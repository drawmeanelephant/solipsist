import Foundation
import XCTest

/// Tests for the subprocess model invariant (AGENTS.md hard boundary #5,
/// #213): one `RunHandle` slot for one-shots, at most two long-lived watch
/// daemons (`WatchServer` + `ValidateWatch`), and the SIGTERM → reapGrace →
/// SIGKILL escalation path.
///
/// We do not spin up a real Boris binary here — we use `/bin/sleep` and a
/// SIGTERM-immune bash trap to exercise the process lifecycle paths.
final class SubprocessInvariantTests: XCTestCase {
    // MARK: - RunHandle serializes one-shots

    /// A single RunHandle holds at most one Process at a time. Attaching a
    /// second process implicitly abandons the first (it keeps running but
    /// the handle no longer references it).
    func testRunHandleSerializesOneShots() async throws {
        let handle = RunHandle()

        // First one-shot: sleep 30, then we escalate it.
        async let first = BorisRunner.run(
            binary: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"],
            handle: handle
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(handle.isRunning, "first one-shot should be running")
        let firstPID = handle.processIdentifier
        XCTAssertNotNil(firstPID)

        // Escalate: SIGTERM → grace → SIGKILL
        await handle.escalate(grace: .milliseconds(80))
        let firstResult = try await first
        XCTAssertNotEqual(firstResult.exitCode, 0, "first one-shot should have been killed")
        XCTAssertFalse(handle.isRunning, "handle should be free after escalation")

        // Second one-shot: runs cleanly through the same handle.
        let secondResult = try await BorisRunner.run(
            binary: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: [],
            handle: handle
        )
        XCTAssertEqual(secondResult.exitCode, 0, "second one-shot should succeed")
    }

    /// `forceKill` delivers SIGKILL even when the process ignores SIGTERM.
    func testForceKilloverridesSIGTERMTrap() async throws {
        let handle = RunHandle()
        async let output = BorisRunner.run(
            binary: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "trap '' TERM; exec sleep 30"],
            handle: handle
        )
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(handle.isRunning)

        handle.terminate()
        // Process ignores SIGTERM — still running.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(handle.isRunning, "process with SIGTERM trap should survive SIGTERM")

        // Escalate with short grace — delivers SIGKILL.
        await handle.escalate(grace: .milliseconds(50))
        let result = try await output
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(handle.isRunning)
    }

    // MARK: - Watch daemon lifecycle

    /// ValidateWatch owns its own Process, independent of RunHandle.
    /// SIGTERM delivers the signal; the exit code reflects the signal
    /// number (15). Boris is special — it traps SIGTERM and exits 0
    /// (A12 / C06) — but the process lifecycle is the same: SIGTERM →
    /// wait → reapGrace → SIGKILL.
    func testValidateWatchSIGTERMGraceful() throws {
        // ValidateWatch requires a real boris binary to start properly,
        // so we test the Process lifecycle directly with /bin/sleep.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        XCTAssertTrue(process.isRunning)
        process.terminate()
        process.waitUntilExit()
        // sleep doesn't trap SIGTERM — exit code is the signal number (15).
        // Boris itself exits 0 (A12/C06) but the Process lifecycle is identical.
        XCTAssertEqual(process.terminationStatus, 15)
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
    }

    /// WatchServer supports suspend/resume for tree-writing builds.
    func testSuspendResumeLifecycle() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let pid = process.processIdentifier
        defer {
            if process.isRunning {
                ChildProcessControl.forceKill(pid: pid)
                process.waitUntilExit()
            }
        }

        XCTAssertTrue(process.isRunning)

        // Suspend
        XCTAssertTrue(ChildProcessControl.suspend(pid: pid))
        let stat = processStat(pid)
        XCTAssertTrue(stat.contains("T"), "suspended child should be in T state")

        // Resume
        XCTAssertTrue(ChildProcessControl.resume(pid: pid))
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(processStat(pid).contains("T"), "resumed child should leave T state")

        // Still alive — forceKill
        XCTAssertTrue(ChildProcessControl.forceKill(pid: pid))
        process.waitUntilExit()
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
    }

    // MARK: - Reap grace escalation

    /// After SIGTERM + reapGrace, forceKill is called. We verify the timing
    /// by confirming that escalate() with a short grace completes quickly
    /// even when the child is SIGTERM-immune.
    func testReapGraceTiming() async throws {
        let handle = RunHandle()
        let start = ContinuousClock.now
        async let output = BorisRunner.run(
            binary: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "trap '' TERM; exec sleep 30"],
            handle: handle
        )
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(handle.isRunning)

        // escalate with 80ms grace — should complete in < 1s total.
        await handle.escalate(grace: .milliseconds(80))
        let elapsed = start.duration(to: .now)
        let result = try await output

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(handle.isRunning)
        XCTAssertLessThan(elapsed, .seconds(2), "escalate with short grace should not hang")
    }

    // MARK: - Concurrent watch daemons do not block one-shots

    /// Two sleep processes run concurrently (simulating preview watch +
    /// validate watch) while a third (simulating a one-shot) also runs.
    /// None of them block each other.
    func testConcurrentProcesses() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("subprocess-concurrent-\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        func launchSleep() throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["10"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return process
        }

        let watch1 = try launchSleep() // preview watch
        let watch2 = try launchSleep() // validate watch
        let oneshot = try launchSleep() // one-shot build

        // All three running concurrently.
        XCTAssertTrue(watch1.isRunning)
        XCTAssertTrue(watch2.isRunning)
        XCTAssertTrue(oneshot.isRunning)

        // Stop one-shot — watches keep running.
        ChildProcessControl.forceKill(pid: oneshot.processIdentifier)
        oneshot.waitUntilExit()
        XCTAssertFalse(oneshot.isRunning)
        XCTAssertTrue(watch1.isRunning)
        XCTAssertTrue(watch2.isRunning)

        // Stop both watches — no zombies.
        watch1.terminate()
        watch2.terminate()
        watch1.waitUntilExit()
        watch2.waitUntilExit()
        XCTAssertFalse(watch1.isRunning)
        XCTAssertFalse(watch2.isRunning)
    }

    // MARK: - Helpers

    private func processStat(_ pid: Int32) -> String {
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/bin/ps")
        listing.arguments = ["-o", "stat=", "-p", "\(pid)"]
        let pipe = Pipe()
        listing.standardOutput = pipe
        listing.standardError = FileHandle.nullDevice
        do {
            try listing.run()
            listing.waitUntilExit()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(bytes: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
