import Foundation

/// One-shot `/usr/bin/git` helper for the Add Git Repository… verb (M12 / #131).
/// A clone is a folder: run `git clone`, then hand the folder to
/// `WorkspaceStore.addLocal`. This is not `BorisEngine` — it is a
/// settings-adjacent one-shot process with its own cancel path.
public enum GitClone {
    /// `/usr/bin/git` on Apple platforms is an `xcrun` wrapper that refuses
    /// to run inside the App Sandbox ("xcrun: error: cannot be used within
    /// an App Sandbox"). Resolve the real binary — Command Line Tools or
    /// Xcode — and fall back to `/usr/bin/git` where that is the only git
    /// (unsandboxed hosts: spike, tests, non-Apple builds).
    public static func gitExecutableURL() -> URL {
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

    public struct CloneResult: Sendable {
        public let exitCode: Int32
        public let stderr: String

        public var isSuccess: Bool { exitCode == 0 }
    }

    /// Validate a clone URL shape. Allows `https://`, `ssh://`, `git://`,
    /// and `git@host:path` scp-like forms. Rejects empty, `file://`, and
    /// anything that is not a git transport shape.
    public static func isValidCloneURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return false }
        if trimmed.hasPrefix("file://") { return false }

        // scp-like: git@host:user/repo.git (no scheme)
        if trimmed.contains("@"), trimmed.contains(":"), !trimmed.contains("://") {
            let atParts = trimmed.split(separator: "@")
            guard atParts.count == 2,
                  !atParts[0].isEmpty,
                  !atParts[1].isEmpty,
                  atParts[1].contains(":")
            else { return false }
            return true
        }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased()
        else { return false }
        return ["https", "ssh", "git"].contains(scheme) && !(url.host?.isEmpty ?? true)
    }

    /// The folder `git clone` would create for this URL: last path
    /// component, `.git` suffix and trailing slashes stripped.
    public static func repoName(from urlString: String) -> String {
        var name = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        // git@host:user/repo.git → user/repo.git
        if let schemeRange = name.range(of: "://") {
            name = String(name[schemeRange.upperBound...])
        }
        if let at = name.lastIndex(of: "@") {
            name = String(name[name.index(after: at)...])
        }
        if let colon = name.firstIndex(of: ":") {
            name = String(name[name.index(after: colon)...])
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }
        return name.isEmpty ? "repo" : name
    }

    /// Run `/usr/bin/git clone -- <url> <dest>`. SIGTERM on the child is
    /// available through the returned session. Blocks until the clone
    /// finishes; call off the main actor. `environment` merges over the
    /// inherited environment — the default disables git's interactive
    /// terminal prompts so a private repo without credentials fails
    /// fast with git's error instead of hanging on a hidden prompt.
    public static func clone(
        url: String,
        to dest: URL,
        session: CloneSession,
        environment: [String: String] = [:]
    ) throws -> CloneResult {
        let process = Process()
        process.executableURL = gitExecutableURL()
        process.arguments = ["clone", "--", url, dest.path]
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env.merge(environment) { _, new in new }
        process.environment = env
        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        session.attach(process)
        do {
            try process.run()
        } catch {
            session.detach()
            throw error
        }
        process.waitUntilExit()
        session.detach()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return CloneResult(
            exitCode: process.terminationStatus,
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Branch of the checkout at `root`, or nil when it is not a repo or
    /// git is unavailable. Missing git / not-a-repo is not an error.
    public static func currentBranch(at root: URL) -> String? {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else {
            return nil
        }
        let process = Process()
        process.executableURL = gitExecutableURL()
        process.arguments = ["-C", root.path, "status", "--porcelain=v2", "--branch"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n") {
            if let branch = parseBranch(from: String(line)) {
                return branch
            }
        }
        return nil
    }

    /// Parse the branch out of one porcelain line:
    /// - v2: `# branch.head main`
    /// - v1: `## main...origin/main [ahead 1, behind 2]`
    /// Detached / unborn heads return nil.
    public static func parseBranch(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("# branch.head ") {
            let name = trimmed.dropFirst("# branch.head ".count)
            guard !name.isEmpty, name != "(detached)" else { return nil }
            return String(name)
        }
        if trimmed.hasPrefix("## ") {
            let rest = trimmed.dropFirst(3)
            guard !rest.isEmpty else { return nil }
            let first = rest.split(separator: " ").first ?? ""
            let branch = first.split(separator: "...").first ?? ""
            guard !branch.isEmpty, branch != "(HEAD)", branch != "HEAD" else { return nil }
            return String(branch)
        }
        return nil
    }
}

/// Owns the running `git clone` child so the store can SIGTERM it on
/// cancel. Thread-safe; not tied to the engine's one-slot process.
public final class CloneSession: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    public init() {}

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func detach() {
        lock.lock()
        process = nil
        lock.unlock()
    }

    public func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
    }
}
