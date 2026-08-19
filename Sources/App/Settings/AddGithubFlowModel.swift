import AppKit
import Foundation
import Observation

/// Drives the Add GitHub Account… sheet (M15 / #179): device-flow OAuth
/// (browser confirm + cancellable poll) or PAT paste, identity via
/// `GET /user`, repo resolution, then clone → Keychain → source. The
/// token lives in a `SecureBuffer` and is wiped on cancel / finish /
/// dismissal.
@MainActor
@Observable
final class AddGithubFlowModel {
    enum Step: Equatable {
        case chooseMethod
        case awaitingAuthorization(userCode: String)
        case tokenInput
        case repo(GithubIdentity)
        case cloning(owner: String, repository: String)
        case done(GithubSource)
    }

    struct GithubIdentity: Equatable {
        let login: String
        let name: String?
        let scopes: [String]
    }

    private(set) var step: Step = .chooseMethod
    var tokenText = ""
    var ownerText = ""
    var repositoryText = ""
    private(set) var repositoryInfo: GithubRepositoryInfo?
    private(set) var errorMessage: String?
    private(set) var isBusy = false

    private let transport: GithubOAuth.HTTPTransport
    private let clock: GithubOAuth.Clock
    private let openBrowser: (URL) -> Void
    private let tokenStore: GithubTokenStore
    private let clientID: String?
    private var token: SecureBuffer?
    private var identity: GithubIdentity?
    private var deviceSession: GithubOAuth.DeviceCodeSession?
    private var pollTask: Task<Void, Never>?
    private var cloneSession: CloneSession?

    static let requestedScope = "repo"

    init(
        transport: GithubOAuth.HTTPTransport = URLSessionGithubTransport(),
        clock: GithubOAuth.Clock = SystemGithubClock(),
        openBrowser: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        tokenStore: GithubTokenStore = GithubTokenStore(),
        clientID: String? = AddGithubFlowModel.bundleClientID()
    ) {
        self.transport = transport
        self.clock = clock
        self.openBrowser = openBrowser
        self.tokenStore = tokenStore
        self.clientID = clientID
    }

    // MARK: - Device flow

    func startDeviceFlow() {
        guard let clientID, !clientID.isEmpty else {
            fail(
                "This build has no GitHub OAuth client id (an operator step — see docs/GITHUB-OAUTH-DESIGN.md §3). Use “Use a token” instead.",
                returningTo: .chooseMethod
            )
            return
        }
        isBusy = true
        pollTask = Task {
            do {
                let session = try await GithubOAuth.requestDeviceCode(
                    clientID: clientID,
                    scope: Self.requestedScope,
                    transport: transport,
                    clock: clock
                )
                deviceSession = session
                openBrowser(session.verificationURI)
                step = .awaitingAuthorization(userCode: session.userCode)
                await pollForToken(session: session, clientID: clientID)
            } catch is CancellationError {
                reset()
            } catch {
                fail(Self.describe(error), returningTo: .chooseMethod)
                isBusy = false
            }
        }
    }

    func reopenAuthorization() {
        guard let deviceSession else { return }
        openBrowser(deviceSession.verificationURI)
    }

    private func pollForToken(session: GithubOAuth.DeviceCodeSession, clientID: String) async {
        do {
            let result = try await GithubOAuth.pollUntilToken(
                session: session,
                clientID: clientID,
                transport: transport,
                clock: clock
            )
            switch result {
            case .success(let granted):
                token = granted.token
                isBusy = false
                await verifyUser(scopes: granted.scopes)
            case .expired:
                fail("The device code expired. Start again.", returningTo: .chooseMethod)
            case .denied:
                fail("Authorization was denied.", returningTo: .chooseMethod)
            case let .failed(code, message):
                fail("\(code): \(message)", returningTo: .chooseMethod)
            case .pending, .slowDown:
                break
            }
        } catch is CancellationError {
            reset()
        } catch {
            fail(Self.describe(error), returningTo: .chooseMethod)
        }
    }

    // MARK: - Token (PAT) fallback

    func chooseTokenInput() {
        step = .tokenInput
    }

    func useToken() {
        let trimmed = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fail("Paste a GitHub personal access token first.", returningTo: .tokenInput)
            return
        }
        tokenText = ""
        token = SecureBuffer(utf8String: trimmed)
        isBusy = true
        Task {
            await verifyUser(scopes: [])
        }
    }

    // MARK: - Identity + repository

    private func verifyUser(scopes: [String]) async {
        guard let token else {
            fail("No token to verify.", returningTo: .chooseMethod)
            return
        }
        isBusy = true
        do {
            let user = try await GithubAPIClient.user(bearer: token, transport: transport)
            let identity = GithubIdentity(login: user.login, name: user.name, scopes: scopes)
            self.identity = identity
            step = .repo(identity)
            isBusy = false
        } catch is CancellationError {
            reset()
        } catch {
            fail(Self.describe(error), returningTo: .chooseMethod)
            isBusy = false
        }
    }

    func resolveRepository() {
        let owner = ownerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = repositoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token else { return }
        guard !owner.isEmpty, !repository.isEmpty else {
            fail("Enter owner and repository (for example: acme/blog).", returningTo: currentRepoStep)
            return
        }
        isBusy = true
        Task {
            do {
                let info = try await GithubAPIClient.repository(
                    owner: owner,
                    repository: repository,
                    bearer: token,
                    transport: transport
                )
                repositoryInfo = info
                isBusy = false
            } catch {
                repositoryInfo = nil
                fail(Self.describe(error), returningTo: currentRepoStep)
                isBusy = false
            }
        }
    }

    // MARK: - Clone + add

    func cloneAndAdd(store: WorkspaceStore) {
        guard let token, let identity, let info = repositoryInfo else { return }
        let owner = ownerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = repositoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty, !repository.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Clone Into"
        panel.message = "\(owner)/\(repository) will be cloned into the folder you choose."
        guard panel.runModal() == .OK, let parent = panel.url else {
            step = currentRepoStep
            return
        }

        let dest = parent.appendingPathComponent(repository, isDirectory: true)
        let urlString = "https://github.com/\(owner)/\(repository).git"
        let helperApp = Bundle.main.executableURL
        let session = CloneSession()
        cloneSession = session
        step = .cloning(owner: owner, repository: repository)
        isBusy = true
        Task {
            // Persist the token first (design §3 step 5): a save failure
            // aborts before any clone, so a retry is clean. A clone
            // failure leaves the token in the Keychain — accepted, the
            // same posture as any OAuth app.
            do {
                try tokenStore.save(token)
            } catch {
                cloneSession = nil
                isBusy = false
                fail("The token could not be saved: \(Self.describe(error))", returningTo: currentRepoStep)
                return
            }

            let result: GitClone.CloneResult
            do {
                result = try await Task.detached {
                    try GitClone.clone(
                        url: urlString,
                        to: dest,
                        session: session,
                        credentialHelperApp: helperApp
                    )
                }.value
            } catch {
                cloneSession = nil
                isBusy = false
                fail("git clone failed: \(Self.describe(error))", returningTo: currentRepoStep)
                return
            }
            cloneSession = nil
            guard result.isSuccess else {
                isBusy = false
                fail(
                    "git clone failed (exit \(result.exitCode)): \(result.stderr)",
                    returningTo: currentRepoStep
                )
                return
            }

            if let source = store.addGithub(
                workingCopy: dest,
                owner: owner,
                repository: repository,
                defaultBranch: info.defaultBranch,
                grantedScopes: identity.scopes
            ) {
                isBusy = false
                step = .done(source)
            } else {
                isBusy = false
                fail("The working copy was cloned but could not be added: \(store.lastError ?? "unknown error")", returningTo: currentRepoStep)
            }
        }
    }

    func cancel() {
        pollTask?.cancel()
        cloneSession?.terminate()
        reset()
    }

    // MARK: - Helpers

    private var currentRepoStep: Step {
        if let identity {
            return .repo(identity)
        }
        return .chooseMethod
    }

    private func fail(_ message: String, returningTo step: Step) {
        errorMessage = message
        self.step = step
    }

    private func reset() {
        pollTask = nil
        cloneSession = nil
        deviceSession = nil
        token?.wipe()
        token = nil
        identity = nil
        repositoryInfo = nil
        errorMessage = nil
        isBusy = false
        step = .chooseMethod
    }

    static func bundleClientID() -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GithubOAuthClientID") as? String,
              !value.isEmpty
        else { return nil }
        return value
    }

    static func describe(_ error: Error) -> String {
        if let github = error as? GithubOAuthError {
            switch github {
            case let .deviceCodeFailed(code, message):
                return "\(code): \(message)"
            case let .httpStatus(status, message):
                return "GitHub returned \(status): \(message)"
            case .invalidResponse:
                return "GitHub returned an unexpected response."
            }
        }
        return String(describing: error)
    }
}
