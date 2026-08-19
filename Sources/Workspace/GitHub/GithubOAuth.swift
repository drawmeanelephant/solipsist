import Foundation

/// GitHub device-flow OAuth (M15 / #179). The app owns this surface —
/// boris has no GitHub OAuth. Primary auth for `GithubSource`; a pasted
/// fine-grained PAT is the sheet-level fallback, not part of this flow.
///
/// Flow: `requestDeviceCode` → open `verificationURI` in the browser →
/// `pollUntilToken` (the settings sheet runs it in a cancellable
/// `Task`). The token crosses this boundary in a `SecureBuffer` — never
/// a plain String (zero-leak invariant).
enum GithubOAuth {
    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    /// The server's `slow_down` instruction: add this many seconds.
    static let slowDownStep: TimeInterval = 5

    /// One device-code grant. `interval` is the server's poll cadence —
    /// honored exactly, never faster than asked.
    struct DeviceCodeSession: Sendable, Equatable {
        var deviceCode: String
        var userCode: String
        var verificationURI: URL
        var expiresAt: Date
        var interval: TimeInterval
    }

    /// The granted token. The access token rides in a `SecureBuffer`.
    struct GithubToken: Sendable {
        let token: SecureBuffer
        let scopes: [String]
        let tokenType: String
    }

    /// One poll round. `.pending` / `.slowDown` mean "poll again";
    /// the rest are terminal.
    enum TokenPoll: Sendable {
        case success(GithubToken)
        case pending
        case slowDown
        case expired
        case denied
        case failed(code: String, message: String)
    }

    /// Form-encoded POST transport. Tests inject a stub; CI never
    /// touches GitHub.
    protocol HTTPTransport: Sendable {
        func post(_ url: URL, form: [String: String]) async throws -> Data
    }

    /// Clock seam: the poller sleeps and computes expiry through this,
    /// so tests fast-forward without real sleeps.
    protocol Clock: Sendable {
        var now: Date { get }
        func sleep(nanoseconds: UInt64) async throws
    }

    static func requestDeviceCode(
        clientID: String,
        scope: String,
        transport: HTTPTransport,
        clock: Clock
    ) async throws -> DeviceCodeSession {
        let data = try await transport.post(
            deviceCodeURL,
            form: ["client_id": clientID, "scope": scope]
        )
        let response = try decode(DeviceCodeResponse.self, from: data)
        if let error = response.error {
            throw GithubOAuthError.deviceCodeFailed(
                code: error,
                message: response.errorDescription ?? "GitHub rejected the device-code request."
            )
        }
        guard
            let deviceCode = response.deviceCode,
            let userCode = response.userCode,
            let verification = response.verificationUri,
            let expiresIn = response.expiresIn,
            let interval = response.interval
        else {
            throw GithubOAuthError.invalidResponse
        }
        return DeviceCodeSession(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: URL(string: verification) ?? deviceCodeURL,
            expiresAt: clock.now.addingTimeInterval(TimeInterval(expiresIn)),
            interval: TimeInterval(interval)
        )
    }

    /// One poll of the access-token endpoint. Errors map to `TokenPoll`
    /// cases per GitHub's device-flow contract; nothing is swallowed.
    static func pollForToken(
        deviceCode: String,
        clientID: String,
        transport: HTTPTransport
    ) async throws -> TokenPoll {
        let data = try await transport.post(
            accessTokenURL,
            form: [
                "client_id": clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ]
        )
        let response = try decode(TokenResponse.self, from: data)
        if let error = response.error {
            switch error {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown
            case "expired_token": return .expired
            case "access_denied": return .denied
            default:
                return .failed(code: error, message: response.errorDescription ?? error)
            }
        }
        guard let accessToken = response.accessToken else {
            throw GithubOAuthError.invalidResponse
        }
        let scopes = (response.scope ?? "").split(separator: " ").map(String.init)
        return .success(GithubToken(
            token: SecureBuffer(utf8String: accessToken),
            scopes: scopes,
            tokenType: response.tokenType ?? "bearer"
        ))
    }

    /// Poll loop the settings sheet runs in a `Task`: `.pending` sleeps
    /// the session's interval, `.slowDown` bumps it by `slowDownStep`
    /// (the server's contract), and `Task.checkCancellation()` stops
    /// the poller when the sheet closes. Terminal results pass through.
    static func pollUntilToken(
        session: DeviceCodeSession,
        clientID: String,
        transport: HTTPTransport,
        clock: Clock
    ) async throws -> TokenPoll {
        var current = session
        while true {
            try Task.checkCancellation()
            let result = try await pollForToken(
                deviceCode: current.deviceCode,
                clientID: clientID,
                transport: transport
            )
            switch result {
            case .success, .expired, .denied, .failed:
                return result
            case .pending:
                try await clock.sleep(nanoseconds: nanoseconds(current.interval))
            case .slowDown:
                current.interval += slowDownStep
                try await clock.sleep(nanoseconds: nanoseconds(current.interval))
            }
        }
    }

    private static func nanoseconds(_ interval: TimeInterval) -> UInt64 {
        UInt64(max(0, interval) * 1_000_000_000)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(type, from: data)
        } catch {
            throw GithubOAuthError.invalidResponse
        }
    }

    private struct DeviceCodeResponse: Decodable {
        let deviceCode: String?
        let userCode: String?
        // Camel-cased to match `.convertFromSnakeCase` of "verification_uri"
        // ("verificationURI" would never match and silently decode nil).
        let verificationUri: String?
        let expiresIn: Int?
        let interval: Int?
        let error: String?
        let errorDescription: String?
    }

    private struct TokenResponse: Decodable {
        let accessToken: String?
        let tokenType: String?
        let scope: String?
        let error: String?
        let errorDescription: String?
    }
}

enum GithubOAuthError: Error, Equatable, Sendable {
    case deviceCodeFailed(code: String, message: String)
    case invalidResponse
    case httpStatus(Int)
}

/// Production transport: form-encoded POST over URLSession. Non-2xx
/// responses throw `GithubOAuthError.httpStatus` — never swallowed.
struct URLSessionGithubTransport: GithubOAuth.HTTPTransport {
    func post(_ url: URL, form: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(form)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GithubOAuthError.httpStatus(status)
        }
        return data
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let pairs = fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
                return "\(key)=\(encoded)"
            }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }
}

/// Wall-clock / real-sleep implementation of the seam.
struct SystemGithubClock: GithubOAuth.Clock {
    var now: Date { Date() }

    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(for: .nanoseconds(nanoseconds))
    }
}
