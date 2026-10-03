import XCTest

final class BorisEngineConcurrencyTests: XCTestCase {
    private struct Fixture {
        let engine: BorisEngine
        let root: URL
        let binary: URL
    }

    private func makeEngine() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-serial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binary = root.appendingPathComponent("engine")
        let script = """
        #!/bin/sh
        if ! mkdir '\(root.path)/active' 2>/dev/null; then
            echo 'overlapping one-shots' >&2
            exit 73
        fi
        trap 'rmdir "\(root.path)/active"' EXIT
        echo "$1" >> '\(root.path)/calls'
        if [ -e '\(root.path)/hold' ]; then
            while [ ! -e '\(root.path)/release' ]; do sleep 0.01; done
        fi
        sleep 0.15
        echo 'test-engine'
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        let engine = try BorisEngine(binaryURL: binary)
        return Fixture(engine: engine, root: root, binary: binary)
    }

    func testConcurrentOneShotsNeverOverlap() async throws {
        let fixture = try makeEngine()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        async let first = fixture.engine.version()
        async let second = fixture.engine.version()
        let results = try await [first, second]
        XCTAssertEqual(results.map(\.exitCode), [0, 0], "actor reentrancy must not replace the active process slot")
        XCTAssertEqual(results.map(\.line), ["test-engine", "test-engine"])
    }

    func testKitToolUsesTheSameOneShotSlot() async throws {
        let fixture = try makeEngine()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        async let engineResult = fixture.engine.version()
        async let toolResult = fixture.engine.runTool(binary: fixture.binary, arguments: ["tool"])
        let results = try await (engineResult, toolResult)
        XCTAssertEqual(results.0.exitCode, 0)
        XCTAssertEqual(results.1.exitCode, 0)
        XCTAssertEqual(results.1.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "test-engine")
    }

    func testLaunchFailureReleasesTheSlot() async throws {
        let fixture = try makeEngine()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            _ = try await fixture.engine.runTool(binary: fixture.root.appendingPathComponent("missing"), arguments: [])
            XCTFail("launch must fail")
        } catch {}
        let result = try await fixture.engine.version()
        XCTAssertEqual(result.exitCode, 0)
    }

    func testCancelledWaiterDoesNotLaunchOrKeepTheSlot() async throws {
        let fixture = try makeEngine()
        let engine = fixture.engine
        let root = fixture.root
        defer {
            engine.forceKill()
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertTrue(FileManager.default.createFile(atPath: root.appendingPathComponent("hold").path, contents: nil))
        let first = Task { try await engine.version() }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("active").path) {
            guard ContinuousClock.now < deadline else {
                engine.forceKill()
                _ = try await first.value
                return XCTFail("first child did not start")
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        let waiter = Task { try await engine.version() }
        try await Task.sleep(for: .milliseconds(10))
        waiter.cancel()
        XCTAssertTrue(FileManager.default.createFile(atPath: root.appendingPathComponent("release").path, contents: nil))
        let firstResult = try await first.value
        XCTAssertEqual(firstResult.exitCode, 0)
        do {
            _ = try await waiter.value
            XCTFail("cancelled waiter must not run")
        } catch is CancellationError {
            // Expected: the child was never launched.
        }
        let calls = try String(contentsOf: root.appendingPathComponent("calls"), encoding: .utf8)
        XCTAssertEqual(calls.split(separator: "\n").count, 1)
        let next = try await engine.version()
        XCTAssertEqual(next.exitCode, 0, "cancelling a waiter must not strand the slot")
    }
}
