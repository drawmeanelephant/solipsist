import XCTest

final class GithubOAuthTests: XCTestCase {
    // MARK: - Device code request

    func testRequestDeviceCodeParsesSession() async throws {
        let transport = StubTransport()
        await transport.enqueue(
            json(["device_code": "dc-123", "user_code": "ABCD-EFGH",
                  "verification_uri": "https://github.com/login/device", "expires_in": 900, "interval": 5]),
            for: GithubOAuth.deviceCodeURL
        )
        let clock = StubClock()

        let session = try await GithubOAuth.requestDeviceCode(
            clientID: "client-1",
            scope: "repo",
            transport: transport,
            clock: clock
        )

        XCTAssertEqual(session.deviceCode, "dc-123")
        XCTAssertEqual(session.userCode, "ABCD-EFGH")
        XCTAssertEqual(session.verificationURI, URL(string: "https://github.com/login/device"))
        XCTAssertEqual(session.interval, 5)
        let expectedExpiry = await clock.now.addingTimeInterval(900)
        XCTAssertEqual(session.expiresAt, expectedExpiry)
        let recorded = await transport.recorded
        let call = try XCTUnwrap(recorded.first)
        XCTAssertEqual(call.url, GithubOAuth.deviceCodeURL)
        XCTAssertEqual(call.form["client_id"], "client-1")
        XCTAssertEqual(call.form["scope"], "repo")
        XCTAssertEqual(call.form.count, 2, "only client_id + scope, never more")
    }

    func testRequestDeviceCodeSurfacesErrors() async {
        let transport = StubTransport()
        await transport.enqueue(
            json(["error": "incorrect_client_credentials", "error_description": "The client_id passed is incorrect"]),
            for: GithubOAuth.deviceCodeURL
        )
        do {
            _ = try await GithubOAuth.requestDeviceCode(
                clientID: "bad",
                scope: "repo",
                transport: transport,
                clock: StubClock()
            )
            XCTFail("expected deviceCodeFailed")
        } catch let GithubOAuthError.deviceCodeFailed(code, message) {
            XCTAssertEqual(code, "incorrect_client_credentials")
            XCTAssertTrue(message.contains("client_id"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let bad = StubTransport()
        await bad.enqueue(json(["unexpected": true]), for: GithubOAuth.deviceCodeURL)
        do {
            _ = try await GithubOAuth.requestDeviceCode(
                clientID: "client-1",
                scope: "repo",
                transport: bad,
                clock: StubClock()
            )
            XCTFail("expected invalidResponse")
        } catch GithubOAuthError.invalidResponse {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Single poll rounds

    func testPollForTokenHandlesResponseShapes() async throws {
        let transport = StubTransport()
        await transport.enqueue(
            json(["access_token": "gho_abc123", "token_type": "bearer", "scope": "repo user"]),
            for: GithubOAuth.accessTokenURL
        )
        let poll = try await GithubOAuth.pollForToken(
            deviceCode: "dc-123",
            clientID: "client-1",
            transport: transport
        )
        guard case .success(let token) = poll else {
            return XCTFail("expected success, got \(poll)")
        }
        XCTAssertEqual(token.token.copyBytes(), Array("gho_abc123".utf8))
        XCTAssertEqual(token.scopes, ["repo", "user"])
        XCTAssertEqual(token.tokenType, "bearer")

        let bad = StubTransport()
        await bad.enqueue(json(["token_type": "bearer"]), for: GithubOAuth.accessTokenURL)
        do {
            _ = try await GithubOAuth.pollForToken(deviceCode: "dc-123", clientID: "client-1", transport: bad)
            XCTFail("expected invalidResponse")
        } catch GithubOAuthError.invalidResponse {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testPollForTokenMapsErrorCodes() async throws {
        let transport = StubTransport()
        let cases: [(code: String, expected: GithubOAuth.TokenPoll)] = [
            ("authorization_pending", .pending),
            ("slow_down", .slowDown),
            ("expired_token", .expired),
            ("access_denied", .denied),
            ("unexpected_code", .failed(code: "unexpected_code", message: "detail")),
        ]
        for item in cases {
            await transport.enqueue(
                json(["error": item.code, "error_description": "detail"]),
                for: GithubOAuth.accessTokenURL
            )
        }
        for item in cases {
            let poll = try await GithubOAuth.pollForToken(
                deviceCode: "dc-123",
                clientID: "client-1",
                transport: transport
            )
            assertPoll(poll, matches: item.expected)
        }

        let recorded = await transport.recorded
        let call = try XCTUnwrap(recorded.first)
        XCTAssertEqual(call.url, GithubOAuth.accessTokenURL)
        XCTAssertEqual(call.form["grant_type"], "urn:ietf:params:oauth:grant-type:device_code")
        XCTAssertEqual(call.form["device_code"], "dc-123")
        XCTAssertEqual(call.form["client_id"], "client-1")
    }

    // MARK: - Poll loop

    func testPollUntilTokenLoopsPendingThenSucceeds() async throws {
        let transport = StubTransport()
        await transport.enqueue(json(["error": "authorization_pending"]), for: GithubOAuth.accessTokenURL)
        await transport.enqueue(json(["error": "authorization_pending"]), for: GithubOAuth.accessTokenURL)
        await transport.enqueue(json(["access_token": "gho_final", "scope": "repo"]), for: GithubOAuth.accessTokenURL)
        let clock = StubClock()

        let poll = try await GithubOAuth.pollUntilToken(session: makeSession(interval: 5), clientID: "client-1", transport: transport, clock: clock)

        guard case .success(let token) = poll else {
            return XCTFail("expected success, got \(poll)")
        }
        XCTAssertEqual(token.token.copyBytes(), Array("gho_final".utf8))
        let slept = await clock.sleptNanoseconds
        XCTAssertEqual(slept, [5_000_000_000, 5_000_000_000])
    }

    func testPollUntilTokenSlowDownAndTerminalResults() async throws {
        let slowTransport = StubTransport()
        await slowTransport.enqueue(json(["error": "authorization_pending"]), for: GithubOAuth.accessTokenURL)
        await slowTransport.enqueue(json(["error": "slow_down"]), for: GithubOAuth.accessTokenURL)
        await slowTransport.enqueue(json(["access_token": "gho_final", "scope": "repo"]), for: GithubOAuth.accessTokenURL)
        let slowClock = StubClock()

        let slowPoll = try await GithubOAuth.pollUntilToken(session: makeSession(interval: 5), clientID: "client-1", transport: slowTransport, clock: slowClock)
        guard case .success = slowPoll else {
            return XCTFail("expected success, got \(slowPoll)")
        }
        let slowSlept = await slowClock.sleptNanoseconds
        XCTAssertEqual(
            slowSlept,
            [5_000_000_000, 10_000_000_000],
            "slow_down bumps the interval by \(GithubOAuth.slowDownStep)s"
        )

        let expiredTransport = StubTransport()
        await expiredTransport.enqueue(json(["error": "authorization_pending"]), for: GithubOAuth.accessTokenURL)
        await expiredTransport.enqueue(json(["error": "expired_token"]), for: GithubOAuth.accessTokenURL)
        let expiredClock = StubClock()

        let expiredPoll = try await GithubOAuth.pollUntilToken(session: makeSession(interval: 5), clientID: "client-1", transport: expiredTransport, clock: expiredClock)
        guard case .expired = expiredPoll else {
            return XCTFail("expected expired, got \(expiredPoll)")
        }
        let expiredSlept = await expiredClock.sleptNanoseconds
        XCTAssertEqual(expiredSlept, [5_000_000_000], "no sleep after a terminal result")
    }

    func testPollUntilTokenCancellationStopsPoller() async throws {
        let transport = StubTransport(defaultToPending: true)
        let session = makeSession(interval: 5)

        let task = Task {
            try await GithubOAuth.pollUntilToken(session: session, clientID: "client-1", transport: transport, clock: StubClock())
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected — the sheet closed, the poller stopped.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - SourceItem payload

    func testSourceItemGithubExhaustiveness() {
        let source = makeSource()
        let item = SourceItem.github(source)

        XCTAssertEqual(item.id, source.id)
        XCTAssertEqual(item.title, "acme/blog")
        XCTAssertEqual(item.kind, .github)
        XCTAssertEqual(item.symbolName, "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(item.detailLine, "/tmp/blog")
        XCTAssertTrue(item.isAvailable)
        XCTAssertNil(item.branch)
        XCTAssertEqual(source.tokenAccount, "github:acme/blog")
        XCTAssertEqual(source.remoteURL, URL(string: "https://github.com/acme/blog"))

        var unavailable = source
        unavailable.isAvailable = false
        unavailable.branch = "main"
        let badItem = SourceItem.github(unavailable)
        XCTAssertFalse(badItem.isAvailable)
        XCTAssertEqual(badItem.branch, "main")
    }

    func testGithubSourceRoundTripExcludesTransientFields() throws {
        var source = makeSource()
        source.isAvailable = false
        source.branch = "main"
        source.isSyncing = true
        source.lastSyncError = "boom"

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(GithubSource.self, from: data)

        XCTAssertTrue(decoded.isAvailable, "transient fields reset on decode")
        XCTAssertNil(decoded.branch)
        XCTAssertFalse(decoded.isSyncing)
        XCTAssertNil(decoded.lastSyncError)
        XCTAssertEqual(decoded.owner, "acme")
        XCTAssertEqual(decoded.repository, "blog")
        XCTAssertEqual(decoded.defaultBranch, "main")
        XCTAssertEqual(decoded.grantedScopes, ["repo"])

        let raw = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(raw.contains("\"isAvailable\""))
        XCTAssertFalse(raw.contains("\"branch\""))
        XCTAssertFalse(raw.contains("\"lastSyncError\""))
        XCTAssertFalse(raw.contains("\"isSyncing\""))
    }

    func testPersistedWorkspaceRoundTripsGithubSources() throws {
        let github = makeSource()
        let payload = PersistedWorkspace(sources: [], selected: nil, mailbox: nil, github: [github])

        let decoded = try WorkspacePersistence.decode(try WorkspacePersistence.encode(payload))

        XCTAssertEqual(decoded.github, [github])
        XCTAssertTrue(decoded.sources.isEmpty)
    }

    // MARK: - Helpers

    private func assertPoll(
        _ poll: GithubOAuth.TokenPoll,
        matches expected: GithubOAuth.TokenPoll,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (poll, expected) {
        case (.pending, .pending), (.slowDown, .slowDown), (.expired, .expired), (.denied, .denied):
            break
        case let (.failed(aCode, aMessage), .failed(bCode, bMessage)):
            XCTAssertEqual(aCode, bCode, file: file, line: line)
            XCTAssertEqual(aMessage, bMessage, file: file, line: line)
        case (.success, .success):
            break
        default:
            XCTFail("poll \(poll) != expected \(expected)", file: file, line: line)
        }
    }
}

private func json(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

private func makeSession(interval: TimeInterval) -> GithubOAuth.DeviceCodeSession {
    GithubOAuth.DeviceCodeSession(
        deviceCode: "dc-123",
        userCode: "ABCD-EFGH",
        verificationURI: URL(string: "https://github.com/login/device")!,
        expiresAt: Date(timeIntervalSince1970: 1_700_000_900),
        interval: interval
    )
}

private func makeSource() -> GithubSource {
    GithubSource(
        id: SourceID(),
        title: "acme/blog",
        owner: "acme",
        repository: "blog",
        defaultBranch: "main",
        bookmarkData: Data([1, 2, 3]),
        displayPath: "/tmp/blog",
        grantedScopes: ["repo"]
    )
}

/// Records calls and returns queued responses per URL. An actor: the
/// poll loop and the test both touch it across await points.
private actor StubTransport: GithubOAuth.HTTPTransport {
    struct RecordedCall: Equatable, Sendable {
        let url: URL
        let form: [String: String]
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

    func post(_ url: URL, form: [String: String]) async throws -> Data {
        calls.append(RecordedCall(url: url, form: form))
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
private actor StubClock: GithubOAuth.Clock {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    private(set) var sleptNanoseconds: [UInt64] = []

    func sleep(nanoseconds: UInt64) async throws {
        sleptNanoseconds.append(nanoseconds)
    }
}
