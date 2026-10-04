import XCTest

@MainActor
final class PreviewSessionLifecycleTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/test/preview/content")
    private let project = URL(fileURLWithPath: "/test/preview")
    private let helper = URL(string: "http://127.0.0.1:49152/__boris/")!

    private final class Servers {
        var values: [WatchServer] = []

        func make(_ engine: BorisEngine, _ content: URL, _ project: URL) -> WatchServer {
            let server = WatchServer(binary: engine.binaryURL, contentRoot: content, workingDirectory: project)
            values.append(server)
            return server
        }
    }

    private final class CoordinatorSpy: PreviewWatchCoordinating {
        var registered: [WatchServer] = []
        var unregistered: [WatchServer] = []

        func registerWatch(_ server: WatchServer) {
            registered.append(server)
        }

        func unregisterWatch(_ server: WatchServer) {
            unregistered.append(server)
        }
    }

    private func makeEngine() throws -> BorisEngine {
        try BorisEngine(binaryURL: URL(fileURLWithPath: "/nonexistent/boris"))
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(10))
    }

    private func makeSession(_ servers: Servers) -> PreviewSession {
        PreviewSession(makeServer: { engine, content, project in servers.make(engine, content, project) })
    }

    func testQueuedServeCannotReviveAStoppedPreview() async throws {
        let servers = Servers()
        let session = makeSession(servers)
        session.start(contentRoot: root, projectRoot: project, engine: try makeEngine(), coordinator: nil)
        servers.values[0].onServe?(helper)
        session.stop()
        try await settle()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertNil(session.serveURL)
        XCTAssertNil(session.boundRootPath)
    }

    func testQueuedServeFromOldSourceCannotBindNewSource() async throws {
        let servers = Servers()
        let session = makeSession(servers)
        defer { session.stop() }
        session.start(contentRoot: root, projectRoot: project, engine: try makeEngine(), coordinator: nil)
        servers.values[0].onServe?(helper)
        let other = root.appendingPathComponent("other")
        session.start(contentRoot: other, projectRoot: project, engine: try makeEngine(), coordinator: nil)
        try await settle()
        XCTAssertEqual(session.phase, .starting)
        XCTAssertNil(session.serveURL)
        XCTAssertTrue(session.isBound(to: other))
    }

    func testQueuedProblemFromOldSourceCannotFailNewSource() async throws {
        let servers = Servers()
        let session = makeSession(servers)
        defer { session.stop() }
        session.start(contentRoot: root, projectRoot: project, engine: try makeEngine(), coordinator: nil)
        servers.values[0].onProblem?("old source failed")
        session.start(contentRoot: root.appendingPathComponent("other"), projectRoot: project, engine: try makeEngine(), coordinator: nil)
        try await settle()
        XCTAssertEqual(session.phase, .starting)
        XCTAssertNil(session.lastProblem)
    }

    func testQueuedExitCannotUnregisterTheReplacementServer() async throws {
        let servers = Servers()
        let coordinator = CoordinatorSpy()
        let session = makeSession(servers)
        defer { session.stop() }
        session.start(contentRoot: root, projectRoot: project, engine: try makeEngine(), coordinator: coordinator)
        servers.values[0].onExit?(WatchExit(exitCode: 2, signalled: false, stderrTail: "old exit"))
        session.start(contentRoot: root.appendingPathComponent("other"), projectRoot: project, engine: try makeEngine(), coordinator: coordinator)
        try await settle()
        XCTAssertEqual(session.phase, .starting)
        XCTAssertEqual(coordinator.registered.count, 2)
        XCTAssertEqual(coordinator.unregistered.count, 1)
        XCTAssertTrue(coordinator.unregistered[0] === servers.values[0])
        servers.values[1].onServe?(helper)
        try await settle()
        XCTAssertEqual(session.serveURL, helper)
    }

    func testCurrentFailuresRemainVisible() async throws {
        let servers = Servers()
        let session = makeSession(servers)
        defer { session.stop() }
        session.start(contentRoot: root, projectRoot: project, engine: try makeEngine(), coordinator: nil)
        servers.values[0].onServe?(helper)
        try await settle()
        servers.values[0].onProblem?("build failed: 1 error")
        try await settle()
        XCTAssertEqual(session.serveURL, helper, "keep the last good build while reporting the failure")
        XCTAssertEqual(session.lastProblem, "build failed: 1 error")
        servers.values[0].onExit?(WatchExit(exitCode: 3, signalled: false, stderrTail: "I/O failed"))
        try await settle()
        XCTAssertTrue(session.isFailure)
        XCTAssertTrue(session.statusText.contains("3"))
        XCTAssertTrue(session.statusText.contains("I/O failed"))
    }
}
