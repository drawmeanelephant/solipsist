import Foundation

/// How a long-running `watch --serve` process ended.
public struct WatchExit: Sendable {
    public let exitCode: Int32
    /// True when the process ended on a signal (SIGTERM from `stop()`, SIGKILL…).
    /// A clean SIGTERM shutdown is exit code 0 with `signalled == true`
    /// (afterparty C06 / A12 pins this).
    public let signalled: Bool
    /// Last 4 KB of stderr, for surfacing build failures on unexpected exit.
    public let stderrTail: String
}

/// The M4 preview server (D5): a long-lived `boris watch --serve` subprocess.
///
/// Runs `boris watch --serve --port 0 --input <contentRoot>` with
/// `cwd = workingDirectory` (D1: the app runs boris with cwd = project
/// folder, so workspace-relative layouts/themes resolve and output trees
/// stay contained; `--input` may be absolute). stderr is streamed through
/// a pipe; the only line the app parses is the startup line:
///
///     preview: http://127.0.0.1:PORT/  (auto-reload helper: http://127.0.0.1:PORT/__boris/)
///
/// `onServe` fires exactly once, with the `http://127.0.0.1:PORT/__boris/`
/// helper URL (the helper page owns the iframe + SSE `EventSource` and
/// auto-reloads — the web view needs no SSE handling of its own).
/// `onExit` fires exactly once, when the process ends.
///
/// Both callbacks run on an arbitrary background thread — hop to the main
/// actor before touching UI. A server is one-shot: after `stop()` or a
/// spontaneous exit it cannot be restarted; the caller creates a new one.
public final class WatchServer: @unchecked Sendable {
    /// Fired once with the helper URL after the startup port line is parsed.
    public var onServe: ((URL) -> Void)?

    /// Fired exactly once when the process ends (after `stop()` or on its own).
    public var onExit: ((WatchExit) -> Void)?

    private let lock = NSLock()
    private var process: Process?
    private let stderrPipe = Pipe()
    private var stderrAccumulator = Data()
    private var stderrTailText = ""
    private var _serveURL: URL?
    private var didServe = false

    public init(binary: URL, contentRoot: URL, workingDirectory: URL, port: Int = 0) {
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "watch", "--serve",
            "--port", String(port),
            "--input", contentRoot.path,
        ]
        // D1: cwd = project folder (layout/theme resolution + output
        // containment); `--input` stays an explicit absolute root.
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        self.process = process
    }

    deinit {
        stop()
    }

    /// The parsed helper URL, if the server has reported its port.
    public var serveURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _serveURL
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    /// Launches the process. Throws `BorisRunnerError.launchFailed` when the
    /// binary cannot be spawned.
    public func start() throws {
        lock.lock()
        guard let process else {
            lock.unlock()
            throw BorisRunnerError.launchFailed("watch server already stopped")
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        process.terminationHandler = { [weak self] process in
            self?.finish(process)
        }
        lock.unlock()

        do {
            try process.run()
        } catch {
            lock.lock()
            self.process = nil
            lock.unlock()
            throw BorisRunnerError.launchFailed(String(describing: error))
        }
    }

    /// SIGTERM the server (afterparty exits 0 gracefully — A12). Cannot be
    /// restarted; create a new `WatchServer` instead.
    public func stop() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    // MARK: stderr streaming

    private func consume(_ data: Data) {
        lock.lock()
        stderrAccumulator.append(data)
        // Bound the buffer: only the tail is kept for diagnostics, and the
        // moderately sized stream keeps the port scan cheap.
        if stderrAccumulator.count > 65_536 {
            stderrAccumulator.removeFirst(stderrAccumulator.count - 32_768)
        }
        stderrTailText = String(decoding: stderrAccumulator.suffix(4_096), as: UTF8.self)

        var url: URL?
        var serveCallback: ((URL) -> Void)?
        if !didServe {
            url = scanServeURL(in: stderrAccumulator)
            if let url {
                didServe = true
                _serveURL = url
                serveCallback = onServe
            }
        }
        lock.unlock()

        if let url, let serveCallback {
            serveCallback(url)
        }
    }

    private func finish(_ process: Process) {
        lock.lock()
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let exit = WatchExit(
            exitCode: process.terminationStatus,
            signalled: process.terminationReason == .uncaughtSignal,
            stderrTail: stderrTailText
        )
        let onExit = self.onExit
        self.process = nil
        lock.unlock()
        onExit?(exit)
    }

    /// Scans the accumulated stderr bytes for `http://127.0.0.1:<port>` and
    /// returns the helper URL `http://127.0.0.1:<port>/__boris/`.
    private func scanServeURL(in data: Data) -> URL? {
        let hostPrefix = Data("http://127.0.0.1:".utf8)
        guard var index = data.range(of: hostPrefix)?.lowerBound else { return nil }
        index += hostPrefix.count
        var portBytes: [UInt8] = []
        while index < data.count, portBytes.count < 6, data[index] >= 0x30, data[index] <= 0x39 {
            portBytes.append(data[index])
            index += 1
        }
        guard !portBytes.isEmpty,
              let port = Int(String(decoding: portBytes, as: UTF8.self))
        else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/__boris/")
    }
}