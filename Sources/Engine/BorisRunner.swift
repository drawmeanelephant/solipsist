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

/// Runs the `boris` binary as a subprocess and captures its output.
///
/// stdout/stderr are redirected to temp files rather than pipes: regular
/// files cannot deadlock (OS pipe buffers cap at ~64 KB and Boris JSON
/// reports can exceed that) and need no concurrent reader threads. The
/// child inherits the file descriptors; after exit we read the files back.
public enum BorisRunner {

    public static func run(
        binary: URL,
        arguments: [String],
        workingDirectory: URL? = nil
    ) throws -> RunOutput {
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
        defer {
            stdoutHandle.closeFile()
            stderrHandle.closeFile()
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
        } catch {
            throw BorisRunnerError.launchFailed(String(describing: error))
        }
        process.waitUntilExit()

        let stdout = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderr = (try? Data(contentsOf: stderrURL)) ?? Data()
        return RunOutput(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
