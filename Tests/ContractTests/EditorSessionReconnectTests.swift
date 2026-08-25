import XCTest

/// #232: auto-reconnect when the `boris-editor` host crashes spontaneously.
/// Drives the real `EditorSession` state machine against an in-memory host,
/// so no binaries are spawned; the injected millisecond backoff keeps every
/// scenario well under a second.
@MainActor
final class EditorSessionReconnectTests: XCTestCase {
    // MARK: Harness

    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("EditorSessionReconnectTests-content")
    private let project = FileManager.default.temporaryDirectory
        .appendingPathComponent("EditorSessionReconnectTests-project")
    private let tokenA = URL(string: "http://127.0.0.1:49152/#token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")!
    private let tokenB = URL(string: "http://127.0.0.1:49153/#token=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")!

    private func makeEngine() throws -> BorisEngine {
        try BorisEngine(binaryURL: URL(fileURLWithPath: "/nonexistent/boris"))
    }

    /// In-memory stand-in for `EditorServer`. Tests fire `connect` / `crash`
    /// by hand, exactly like the process callbacks would arrive.
    private final class FakeHost: EditorHost {
        var onConnect: ((URL) -> Void)?
        var onExit: ((EditorExit) -> Void)?

        private(set) var editorURL: URL?
        private(set) var stopCount = 0
        var isRunning = true

        func connect(url: URL) {
            editorURL = url
            isRunning = true
            onConnect?(url)
        }

        func crash(exitCode: Int32, signalled: Bool = false) {
            isRunning = false
            onExit?(EditorExit(exitCode: exitCode, signalled: signalled, stderrTail: ""))
        }

        func stop() {
            stopCount += 1
            isRunning = false
        }
    }

    private final class HostRecorder {
        private(set) var hosts: [FakeHost] = []

        var last: FakeHost? { hosts.last }

        func factory(engine: BorisEngine, workingDirectory: URL) throws -> any EditorHost {
            let host = FakeHost()
            hosts.append(host)
            return host
        }
    }

    /// Backoff small enough that auto-restarts land inside the test, large
    /// enough that `.reconnecting` stays observable between ticks.
    private let baseDelay = Duration.milliseconds(100)

    private func makeSession(_ recorder: HostRecorder) -> EditorSession {
        EditorSession(
            makeHost: { engine, workDir in try recorder.factory(engine: engine, workingDirectory: workDir) },
            reconnectBaseDelay: baseDelay
        )
    }

    private func connectedURL(of session: EditorSession) -> URL? {
        if case .connected(let url) = session.phase { return url }
        return nil
    }

    private func reconnectingAttempt(of session: EditorSession) -> Int? {
        if case .reconnecting(let attempt) = session.phase { return attempt }
        return nil
    }

    /// Lets enqueued MainActor tasks (`handleConnect` / `handleExit`) run.
    private func settle(milliseconds: Int = 10) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func waitForHosts(_ recorder: HostRecorder, _ count: Int) async throws {
        var waited = 0
        while recorder.hosts.count < count {
            guard waited < 2000 else {
                XCTFail("timed out waiting for \(count) hosts (have \(recorder.hosts.count))")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
            waited += 10
        }
    }

    private func waitForConnected(_ session: EditorSession, _ url: URL) async throws {
        var waited = 0
        while connectedURL(of: session) != url {
            guard waited < 2000 else {
                XCTFail("timed out waiting for connected phase (\(session.phase))")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
            waited += 10
        }
    }

    /// start → host 1 reports its token URL.
    private func startAndConnect(_ session: EditorSession, _ recorder: HostRecorder) async throws {
        session.start(contentRoot: root, projectRoot: project, engine: try makeEngine())
        try await waitForHosts(recorder, 1)
        recorder.last?.connect(url: tokenA)
        try await waitForConnected(session, tokenA)
        XCTAssertNil(session.transientNotice)
    }

    // MARK: Auto-reconnect fires

    func testAutoReconnectFiresOnNonZeroExit() async throws {
        let recorder = HostRecorder()
        let session = makeSession(recorder)
        defer { session.stop() }

        try await startAndConnect(session, recorder)

        recorder.hosts[0].crash(exitCode: 1)
        await settle()
        XCTAssertEqual(reconnectingAttempt(of: session), 1)
        XCTAssertFalse(session.isFailure)

        try await waitForHosts(recorder, 2)
        XCTAssertEqual(
            recorder.hosts[0].stopCount, 0,
            "a crashed process is already dead; teardown must not SIGTERM it again"
        )

        recorder.hosts[1].connect(url: tokenB)
        try await waitForConnected(session, tokenB)
        XCTAssertEqual(session.transientNotice, "Editor host restarted")
    }

    func testAutoReconnectDoesNotFireOnCleanExit() async throws {
        let recorder = HostRecorder()
        let session = makeSession(recorder)
        defer { session.stop() }

        try await startAndConnect(session, recorder)

        recorder.hosts[0].crash(exitCode: 0)
        await settle(milliseconds: 120)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.transientNotice)
        XCTAssertEqual(recorder.hosts.count, 1, "exit 0 must never trigger a reconnect")
    }

    func testAutoReconnectDoesNotFireWhenStartFails() {
        let recorder = HostRecorder()
        let session = makeSession(recorder)
        defer { session.stop() }

        // No engine: permanent configuration error, not a crash (#232).
        session.start(contentRoot: root, projectRoot: project, engine: nil)
        XCTAssertEqual(session.phase, .failed(.engineUnavailable))
        XCTAssertTrue(recorder.hosts.isEmpty)
    }

    func testSignalledExitCountsAsCrash() async throws {
        let recorder = HostRecorder()
        let session = makeSession(recorder)
        defer { session.stop() }

        try await startAndConnect(session, recorder)

        recorder.hosts[0].crash(exitCode: 0, signalled: true)
        try await waitForHosts(recorder, 2)
        XCTAssertEqual(reconnectingAttempt(of: session), nil, "restart may already have fired")
        XCTAssertFalse(session.isFailure, "a signalled death must be treated as a crash, not a clean exit")
    }

    // MARK: Cap and reset

    func testAutoReconnectStopsAfterMaxAttempts() async throws {
        let recorder = HostRecorder()
        let session = makeSession(recorder)
        defer { session.stop() }

        try await startAndConnect(session, recorder)

        for attempt in 1 ... EditorAutoReconnect.maxAttempts {
            recorder.last?.crash(exitCode: 1)
            await settle()
            XCTAssertEqual(reconnectingAttempt(of: session), attempt, "crash \(attempt)")
            try await waitForHosts(recorder, 1 + attempt)
        }
        // The third restart is underway; nothing has connected since.
        XCTAssertEqual(session.phase, .starting)

        // Fourth crash within the window: cap reached, manual restart required.
        recorder.last?.crash(exitCode: 1)
        await settle()
        guard case .failed(let error) = session.phase else {
            return XCTFail("expected failed phase, got \(session.phase)")
        }
        XCTAssertEqual(error, .crashLoop(stderrTail: ""))
        XCTAssertTrue(error.message.contains("Manual restart required"), error.message)
        XCTAssertTrue(error.message.contains("3 times"), error.message)

        await settle(milliseconds: 120)
        XCTAssertEqual(recorder.hosts.count, 4, "no fifth host may spawn after the cap")
        XCTAssertTrue(session.isFailure)
    }

    func testAutoReconnectResetsOnSuccess() async throws {
        let recorder = HostRecorder()
        let session = makeSession(recorder)
        defer { session.stop() }

        try await startAndConnect(session, recorder)

        // First crash-and-recover cycle.
        recorder.hosts[0].crash(exitCode: 1)
        try await waitForHosts(recorder, 2)
        recorder.hosts[1].connect(url: tokenB)
        try await waitForConnected(session, tokenB)
        XCTAssertEqual(session.transientNotice, "Editor host restarted")

        // A later crash counts from scratch again.
        recorder.hosts[1].crash(exitCode: 1)
        await settle()
        XCTAssertEqual(reconnectingAttempt(of: session), 1, "a successful connect must reset the counter")
        XCTAssertNil(session.transientNotice, "leaving connected clears the notice")
    }

    func testManualRestartResetsAttemptCounter() async throws {
        let recorder = HostRecorder()
        let session = makeSession(recorder)
        defer { session.stop() }

        try await startAndConnect(session, recorder)

        recorder.hosts[0].crash(exitCode: 1)
        try await waitForHosts(recorder, 2)

        session.restart()
        try await waitForHosts(recorder, 3)
        XCTAssertEqual(recorder.hosts[1].stopCount, 1)

        // The manual restart wiped the earlier crash from the books.
        recorder.hosts[2].crash(exitCode: 1)
        await settle()
        XCTAssertEqual(reconnectingAttempt(of: session), 1)
    }

    // MARK: Manual teardown wins

    func testAutoReconnectDoesNotFireOnWindowClose() async throws {
        let recorder = HostRecorder()
        let session = makeSession(recorder)

        try await startAndConnect(session, recorder)

        recorder.hosts[0].crash(exitCode: 1)
        await settle() // phase flips to .reconnecting; the backoff task is pending
        XCTAssertEqual(reconnectingAttempt(of: session), 1)

        // Window close (.onDisappear → stop()) must cancel the pending task.
        session.stop()

        await settle(milliseconds: 150)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(recorder.hosts.count, 1, "closing the window must never spawn another host")
        XCTAssertNil(session.transientNotice)
    }

    func testStopBeforeExitArrivesSwallowsTheExit() async throws {
        let recorder = HostRecorder()
        let session = makeSession(recorder)
        defer { session.stop() }

        try await startAndConnect(session, recorder)

        // The exit callback is enqueued, then a manual stop() runs first:
        // callbacks nil'd and server cleared before handleExit executes, so
        // the dying host can never schedule a reconnect behind our back.
        recorder.hosts[0].crash(exitCode: 1)
        session.stop()

        await settle(milliseconds: 150)
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(recorder.hosts.count, 1)
    }

    // MARK: Source switch while pending

    func testSourceSwitchCancelsPendingReconnect() async throws {
        let recorder = HostRecorder()
        // Long backoff so the switch reliably lands while a restart is pending.
        let session = EditorSession(
            makeHost: { engine, workDir in try recorder.factory(engine: engine, workingDirectory: workDir) },
            reconnectBaseDelay: .milliseconds(500)
        )
        defer { session.stop() }

        try await startAndConnect(session, recorder)

        recorder.hosts[0].crash(exitCode: 1)
        await settle()
        XCTAssertEqual(reconnectingAttempt(of: session), 1)

        // The user picks a different source: .task(id:) re-runs start() with
        // new roots, which tears down and cancels the pending auto-restart.
        let otherRoot = root.appendingPathComponent("other")
        session.start(contentRoot: otherRoot, projectRoot: project, engine: try makeEngine())
        try await waitForHosts(recorder, 2)
        XCTAssertEqual(session.phase, .starting)

        await settle(milliseconds: 600)
        XCTAssertEqual(recorder.hosts.count, 2, "the cancelled backoff task must not add hosts")
    }

    // MARK: Policy arithmetic (pure)

    func testPolicyRetriesGrowThenGiveUp() {
        XCTAssertEqual(EditorAutoReconnect.decision(crashesInWindow: 1), .retry(attempt: 1))
        XCTAssertEqual(EditorAutoReconnect.decision(crashesInWindow: 2), .retry(attempt: 2))
        XCTAssertEqual(EditorAutoReconnect.decision(crashesInWindow: 3), .retry(attempt: 3))
        XCTAssertEqual(EditorAutoReconnect.decision(crashesInWindow: 4), .giveUp)
    }

    func testPolicyPrunesCrashesOutsideWindow() {
        let now = ContinuousClock.now
        let fresh = now - Duration.seconds(5)
        let boundary = now - EditorAutoReconnect.window
        let stale = now - Duration.seconds(45)
        XCTAssertEqual(EditorAutoReconnect.prune([stale], now: now), [])
        XCTAssertEqual(EditorAutoReconnect.prune([fresh], now: now), [fresh])
        XCTAssertEqual(EditorAutoReconnect.prune([boundary], now: now), [boundary])
    }
}
