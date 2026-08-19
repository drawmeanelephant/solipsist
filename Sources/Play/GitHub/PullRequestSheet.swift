import AppKit
import SwiftUI

/// New Pull Request sheet (M16-3 / #185, shared since M17-3 / #192):
/// title + body over the current branch, base defaulting to the
/// source's `defaultBranch` (from the remote, never guessed). When the
/// branch has no upstream it is pushed first (`-u`, M16-2's one-shot)
/// so the PR has a branch to point at; then
/// `POST /repos/{owner}/{repo}/pulls` with the Keychain bearer.
/// Success opens the PR in the browser.
///
/// Presented from two surfaces with byte-for-byte the same flow: the
/// Remote mailbox (M16-3) and the Pull Requests mailbox toolbar
/// (M17-3). `onCreated` runs after a successful PR so the presenting
/// surface refreshes.
struct PullRequestSheet: View {
    let source: GithubSource
    /// Runs after a successful PR (branchStatus / mailbox refresh).
    let onCreated: () -> Void

    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var bodyText = ""
    @State private var base = ""
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var branch: String?
    @State private var hasUpstream = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Pull Request")
                .font(.headline)

            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            LabeledContent("Branch") {
                Text(branch ?? "—")
                    .monospaced()
            }
            LabeledContent("Base") {
                TextField("base branch", text: $base)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }

            TextField("Title", text: $title, axis: .vertical)
                .lineLimit(1...2)
                .textFieldStyle(.roundedBorder)
            TextField("Body", text: $bodyText, axis: .vertical)
                .lineLimit(4...8)
                .textFieldStyle(.roundedBorder)

            HStack {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                    Text(hasUpstream ? "Creating…" : "Pushing branch, then creating…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(hasUpstream ? "Create Pull Request" : "Push & Create Pull Request") {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isWorking
                        || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || branch == nil
                        || base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(20)
        .frame(width: 480, height: 340)
        .task {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let root = try? source.workspaceRoot() else {
            errorText = "Working copy is unavailable."
            return
        }
        let result = await Task.detached {
            GitClone.branchStatus(at: root)
        }.value
        branch = result.branch
        hasUpstream = result.upstream != nil
        // Base = the source's defaultBranch (from the remote, never
        // guessed); the user may override it.
        base = source.defaultBranch
    }

    private func create() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let branch, !trimmedTitle.isEmpty, !trimmedBase.isEmpty, !isWorking else { return }
        isWorking = true
        errorText = nil
        Task {
            // Push the branch first when it has no upstream — the PR
            // needs a remote branch to point at. Reuses the M16-2
            // one-shot; auth rides the credential helper.
            if !hasUpstream {
                let pushResult = await store.pushGithub(source.id)
                guard pushResult.isSuccess else {
                    isWorking = false
                    errorText = RemoteMailboxView.describePush(pushResult)
                    return
                }
            }

            // Load the token from the Keychain (zero-leak: SecureBuffer,
            // never argv/env/logs) and create the PR over the transport.
            let tokenStore = GithubTokenStore()
            let transport = URLSessionGithubTransport()
            do {
                guard let token = try tokenStore.load() else {
                    throw GithubOAuthError.httpStatus(401, message: "No GitHub token in the Keychain. Re-authenticate from Settings → Sources.")
                }
                defer { token.wipe() }
                let created = try await GithubAPIClient.createPullRequest(
                    owner: source.owner,
                    repository: source.repository,
                    title: trimmedTitle,
                    body: bodyText,
                    head: branch,
                    base: trimmedBase,
                    bearer: token,
                    transport: transport
                )
                isWorking = false
                onCreated()
                dismiss()
                if let url = URL(string: created.htmlURL) {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                isWorking = false
                errorText = Self.describe(error)
            }
        }
    }

    static func describe(_ error: Error) -> String {
        if let github = error as? GithubOAuthError {
            switch github {
            case let .httpStatus(status, message):
                return "GitHub returned \(status): \(message)"
            case .invalidResponse:
                return "GitHub returned an unexpected response."
            case let .deviceCodeFailed(code, message):
                return "\(code): \(message)"
            }
        }
        return String(describing: error)
    }
}
