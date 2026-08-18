import Darwin
import Foundation

/// SIGSTOP / SIGCONT / SIGKILL against a child pid. Shared by the one-shot
/// `RunHandle` and the long-lived `WatchServer` so teardown stays one path.
public enum ChildProcessControl {
    /// Freeze the process. Port stays bound; no further writes.
    @discardableResult
    public static func suspend(pid: Int32) -> Bool {
        guard pid > 1 else { return false }
        return kill(pid, SIGSTOP) == 0
    }

    /// Unfreeze a previously stopped process.
    @discardableResult
    public static func resume(pid: Int32) -> Bool {
        guard pid > 1 else { return false }
        return kill(pid, SIGCONT) == 0
    }

    /// Last-resort reap. Works on a SIGSTOP'd child.
    @discardableResult
    public static func forceKill(pid: Int32) -> Bool {
        guard pid > 1 else { return false }
        return kill(pid, SIGKILL) == 0
    }

    /// Seconds to wait after SIGTERM before SIGKILL.
    public static let reapGrace: Duration = .seconds(2)
}
