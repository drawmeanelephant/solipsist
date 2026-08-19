import Foundation

/// The A5 live-problems daemon (#161 / boris#647): a long-lived
/// `boris validate --watch --watch-json` subprocess, sibling of the M4
/// preview `WatchServer` (never a third watch — one HTML watch for
/// preview, one validate watch for problems).
///
/// Runs `boris validate --watch --watch-json --input <contentRoot>` with
/// `cwd = workingDirectory` (D1: workspace-relative layouts/themes
/// resolve), stderr → NDJSON. No `--serve` (no helper URL), no output
/// flags, no `--report` (stream-only — the app already has the A1
/// parser). Validate writes nothing, so the daemon never needs the
/// tree-write suspend/resume the preview watch does.
///
/// The stream is the A1 protocol with `mode: "validate"` (probed at
/// `bf464a0`): `hello` (schema 1) → `build-started` →
/// `build-succeeded` / `build-failed` (with the `html-build-report`
/// `diagnostics` shape) → `watcher-started`; rebuild cycles carry
/// `changed`; SIGTERM → graceful `watch-stopped reason:"signal"`, exit 0
/// (A12).
///
/// `onBuild` fires per build cycle with the structured outcome
/// (handshake-gated by the parser, D8); `onProblem` fires for
/// `watch-error` / unexpected `watch-stopped`; `onExit` fires exactly
/// once when the process ends. Callbacks run on an arbitrary background
/// thread — hop to the main actor before touching UI. One-shot: after
/// `stop()` or a spontaneous exit it cannot be restarted.
public final class ValidateWatch: @unchecked Sendable {
    /// Fired per build cycle: `.failed(diagnostics)` replaces the pane's
    /// problems, `.succeeded` clears them.
    public var onBuild: ((WatchBuildOutcome) -> Void)?

    /// Fired for `watch-error` / unexpected `watch-stopped` events —
    /// problems the stream reports without ending the process.
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
    private var lastDeliveredOutcome: WatchBuildOutcome?
    private var deliveredProblemCount = 0

    public init(binary: URL, contentRoot: URL, workingDirectory: URL) {
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "validate", "--watch", "--watch-json",
            "--input", contentRoot.path,
        ]
        // D1: cwd = project folder; `--input` stays an explicit absolute root.
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        self.process = process
    }

    deinit {
        stop()
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    public var processIdentifier: Int32? {
        lock.lock()
        defer { lock.unlock() }
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    /// Launches the process. Throws `BorisRunnerError.launchFailed` when the
    /// binary cannot be spawned.
    public func start() throws {
        lock.lock()
        guard let process else {
            lock.unlock()
            throw BorisRunnerError.launchFailed("validate watch already stopped")
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

    /// SIGTERM the daemon (afterparty exits 0 gracefully — A12). Cannot be
    /// restarted; create a new `ValidateWatch` instead.
    public func stop() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    /// SIGKILL if SIGTERM was ignored.
    public func forceKill() {
        lock.lock()
        let pid = process?.isRunning == true ? process?.processIdentifier : nil
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

        // Fire each *new* build outcome exactly once (first and subsequent).
        var builds: [WatchBuildOutcome] = []
        if let outcome = parser.buildOutcome, outcome != lastDeliveredOutcome {
            builds.append(outcome)
            lastDeliveredOutcome = outcome
        }
        var problems: [String] = []
        if parser.problems.count > deliveredProblemCount {
            // Build-failed summaries ride the structured `.failed(diagnostics)`
            // channel; a string summary would overwrite the pane's
            // diagnostics. Everything else (watch-error, watch-stopped,
            // handshake) is delivered as a problem.
            problems = Array(parser.problems[deliveredProblemCount...])
                .filter { !$0.hasPrefix(WatchStreamParser.buildFailedSummaryPrefix) }
            deliveredProblemCount = parser.problems.count
        }
        let buildCallback = onBuild
        let problemCallback = onProblem
        lock.unlock()

        for build in builds {
            buildCallback?(build)
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
        lock.unlock()
        onExit?(exit)
    }
}
