import Foundation

/// Centralized resolution of the `git` binary for all one-shot git
/// verbs (M12 / #131, M15/M16). `/usr/bin/git` on Apple platforms is
/// an `xcrun` shim that refuses to run inside the App Sandbox
/// ("xcrun: error: cannot be used within an App Sandbox"), so we
/// probe the real Command Line Tools and Xcode locations first, then
/// fall back to `/usr/bin/git` where that is the only `git`
/// (unsandboxed hosts: tests, spike, non-Apple builds).
///
/// `GitClone.gitExecutableURL()` forwards here; new code should call
/// `GitCLT.resolve()` directly. `GithubSync` and `GithubCommit` share
/// this single probe so credential-helper wiring and sandboxed-clone
/// fixes stay in one place.
public enum GitCLT {
    public static func resolve() -> URL {
        let candidates = [
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/usr/bin/git",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/git")
    }

    /// Whether the resolved `git` is actually executable on this host.
    /// Use for disabled-hint copy ("git not found").
    public static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: resolve().path)
    }
}
