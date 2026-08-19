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
    /// `credentialHelperApp` (when set) configures git to ask this app
    /// binary for GitHub credentials via `credential.helper=` — the
    /// helper mode reads the Keychain and prints the token on stdout;
    /// the token never appears in argv, env, or on disk.
    public static func clone(
        url: String,
        to dest: URL,
        session: CloneSession,
        environment: [String: String] = [:],
        credentialHelperApp: URL? = nil
    ) throws -> CloneResult {
        let process = Process()
        process.executableURL = gitExecutableURL()
        var arguments = ["clone", "--", url, dest.path]
        if let credentialHelperApp {
            arguments.insert(contentsOf: credentialHelperArguments(appURL: credentialHelperApp), at: 0)
        }
        process.arguments = arguments
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

    /// `-c credential.helper=…` argument pair pointing git at this app
    /// binary in helper mode. The `!` shell form quotes the path so
    /// app locations with spaces work; git appends the operation
    /// (`get`) as the last argument.
    public static func credentialHelperArguments(appURL: URL) -> [String] {
        let quoted = shellQuote(appURL.path)
        return ["-c", "credential.helper=!\(quoted) \(GitCredentialHelper.flag)"]
    }

    private static func shellQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        return "\"\(escaped)\""
    }

    /// Branch of the checkout at `root`, or nil when it is not a repo or
    /// git is unavailable. Missing git / not-a-repo is not an error.
    public static func currentBranch(at root: URL) -> String? {
        branchStatus(at: root).branch
    }

    /// Branch + ahead/behind of the checkout at `root` (Remote mailbox,
    /// M15). `ahead`/`behind` count commits against the upstream
    /// (`origin/<branch>`). Missing git / not-a-repo yields an empty
    /// status with a nil branch — never an error.
    public static func branchStatus(at root: URL) -> GitBranchStatus {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else {
            return GitBranchStatus(branch: nil, upstream: nil, ahead: 0, behind: 0)
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
            return GitBranchStatus(branch: nil, upstream: nil, ahead: 0, behind: 0)
        }
        guard process.terminationStatus == 0 else {
            return GitBranchStatus(branch: nil, upstream: nil, ahead: 0, behind: 0)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        for line in text.split(separator: "\n") {
            let line = String(line)
            if let parsed = parseBranch(from: line) {
                branch = parsed
            }
            if let up = parseUpstream(from: line) {
                upstream = up
            }
            if let ab = parseAheadBehind(from: line) {
                ahead = ab.ahead
                behind = ab.behind
            }
        }
        return GitBranchStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind)
    }

    /// Parse the upstream out of one porcelain v2 line: `# branch.upstream
    /// origin/main` → `origin/main`. Anything else returns nil.
    public static func parseUpstream(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("# branch.upstream ") else { return nil }
        let name = trimmed.dropFirst("# branch.upstream ".count)
        return name.isEmpty ? nil : String(name)
    }

    /// Branch + ahead/behind parsed from `status --porcelain=v2 --branch`.
    /// `upstream` is `origin/<branch>` when tracking is set (from
    /// `# branch.upstream`), nil otherwise — the PR sheet (M16-3) uses
    /// its absence to know a `-u` push is required first.
    public struct GitBranchStatus: Sendable, Equatable {
        public let branch: String?
        public let upstream: String?
        public let ahead: Int
        public let behind: Int
    }

    /// One changed file from `status --porcelain=v1 -z` (M16-1).
    /// `path` is the working-copy-relative path `git add -- <path>`
    /// accepts — for renames that is the **destination** (git -z emits
    /// `XY <to>\0<from>`; staging the destination stages the rename).
    public struct GitStatusEntry: Sendable, Equatable {
        public let path: String
        /// The porcelain XY pair, e.g. `" M"`, `"??"`, `"R "`.
        public let status: String
        /// Rename/copy source path (display only); nil otherwise.
        public let sourcePath: String?

        /// Human label for the picker row.
        public var statusLabel: String {
            switch status {
            case "??": return "untracked"
            case "M ", " M": return "modified"
            case "A ", " A": return "added"
            case "D ", " D": return "deleted"
            case "R ", " R": return "renamed"
            case "C ", " C": return "copied"
            case "MM", "AM", "MD", "AD", "RM", "RD": return status
            default:
                let trimmed = status.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? status : trimmed
            }
        }
    }

    /// Changed files of the checkout at `root` (Commit picker, M16-1):
    /// `git status --porcelain=v1 -z`, same runner shape as
    /// `branchStatus`. Missing git / not-a-repo → empty, never an error.
    public static func statusEntries(at root: URL) -> [GitStatusEntry] {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else {
            return []
        }
        let process = Process()
        process.executableURL = gitExecutableURL()
        process.arguments = ["-C", root.path, "status", "--porcelain=v1", "-z"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        return parseStatusEntries(pipe.fileHandleForReading.readDataToEndOfFile())
    }

    /// Parse `--porcelain=v1 -z` bytes. Each NUL record is `XY <path>`;
    /// rename/copy entries emit a second bare record with the source
    /// path (`XY <to>\0<from>`), consumed here. Pure — tests feed bytes.
    public static func parseStatusEntries(_ data: Data) -> [GitStatusEntry] {
        let records = data.split(separator: 0)
        var entries: [GitStatusEntry] = []
        var index = 0
        while index < records.count {
            let record = records[index]
            guard let text = String(data: record, encoding: .utf8), text.count >= 3 else {
                index += 1
                continue
            }
            // Records are `XY <path>`; the second character must be the
            // status, the third a space. A bare record (no `XY ` prefix)
            // is a rename/copy source — it belongs to the prior entry,
            // which is handled below, so skip it here.
            guard text[text.index(text.startIndex, offsetBy: 2)] == " " else {
                index += 1
                continue
            }
            let status = String(text.prefix(2))
            let path = String(text.dropFirst(3))
            var entry = GitStatusEntry(path: path, status: status, sourcePath: nil)
            if status.contains("R") || status.contains("C") {
                if index + 1 < records.count,
                   let source = String(data: records[index + 1], encoding: .utf8),
                   !source.isEmpty
                {
                    entry = GitStatusEntry(path: path, status: status, sourcePath: source)
                }
                index += 2
            } else {
                index += 1
            }
            entries.append(entry)
        }
        return entries
    }

    /// Parse the ahead/behind counts out of one porcelain v2 line:
    /// `# branch.ab +1 -2` → (1, 2). Anything else returns nil.
    public static func parseAheadBehind(from line: String) -> (ahead: Int, behind: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("# branch.ab ") else { return nil }
        let rest = trimmed.dropFirst("# branch.ab ".count)
        let parts = rest.split(separator: " ")
        guard parts.count == 2 else { return nil }
        let aheadPart = parts[0].hasPrefix("+") ? parts[0].dropFirst() : parts[0]
        let behindPart = parts[1].hasPrefix("-") ? parts[1].dropFirst() : parts[1]
        guard let ahead = Int(aheadPart), let behind = Int(behindPart) else { return nil }
        return (ahead, behind)
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
