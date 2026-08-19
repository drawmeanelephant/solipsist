import Foundation

/// Remote mailbox sync verb (M15 / #179): `fetch` then `pull --ff-only`
/// against a GitHub working copy, one-shot `/usr/bin/git` processes (not
/// the engine slot) authenticated through the app binary's
/// `--git-credential-helper` mode — the token never appears in argv,
/// env, or on disk.
public enum GithubSync {
    public struct SyncResult: Sendable {
        public let exitCode: Int32
        public let stderr: String

        public var isSuccess: Bool { exitCode == 0 }
    }

    /// Fetch then fast-forward pull. Runs two sequential git processes
    /// sharing one `SyncSession` (SIGTERM cancels the in-flight one).
    /// The pull is skipped when the fetch fails — the fetch result is
    /// returned so the failure surfaces with git's own stderr.
    public static func sync(
        workingCopy: URL,
        credentialHelperApp: URL?,
        session: SyncSession
    ) -> SyncResult {
        let fetch = run(["fetch"], workingCopy: workingCopy, credentialHelperApp: credentialHelperApp, session: session)
        guard fetch.isSuccess else { return fetch }
        return run(["pull", "--ff-only"], workingCopy: workingCopy, credentialHelperApp: credentialHelperApp, session: session)
    }

    private static func run(
        _ verb: [String],
        workingCopy: URL,
        credentialHelperApp: URL?,
        session: SyncSession
    ) -> SyncResult {
        let process = Process()
        process.executableURL = GitClone.gitExecutableURL()
        var arguments = ["-C", workingCopy.path]
        if let credentialHelperApp {
            arguments.append(contentsOf: GitClone.credentialHelperArguments(appURL: credentialHelperApp))
        }
        arguments.append(contentsOf: verb)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env
        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe
        session.attach(process)
        do {
            try process.run()
        } catch {
            session.detach()
            return SyncResult(exitCode: 1, stderr: String(describing: error))
        }
        process.waitUntilExit()
        session.detach()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return SyncResult(
            exitCode: process.terminationStatus,
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}

/// Owns the running git sync child so the store can SIGTERM it on cancel.
/// Same shape as `CloneSession` — thread-safe, not the engine's one slot.
public final class SyncSession: @unchecked Sendable {
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
