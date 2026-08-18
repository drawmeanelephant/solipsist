import XCTest

final class ChildProcessControlTests: XCTestCase {
    func testSuspendResumeAndForceKill() throws {
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
        XCTAssertTrue(ChildProcessControl.suspend(pid: pid))
        XCTAssertTrue(processStat(pid).contains("T"), "suspended child should be in T state")

        XCTAssertTrue(ChildProcessControl.resume(pid: pid))
        // Give the kernel a tick to leave T.
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(processStat(pid).contains("T"), "resumed child should leave T state")
        XCTAssertTrue(process.isRunning)

        XCTAssertTrue(ChildProcessControl.forceKill(pid: pid))
        process.waitUntilExit()
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(process.terminationReason, .uncaughtSignal)
    }

    func testRefusesPidZeroAndOne() {
        XCTAssertFalse(ChildProcessControl.suspend(pid: 0))
        XCTAssertFalse(ChildProcessControl.resume(pid: 1))
        XCTAssertFalse(ChildProcessControl.forceKill(pid: 0))
    }

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
