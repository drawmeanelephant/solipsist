import XCTest

final class BorisRunnerAsyncTests: XCTestCase {
    func testInterruptUnblocksSleep() async throws {
        let handle = RunHandle()
        let started = ContinuousClock.now
        async let output = BorisRunner.run(
            binary: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"],
            handle: handle
        )
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(handle.isRunning)
        handle.terminate()
        let result = try await output
        let elapsed = ContinuousClock.now - started
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertLessThan(elapsed, .seconds(3))
        XCTAssertFalse(handle.isRunning)
    }

    func testEscalateKillsProcessThatIgnoresSIGTERM() async throws {
        let handle = RunHandle()
        let started = ContinuousClock.now
        async let output = BorisRunner.run(
            binary: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "trap '' TERM; exec sleep 30"],
            handle: handle
        )
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(handle.isRunning)
        await handle.escalate(grace: .milliseconds(80))
        let result = try await output
        let elapsed = ContinuousClock.now - started
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertLessThan(elapsed, .seconds(3))
        XCTAssertFalse(handle.isRunning)
    }

    func testTrueStillExitsZero() async throws {
        let output = try await BorisRunner.run(
            binary: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: []
        )
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertTrue(output.stdout.isEmpty)
    }
}
