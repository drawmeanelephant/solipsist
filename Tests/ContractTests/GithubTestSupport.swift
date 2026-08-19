import Foundation

// Shared GitHub test doubles: queued-response transport + fast-forward
// clock. No network in CI — everything is injected.

func json(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

/// Records calls and returns queued responses per URL. An actor: the
/// poll loop and the test both touch it across await points.
actor StubTransport: GithubOAuth.HTTPTransport {
    struct RecordedCall: Equatable, Sendable {
        let url: URL
        /// Form body for POSTs; nil for GETs.
        let form: [String: String]?
        /// Bearer token bytes for GETs; nil for POSTs.
        let bearerBytes: [UInt8]?
    }

    private var queues: [URL: [Result<Data, Error>]] = [:]
    private(set) var calls: [RecordedCall] = []

    /// When true, an exhausted queue answers `authorization_pending`
    /// instead of throwing — for cancellation tests that must spin.
    private let defaultToPending: Bool

    init(defaultToPending: Bool = false) {
        self.defaultToPending = defaultToPending
    }

    var recorded: [RecordedCall] {
        calls
    }

    func enqueue(_ data: Data, for url: URL) {
        queues[url, default: []].append(.success(data))
    }

    func enqueue(error: Error, for url: URL) {
        queues[url, default: []].append(.failure(error))
    }

    func post(_ url: URL, form: [String: String]) async throws -> Data {
        try await respond(to: url, form: form, bearerBytes: nil)
    }

    func get(_ url: URL, bearer: SecureBuffer) async throws -> Data {
        try await respond(to: url, form: nil, bearerBytes: bearer.copyBytes())
    }

    private func respond(
        to url: URL,
        form: [String: String]?,
        bearerBytes: [UInt8]?
    ) async throws -> Data {
        calls.append(RecordedCall(url: url, form: form, bearerBytes: bearerBytes))
        var queue = queues[url] ?? []
        let next = queue.isEmpty ? nil : queue.removeFirst()
        queues[url] = queue
        guard let next else {
            if defaultToPending {
                return Self.pendingJSON
            }
            throw GithubOAuthError.invalidResponse
        }
        return try next.get()
    }

    private static let pendingJSON = (try? JSONSerialization.data(
        withJSONObject: ["error": "authorization_pending"]
    )) ?? Data()
}

/// Fast-forward clock: sleeps return immediately and record their
/// requested durations so the poll loop is testable without real waits.
actor StubClock: GithubOAuth.Clock {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    private(set) var sleptNanoseconds: [UInt64] = []

    func sleep(nanoseconds: UInt64) async throws {
        sleptNanoseconds.append(nanoseconds)
    }
}
