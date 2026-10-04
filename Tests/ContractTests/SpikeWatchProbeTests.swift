import XCTest

final class SpikeWatchProbeTests: XCTestCase {
    private func withServer(
        script: String,
        test: (WatchServer) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("spike-watch-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binary = root.appendingPathComponent("watch")
        try ("#!/bin/sh\n" + script).write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let server = WatchServer(binary: binary, contentRoot: root, workingDirectory: root)
        defer {
            server.forceKill()
            try? FileManager.default.removeItem(at: root)
        }
        try server.start()
        try await test(server)
    }

    func testReadinessTimeoutStopsTheChildWithoutHanging() async throws {
        try await withServer(script: "exec /bin/sleep 30\n") { server in
            do {
                _ = try await SpikeWatchProbe.run(server, startupTimeout: .milliseconds(100))
                XCTFail("an unready watch must not appear successful")
            } catch let failure as SpikeFailure {
                XCTAssertEqual(failure.exitCode, 3)
                XCTAssertTrue(failure.description.contains("timed out waiting"))
            }
        }
    }

    func testShutdownTimeoutKillsAWatchIgnoringSIGTERM() async throws {
        let script = """
        trap '' TERM
        echo '{"event":"hello","watch_events_schema":1}' >&2
        echo '{"event":"serve-started","helper":"http://127.0.0.1:49152/__boris/","port":49152}' >&2
        exec /bin/sleep 30
        """
        try await withServer(script: script) { server in
            do {
                _ = try await SpikeWatchProbe.run(server, stopTimeout: .milliseconds(100))
                XCTFail("an unresponsive watch must not appear successful")
            } catch let failure as SpikeFailure {
                XCTAssertEqual(failure.exitCode, 3)
                XCTAssertTrue(failure.description.contains("timed out stopping"))
            }
        }
    }
}
