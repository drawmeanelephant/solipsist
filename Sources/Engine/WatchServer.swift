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
/// Runs `boris watch --serve --watch-json --port 0 --input <contentRoot>`
/// with `cwd = workingDirectory` (D1: the app runs boris with cwd = project
/// folder, so workspace-relative layouts/themes resolve and output trees
/// stay contained; `--input` may be absolute). With `--watch-json` (A1,
/// boris#648) stderr is exclusively NDJSON — no prose port line. The
/// pinned kit emits `hello` (schema 1) first, then `serve-started` with
/// `url` / `helper` / `port`.
///
/// `onServe` fires exactly once, from the `serve-started` event, with the
/// `http://127.0.0.1:PORT/__boris/` helper URL (the helper page owns the
/// iframe + SSE `EventSource` and auto-reloads — the web view needs no SSE
/// handling of its own). `onProblem` fires for `build-failed` /
/// `watch-error` / unexpected `watch-stopped` — never swallowed.
/// `onExit` fires exactly once, when the process ends.
///
/// Callbacks run on an arbitrary background thread — hop to the main
/// actor before touching UI. A server is one-shot: after `stop()` or a
/// spontaneous exit it cannot be restarted; the caller creates a new one.
public final class WatchServer: @unchecked Sendable {
    /// Fired once with the helper URL after the `serve-started` event.
    public var onServe: ((URL) -> Void)?

    /// Fired for `build-failed` / `watch-error` / unexpected `watch-stopped`
    /// events — problems the watch stream reports without ending the process.
    public var onProblem: ((String) -> Void)?

    /// Fired exactly once when the process ends (after `stop()` or on its own).
    public var onExit: ((WatchExit) -> Void)?

    private let lock = NSLock()
    private var process: Process?
    private let stderrPipe = Pipe()
    private var stderrAccumulator = Data()
    private var lineBuffer = Data()
    private var parser = WatchStreamParser()
    private var stderrTailText = ""
    private var _serveURL: URL?
    private var didFireServe = false
    private var deliveredProblemCount = 0

    public init(binary: URL, contentRoot: URL, workingDirectory: URL, port: Int = 0) {
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "watch", "--serve", "--watch-json",
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

    public var isSuspended: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _suspended
    }

    public var processIdentifier: Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    private var _suspended = false

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
    /// restarted; create a new `WatchServer` instead. A SIGSTOP'd child is
    /// continued first so the signal is delivered.
    public func stop() {
        lock.lock()
        let process = self.process
        let suspended = _suspended
        let pid = process?.processIdentifier
        _suspended = false
        lock.unlock()
        guard let process, process.isRunning else { return }
        if suspended, let pid {
            ChildProcessControl.resume(pid: pid)
        }
        process.terminate()
    }

    /// Freeze watch so a tree-writing job can own `dist/` / `.boris`.
    /// The helper URL and bound port stay valid.
    public func suspend() {
        lock.lock()
        let pid = process?.isRunning == true ? process?.processIdentifier : nil
        let already = _suspended
        lock.unlock()
        guard let pid, !already else { return }
        guard ChildProcessControl.suspend(pid: pid) else { return }
        lock.lock()
        _suspended = true
        lock.unlock()
    }

    /// Continue a frozen watch. No-op if it already exited.
    public func resume() {
        lock.lock()
        let pid = process?.isRunning == true ? process?.processIdentifier : nil
        let was = _suspended
        _suspended = false
        lock.unlock()
        guard was, let pid else { return }
        ChildProcessControl.resume(pid: pid)
    }

    /// SIGKILL if SIGTERM was ignored. Safe on a stopped child.
    public func forceKill() {
        lock.lock()
        let pid = process?.isRunning == true ? process?.processIdentifier : nil
        _suspended = false
        lock.unlock()
        guard let pid else { return }
        ChildProcessControl.forceKill(pid: pid)
    }

    // MARK: stderr streaming

    private func consume(_ data: Data) {
        lock.lock()
        stderrAccumulator.append(data)
        // Bound the buffer: only the tail is kept for diagnostics.
        if stderrAccumulator.count > 65_536 {
            stderrAccumulator.removeFirst(stderrAccumulator.count - 32_768)
        }
        stderrTailText = String(decoding: stderrAccumulator.suffix(4_096), as: UTF8.self)

        // Feed complete NDJSON lines to the parser; keep the trailing
        // fragment for the next chunk.
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer[..<newline]
            lineBuffer.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8) {
                parser.consume(line: line)
            }
        }

        var serveURL: URL?
        var serveCallback: ((URL) -> Void)?
        if parser.didServe, !didFireServe {
            didFireServe = true
            _serveURL = parser.serveURL
            serveURL = parser.serveURL
            serveCallback = onServe
        }
        var problems: [String] = []
        if parser.problems.count > deliveredProblemCount {
            problems = Array(parser.problems[deliveredProblemCount...])
            deliveredProblemCount = parser.problems.count
        }
        let problemCallback = onProblem
        lock.unlock()

        if let serveURL, let serveCallback {
            serveCallback(serveURL)
        }
        for problem in problems {
            problemCallback?(problem)
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
        _suspended = false
        lock.unlock()
        onExit?(exit)
    }
}

