import Foundation

/// Commit + push verbs (M16 / #185): `git add -- <picked>` then
/// `git commit`, and `git push -u`, one-shot processes (never the
/// engine slot) on the working copy. The picker decides exactly which
/// paths are staged — never `git add -A`. Identity is never invented:
/// git's own missing-identity error surfaces verbatim. Push rides the
/// credential helper — the token never appears in argv, env, or on
/// disk.
public enum GithubCommit {
    public struct CommitResult: Sendable {
        public let exitCode: Int32
        public let stderr: String

        public var isSuccess: Bool { exitCode == 0 }
    }

    /// Stage exactly the picked paths, then commit with the message.
    /// Runs two sequential git processes sharing one `SyncSession`
    /// (SIGTERM cancels the in-flight one). The commit is skipped when
    /// staging fails — its result is returned so the failure surfaces
    /// with git's own stderr. Identity failures come back in `stderr`
    /// verbatim (git's "Please tell me who you are").
    public static func commit(
        paths: [String],
        message: String,
        workingCopy: URL,
        session: SyncSession,
        environment: [String: String] = [:]
    ) -> CommitResult {
        let stage = run(["add", "--"] + paths, workingCopy: workingCopy, session: session, environment: environment)
        guard stage.isSuccess else { return stage }
        return run(["commit", "-m", message], workingCopy: workingCopy, session: session, environment: environment)
    }

    /// Push the current branch with upstream tracking: `git push -u
    /// origin <branch>`. The credential helper authenticates https
    /// remotes. Never a force-push — a non-fast-forward rejection is
    /// git's own error, surfaced verbatim.
    public static func push(
        branch: String,
        workingCopy: URL,
        credentialHelperApp: URL?,
        session: SyncSession,
        environment: [String: String] = [:]
    ) -> CommitResult {
        let process = Process()
        process.executableURL = GitClone.gitExecutableURL()
        var arguments = ["-C", workingCopy.path]
        if let credentialHelperApp {
            arguments.append(contentsOf: GitClone.credentialHelperArguments(appURL: credentialHelperApp))
        }
        arguments.append(contentsOf: ["push", "-u", "origin", branch])
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
            return CommitResult(exitCode: 1, stderr: String(describing: error))
        }
        process.waitUntilExit()
        session.detach()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return CommitResult(
            exitCode: process.terminationStatus,
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    private static func run(
        _ arguments: [String],
        workingCopy: URL,
        session: SyncSession,
        environment: [String: String]
    ) -> CommitResult {
        let process = Process()
        process.executableURL = GitClone.gitExecutableURL()
        process.arguments = ["-C", workingCopy.path] + arguments
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
            return CommitResult(exitCode: 1, stderr: String(describing: error))
        }
        process.waitUntilExit()
        session.detach()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return CommitResult(
            exitCode: process.terminationStatus,
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
