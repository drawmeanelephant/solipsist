import Darwin
import XCTest

final class BorisProcessLifecycleTests: XCTestCase {
    private struct Fixture: Sendable {
        let root: URL
        let binary: URL
        let engine: BorisEngine
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("process-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let binary = root.appendingPathComponent("engine")
        let script = """
        #!/bin/bash
        case "$1" in
          hold|next)
            echo $$ > '\(root.path)/'"$1"'.pid'
            exec /bin/sleep 30
            ;;
          broken-stdin)
            trap '' TERM
            exec 0<&-
            echo $$ > '\(root.path)/broken-stdin.pid'
            exec /bin/sleep 30
            ;;
          *)
            echo 'test-engine'
            ;;
        esac
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        return Fixture(root: root, binary: binary, engine: try BorisEngine(binaryURL: binary))
    }

    func testQueuedCancellationCompletesBeforeTheActiveChildExits() async throws {
        let fixture = try makeFixture()
        let engine = fixture.engine
        defer {
            engine.forceKill()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let first = Task { try await engine.runTool(binary: fixture.binary, arguments: ["hold"]) }
        let pid = try await waitForPID(in: fixture.root, name: "hold")
        let cancelled = expectation(description: "queued cancellation completes while the first child is alive")
        let waiter = Task {
            do {
                _ = try await engine.version()
                XCTFail("a cancelled queued call must not launch")
            } catch is CancellationError {
                cancelled.fulfill()
            } catch {
                XCTFail("expected CancellationError, got \(error)")
                cancelled.fulfill()
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        waiter.cancel()
        await fulfillment(of: [cancelled], timeout: 0.5)
        XCTAssertEqual(kill(pid, 0), 0, "cancelling a waiter must not interrupt the active child")

        let survivor = Task { try await engine.version() }
        engine.forceKill()
        _ = try await first.value
        await waiter.value
        let result = try await survivor.value
        XCTAssertEqual(result.exitCode, 0, "removing a cancelled waiter must preserve the next caller")
    }

    func testEscalationCannotKillTheNextQueuedChild() async throws {
        let fixture = try makeFixture()
        let engine = fixture.engine
        defer {
            engine.forceKill()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let first = Task { try await engine.runTool(binary: fixture.binary, arguments: ["hold"]) }
        _ = try await waitForPID(in: fixture.root, name: "hold")
        let next = Task { try await engine.runTool(binary: fixture.binary, arguments: ["next"]) }
        try await Task.sleep(for: .milliseconds(30))
        let escalation = Task { await engine.escalate(grace: .milliseconds(300)) }
        _ = try await first.value
        let nextPID = try await waitForPID(in: fixture.root, name: "next")
        await escalation.value
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(kill(nextPID, 0), 0, "escalation belongs to the original child, not the mutable slot")
        engine.forceKill()
        _ = try await next.value
    }

    func testStdinWriteFailureIsThrownOnlyAfterTheChildIsReaped() async throws {
        let fixture = try makeFixture()
        let handle = RunHandle()
        defer {
            handle.forceKill()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        let output = Task {
            do {
                _ = try await BorisRunner.run(
                    binary: fixture.binary,
                    arguments: ["broken-stdin"],
                    handle: handle,
                    stdinText: String(repeating: "fixture text\n", count: 100_000)
                )
                XCTFail("the closed stdin must report a write failure")
            } catch {
                XCTAssertFalse(error is BorisRunnerError, "preserve the original stdin error, not a launch error")
            }
        }
        _ = try await waitForPID(in: fixture.root, name: "broken-stdin")
        await output.value
        XCTAssertFalse(handle.isRunning, "returning early would let the engine replace a live child")
    }

    func testSecretWriteFailurePreservesTheErrorAndWipesTheBuffer() async throws {
        let fixture = try makeFixture()
        let handle = RunHandle()
        let secret = SecureBuffer(bytes: [UInt8](repeating: 88, count: 1_000_000))
        defer {
            handle.forceKill()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        do {
            _ = try await BorisRunner.run(
                binary: fixture.binary,
                arguments: ["broken-stdin"],
                handle: handle,
                stdin: secret
            )
            XCTFail("the closed stdin must report a write failure")
        } catch StdinSecretWriterError.writeFailed(let message) {
            XCTAssertTrue(message.contains("errno: \(EPIPE)"))
        }
        XCTAssertTrue(secret.isEmpty)
        XCTAssertFalse(handle.isRunning)
    }

    private func waitForPID(in root: URL, name: String) async throws -> Int32 {
        let file = root.appendingPathComponent("\(name).pid")
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if let text = try? String(contentsOf: file, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "BorisProcessLifecycleTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Timed out waiting for \(name) child",
        ])
    }
}
