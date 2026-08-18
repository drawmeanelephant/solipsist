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
        lock.lock()
        let process = self.process
        lock.unlock()
        return process?.isRunning == true
    }

    public var processIdentifier: Int32? {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    public func terminate() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    public func forceKill() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        ChildProcessControl.forceKill(pid: process.processIdentifier)
    }

    /// SIGTERM, wait `grace`, then SIGKILL if the child is still up.
    public func escalate(grace: Duration = ChildProcessControl.reapGrace) async {
        terminate()
        try? await Task.sleep(for: grace)
        if isRunning {
            forceKill()
        }
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

        handle?.attach(process)
        defer {
            stdoutHandle.closeFile()
            stderrHandle.closeFile()
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let box = OnceResume()
            process.terminationHandler = { _ in
                box.resume {
                    cont.resume()
                }
            }
            do {
                try process.run()
            } catch {
                box.resume {
                    cont.resume(throwing: BorisRunnerError.launchFailed(String(describing: error)))
                }
                return
            }
            do {
                try writeStdin(pipe)
                pipe.fileHandleForWriting.closeFile()
            } catch {
                process.terminate()
                box.resume {
                    cont.resume(throwing: error)
                }
            }
        }

        let stdout = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderr = (try? Data(contentsOf: stderrURL)) ?? Data()
        return RunOutput(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}

/// `terminationHandler` and launch-failure can race; resume once.
private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func resume(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}
