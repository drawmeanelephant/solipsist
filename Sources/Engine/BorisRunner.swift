import Darwin
import Foundation

public struct RunOutput: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum BorisRunnerError: Error, Sendable, CustomStringConvertible {
    case binaryNotFound
    case launchFailed(String)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return "boris binary not found (set SOLIPSIST_BORIS_BIN or build via scripts/embed-boris.sh)"
        case .launchFailed(let message):
            return "failed to launch boris: \(message)"
        }
    }
}

/// Lets the engine interrupt an in-flight `Process` (Stop). Additive —
/// capture/wait behavior is unchanged.
public final class RunHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    public init() {}

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    public var isRunning: Bool {
        currentProcess()?.isRunning == true
    }

    public var processIdentifier: Int32? {
        guard let process = currentProcess(), process.isRunning else { return nil }
        return process.processIdentifier
    }

    public func terminate() {
        guard let process = currentProcess(), process.isRunning else { return }
        process.terminate()
    }

    public func forceKill() {
        guard let process = currentProcess(), process.isRunning else { return }
        ChildProcessControl.forceKill(pid: process.processIdentifier)
    }

    /// SIGTERM, wait `grace`, then SIGKILL if the child is still up.
    public func escalate(grace: Duration = ChildProcessControl.reapGrace) async {
        guard let process = currentProcess() else { return }
        await Self.escalate(process, grace: grace)
    }

    /// Both signals belong to this child, even if the shared slot changes.
    static func escalate(_ process: Process, grace: Duration) async {
        guard process.isRunning else { return }
        process.terminate()
        try? await Task.sleep(for: grace)
        if process.isRunning {
            ChildProcessControl.forceKill(pid: process.processIdentifier)
        }
    }

    private func currentProcess() -> Process? {
        lock.lock()
        defer { lock.unlock() }
        return process
    }
}

public enum BorisRunner {

    /// Launch and wait off the caller's executor. Completion uses
    /// `terminationHandler` so an actor can still `interrupt()` / `forceKill()`
    /// a wedged child. Stdin is a wiped secret buffer (Boris publication).
    public static func run(
        binary: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        handle: RunHandle? = nil,
        stdin: SecureBuffer? = nil
    ) async throws -> RunOutput {
        if let stdin {
            return try await launch(
                binary: binary,
                arguments: arguments,
                workingDirectory: workingDirectory,
                handle: handle
            ) { pipe in
                try StdinSecretWriter.writeAndWipe(stdin, to: pipe.fileHandleForWriting)
            }
        }
        // No stdin: close the write end immediately so the child sees EOF
        // (the old behavior piped `nullDevice`; EOF is equivalent).
        return try await launch(
            binary: binary,
            arguments: arguments,
            workingDirectory: workingDirectory,
            handle: handle
        ) { pipe in
            pipe.fileHandleForWriting.closeFile()
        }
    }

    /// Same launch, with plain-text stdin — the compose preview renders
    /// buffers through this path (Oliver CLI), never secrets.
    public static func run(
        binary: URL,
        arguments: [String],
        workingDirectory: URL? = nil,
        handle: RunHandle? = nil,
        stdinText: String
    ) async throws -> RunOutput {
        try await launch(
            binary: binary,
            arguments: arguments,
            workingDirectory: workingDirectory,
            handle: handle
        ) { pipe in
            let data = Data(stdinText.utf8)
            try pipe.fileHandleForWriting.write(contentsOf: data)
        }
    }

    private static func launch(
        binary: URL,
        arguments: [String],
        workingDirectory: URL?,
        handle: RunHandle?,
        writeStdin: (Pipe) throws -> Void
    ) async throws -> RunOutput {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory
            .appendingPathComponent("boris-run-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let stdoutURL = tmpDir.appendingPathComponent("stdout")
        let stderrURL = tmpDir.appendingPathComponent("stderr")
        guard
            fm.createFile(atPath: stdoutURL.path, contents: nil),
            fm.createFile(atPath: stderrURL.path, contents: nil),
            let stdoutHandle = FileHandle(forWritingAtPath: stdoutURL.path),
            let stderrHandle = FileHandle(forWritingAtPath: stderrURL.path)
        else {
            throw BorisRunnerError.launchFailed("could not create capture files")
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let pipe = Pipe()
        process.standardInput = pipe
        defer {
            stdoutHandle.closeFile()
            stderrHandle.closeFile()
        }
        // A child that closes stdin must produce a write error, not SIGPIPE
        // in the app. Limit signal protection to this pipe, not the process.
        guard fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        handle?.attach(process)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let completion = RunCompletion(cont)
            process.terminationHandler = { _ in
                completion.processExited()
            }
            do {
                try process.run()
            } catch {
                completion.launchFailed(BorisRunnerError.launchFailed(String(describing: error)))
                return
            }
            do {
                try writeStdin(pipe)
                pipe.fileHandleForWriting.closeFile()
                completion.stdinFinished()
            } catch {
                pipe.fileHandleForWriting.closeFile()
                completion.stdinFinished(error: error)
                // Do not release the caller's process slot until this child
                // has exited. Escalation is bounded and targets only it.
                Task {
                    await RunHandle.escalate(process, grace: ChildProcessControl.reapGrace)
                }
            }
        }

        let stdout = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderr = (try? Data(contentsOf: stderrURL)) ?? Data()
        return RunOutput(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}

/// Exit can race stdin completion. Preserve write errors and resume once,
/// only after the launched child has been reaped.
private final class RunCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<Void, any Error>
    private var exited = false
    private var inputFinished = false
    private var resumed = false
    private var error: (any Error)?

    init(_ continuation: CheckedContinuation<Void, any Error>) {
        self.continuation = continuation
    }

    func processExited() {
        lock.lock()
        exited = true
        lock.unlock()
        resumeIfComplete()
    }

    func stdinFinished(error: (any Error)? = nil) {
        lock.lock()
        inputFinished = true
        self.error = error
        lock.unlock()
        resumeIfComplete()
    }

    func launchFailed(_ error: any Error) {
        lock.lock()
        exited = true
        inputFinished = true
        self.error = error
        lock.unlock()
        resumeIfComplete()
    }

    private func resumeIfComplete() {
        lock.lock()
        guard exited, inputFinished, !resumed else {
            lock.unlock()
            return
        }
        resumed = true
        let error = self.error
        lock.unlock()
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
