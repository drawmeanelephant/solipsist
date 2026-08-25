import Foundation
import Observation

/// What `EditorSession` drives across the subprocess boundary. Production
/// vends `EditorServer` from `BorisEngine.editorStart` (A14); the seam lets
/// reconnect behavior be exercised without spawning binaries.
protocol EditorHost: AnyObject {
    var onConnect: ((URL) -> Void)? { get set }
    var onExit: ((EditorExit) -> Void)? { get set }
    var editorURL: URL? { get }
    var isRunning: Bool { get }
    func stop()
}

extension EditorServer: EditorHost {}

/// Auto-reconnect policy for spontaneous `boris-editor` crashes (#232): up
/// to three restarts inside a 30s sliding window, backing off 2s × attempt.
/// Pure so the cap/window arithmetic is unit-testable without a clock.
enum EditorAutoReconnect {
    static let maxAttempts = 3
    static let window: Duration = .seconds(30)
    static let baseDelay: Duration = .seconds(2)

    enum Decision: Equatable {
        /// Schedule the next automatic restart; payload is the 1-based
        /// attempt number (delay = baseDelay × attempt).
        case retry(attempt: Int)
        /// Cap reached within the window — manual restart required.
        case giveUp
    }

    /// Drops crash instants that aged out of the sliding window.
    static func prune(_ crashes: [ContinuousClock.Instant], now: ContinuousClock.Instant) -> [ContinuousClock.Instant] {
        let cutoff = now - window
        return crashes.filter { $0 >= cutoff }
    }

    /// Decides what to do given the number of crashes recorded in the
    /// window, including the one that just happened.
    static func decision(crashesInWindow count: Int) -> Decision {
        count > maxAttempts ? .giveUp : .retry(attempt: count)
    }

    static let windowDescription = "\(window.components.seconds)s"
}

/// #280: typed reasons an editor host lifecycle fails. `Phase.failed`
/// carries one of these instead of a raw message, so chrome mapping is
/// compiler-checked (`EditorFailureGuidance`) rather than substring
/// matching against wording that can drift.
enum EditorSessionError: Equatable {
    /// No engine binary is available to host the editor from.
    case engineUnavailable
    /// The `boris-editor` binary could not be located — a permanent
    /// configuration error, never a crash-reconnect candidate (#232).
    case binaryNotFound
    /// The host started but never reported a token URL within
    /// `EditorSession.connectTimeout`.
    case timeout
    /// The host crashed more than `EditorAutoReconnect.maxAttempts` times
    /// inside the reconnect window; manual restart required. Carries the
    /// trimmed stderr tail for the status line.
    case crashLoop(stderrTail: String)
    /// The host factory threw something other than a launch-configuration error.
    case launchFailed(String)
    /// The selected source's content/project folders could not be resolved.
    case folderUnresolved(String)

    /// Maps permanent factory configuration errors onto their typed cases;
    /// exhaustive over `EditorHostLaunchError`, so a new case cannot be
    /// added without deciding its session-level meaning.
    init(_ launchError: EditorHostLaunchError) {
        switch launchError {
        case .editorBinaryNotFound:
            self = .binaryNotFound
        }
    }

    /// Human-readable status line, surfaced verbatim by the chrome.
    var message: String {
        switch self {
        case .engineUnavailable:
            return "Boris engine not available."
        case .binaryNotFound:
            return EditorHostLaunchError.editorBinaryNotFound.errorDescription ?? "boris-editor binary not found."
        case .timeout:
            return "Editor host did not report a token URL within \(EditorSession.connectTimeoutDescription)."
        case .crashLoop(let stderrTail):
            let suffix = stderrTail.isEmpty ? "" : " — \(stderrTail.suffix(200))"
            return "Editor host crashed \(EditorAutoReconnect.maxAttempts) times within \(EditorAutoReconnect.windowDescription). Manual restart required.\(suffix)"
        case .launchFailed(let underlying):
            return "Could not start editor host: \(underlying)"
        case .folderUnresolved(let title):
            return "Could not resolve project folder for '\(title)'"
        }
    }
}

/// Drives the M6 author companion surface (A14 / #75): owns the `boris-editor`
/// subprocess host lifetime and hands the tokenized session URL to the editor web view.
///
/// When the host dies spontaneously (non-zero exit or signal — never exit 0,
/// which is the SIGTERM shutdown path), the session restarts it automatically
/// with backoff, capped at `EditorAutoReconnect.maxAttempts` crashes inside
/// `EditorAutoReconnect.window`. A successful connect resets the counter and
/// raises a transient "Editor host restarted" notice (#232). Manual actions
/// (`restart()`, `stop()`, source switches) cancel any pending auto-restart;
/// they clear the callbacks before the old process reports its exit, so
/// `handleExit` only ever sees spontaneous deaths.
@MainActor
@Observable
final class EditorSession {
    enum Phase: Equatable {
        case idle
        case starting
        case connected(URL)
        /// Spontaneous exit; an automatic restart is pending (attempt N).
        case reconnecting(attempt: Int)
        case failed(EditorSessionError)
    }

    /// Builds a host. Always invoked on the main actor (`start()`'s context).
    typealias HostFactory = @MainActor (_ engine: BorisEngine, _ workingDirectory: URL) throws -> any EditorHost

    /// How long the host gets to report its token URL before the start
    /// attempt is failed as `.timeout`.
    nonisolated static let connectTimeout: Duration = .seconds(15)

    /// Human form of `connectTimeout` for status copy ("15s").
    nonisolated static var connectTimeoutDescription: String { "\(connectTimeout.components.seconds)s" }

    private(set) var phase: Phase = .idle

    /// One-shot confirmation after an automatic reconnect succeeds ("Editor
    /// host restarted"). Cleared whenever the session leaves `connected`.
    private(set) var transientNotice: String?

    /// Backoff base for automatic restarts: attempt N waits N × base.
    let reconnectBaseDelay: Duration

    var editorURL: URL? {
        if case .connected(let url) = phase { return url }
        return nil
    }

    var isFailure: Bool {
        if case .failed = phase { return true }
        return false
    }

    /// #237: True when the editor host has connected and the URL is live.
    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    var statusText: String {
        switch phase {
        case .idle:
            return ""
        case .starting:
            return "Starting boris-editor…"
        case .connected(let url):
            return "Connected to \(url.host ?? "loopback")"
        case .reconnecting(let attempt):
            return "boris-editor exited unexpectedly — restarting automatically (attempt \(attempt) of \(EditorAutoReconnect.maxAttempts))…"
        case .failed(let error):
            return error.message
        }
    }

    private let makeHost: HostFactory
    private var server: (any EditorHost)?
    private var rootPath: String?
    private var timeoutTask: Task<Void, Never>?
    private var lastContentRoot: URL?
    private var lastProjectRoot: URL?
    private var lastEngine: BorisEngine?
    private var reconnectCrashes: [ContinuousClock.Instant] = []
    private var reconnectTask: Task<Void, Never>?

    var canRestart: Bool {
        lastContentRoot != nil
    }

    init(
        makeHost: @escaping HostFactory = EditorServerFactory.launch,
        reconnectBaseDelay: Duration = EditorAutoReconnect.baseDelay
    ) {
        self.makeHost = makeHost
        self.reconnectBaseDelay = reconnectBaseDelay
    }

    func start(contentRoot: URL, projectRoot: URL, engine: BorisEngine?) {
        startInternal(
            contentRoot: contentRoot,
            projectRoot: projectRoot,
            engine: engine,
            preservingReconnectState: false
        )
    }

    private func startInternal(
        contentRoot: URL,
        projectRoot: URL,
        engine: BorisEngine?,
        preservingReconnectState preserve: Bool
    ) {
        lastContentRoot = contentRoot
        lastProjectRoot = projectRoot
        lastEngine = engine
        let root = contentRoot.standardizedFileURL.path
        if root == rootPath, let server, server.isRunning {
            if let url = server.editorURL {
                phase = .connected(url)
            }
            return
        }
        // A fresh lifecycle cancels any pending auto-restart (source switch,
        // re-selected source); the automatic restart itself must preserve the
        // counter so crashes accumulate toward the cap (#232).
        if !preserve {
            cancelAutoReconnect()
        }
        teardown()
        rootPath = root

        guard let engine else {
            setPhase(.failed(.engineUnavailable))
            return
        }

        setPhase(.starting)
        scheduleTimeout()
        do {
            let server = try makeHost(engine, projectRoot)
            self.server = server
            server.onConnect = { [weak self] url in
                Task { @MainActor in self?.handleConnect(url: url) }
            }
            server.onExit = { [weak self] exit in
                Task { @MainActor in self?.handleExit(exit) }
            }
        } catch let error as EditorHostLaunchError {
            timeoutTask?.cancel()
            timeoutTask = nil
            // Permanent configuration error — surface verbatim through the
            // typed case, never a crash-reconnect candidate (#232).
            setPhase(.failed(EditorSessionError(error)))
        } catch {
            timeoutTask?.cancel()
            timeoutTask = nil
            setPhase(.failed(.launchFailed("\(error)")))
        }
    }

    /// Tears down the current host (if any) and starts a fresh one for the
    /// same content root. A new random token URL is printed by the new host,
    /// so the web view reconnects via the existing `editorURL` observation.
    ///
    /// Manual entry point (#232): cancels any pending auto-reconnect and
    /// resets its crash counter — the gate treats manual restarts as a
    /// deliberate fresh start.
    func restart() {
        beginRestart(preservingReconnectState: false)
    }

    /// Shared restart path. The automatic reconnect passes
    /// `preservingReconnectState: true` so crash counts accumulate across
    /// auto-restarts; every other caller resets them. Teardown happens
    /// unconditionally — a manual restart must bounce even a healthy host,
    /// and `startInternal`'s idempotent early-return must not short-circuit it.
    private func beginRestart(preservingReconnectState preserve: Bool) {
        guard let contentRoot = lastContentRoot, let projectRoot = lastProjectRoot else { return }
        if !preserve {
            cancelAutoReconnect()
        }
        teardown()
        startInternal(
            contentRoot: contentRoot,
            projectRoot: projectRoot,
            engine: lastEngine,
            preservingReconnectState: preserve
        )
    }

    func fail(_ error: EditorSessionError) {
        cancelAutoReconnect()
        teardown()
        setPhase(.failed(error))
    }

    func stop() {
        cancelAutoReconnect()
        teardown()
    }

    /// Tears down the host and returns the session to idle without touching
    /// auto-reconnect bookkeeping (callers decide whether to reset it).
    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let server {
            server.onConnect = nil
            server.onExit = nil
            server.stop()
            self.server = nil
        }
        rootPath = nil
        setPhase(.idle)
    }

    private func handleConnect(url: URL) {
        timeoutTask?.cancel()
        timeoutTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        // Direct assignment, not setPhase(_:): a notice raised by this very
        // connect must survive landing in the connected phase.
        phase = .connected(url)
        if !reconnectCrashes.isEmpty {
            transientNotice = "Editor host restarted"
        }
        reconnectCrashes.removeAll()
    }

    private func handleExit(_ exit: EditorExit) {
        // Only spontaneous exits reach this callback: stop()/fail()/teardown
        // nil the callbacks before the old process can report, so a manual
        // Restart Host, Stop, window close, or source switch never lands here.
        guard server != nil else { return }
        server = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        rootPath = nil

        // Exit 0 is a clean shutdown (SIGTERM via stop()), never a crash (#232).
        guard exit.exitCode != 0 || exit.signalled else {
            setPhase(.idle)
            return
        }

        let now = ContinuousClock.now
        reconnectCrashes.append(now)
        reconnectCrashes = EditorAutoReconnect.prune(reconnectCrashes, now: now)

        switch EditorAutoReconnect.decision(crashesInWindow: reconnectCrashes.count) {
        case .retry(let attempt):
            setPhase(.reconnecting(attempt: attempt))
            scheduleAutoReconnect(after: reconnectBaseDelay * attempt)
        case .giveUp:
            setPhase(.failed(.crashLoop(stderrTail: exit.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines))))
        }
    }

    private func scheduleAutoReconnect(after delay: Duration) {
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.beginRestart(preservingReconnectState: true)
        }
    }

    private func scheduleTimeout() {
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: EditorSession.connectTimeout)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.failTimeout()
        }
    }

    private func failTimeout() {
        server?.stop()
        server = nil
        timeoutTask = nil
        rootPath = nil
        setPhase(.failed(.timeout))
    }

    /// Phase transitions leave the connected state, so any transient
    /// "Editor host restarted" notice dies with it.
    private func setPhase(_ newPhase: Phase) {
        if case .connected = newPhase {} else { transientNotice = nil }
        phase = newPhase
    }

    /// Cancels a pending automatic restart and clears its crash counter.
    /// Manual actions and successful connections come through here.
    private func cancelAutoReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectCrashes.removeAll()
    }
}
