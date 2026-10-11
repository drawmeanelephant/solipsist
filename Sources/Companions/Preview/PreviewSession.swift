import Foundation
import Observation

@MainActor
protocol PreviewWatchCoordinating: AnyObject {
    func registerWatch(_ server: WatchServer)
    func unregisterWatch(_ server: WatchServer)
}

/// Drives the M4 preview surface (D5): owns the `boris watch --serve`
/// lifetime for the selected source and hands the served helper URL to the
/// preview web view.
///
/// Main-actor confined. `start` is idempotent for the same content root —
/// reopening the window reuses a live server instead of rebuilding. A
/// server takes over when the A1 `serve-started` event arrives on stderr;
/// if it never arrives within 15 seconds, the phase
/// degrades to `failed` and the server is stopped so it cannot linger.
@MainActor
@Observable
final class PreviewSession {
    typealias ServerFactory = @MainActor (BorisEngine, URL, URL) throws -> WatchServer

    enum Phase: Equatable {
        case idle
        case starting
        case serving(URL)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    /// Most recent problem reported by the watch stream (`build-failed` /
    /// `watch-error` / unexpected `watch-stopped`) while still serving the
    /// last good build. Surfaced in `statusText`; never swallowed.
    private(set) var lastProblem: String?

    /// The helper URL (`…/__boris/`) the web view should load, if serving.
    var serveURL: URL? {
        if case .serving(let url) = phase { return url }
        return nil
    }

    /// Content-root path this session last started, if any.
    var boundRootPath: String? { rootPath }

    func isBound(to contentRoot: URL) -> Bool {
        boundRootPath == contentRoot.standardizedFileURL.path
    }

    var isFailure: Bool {
        if case .failed = phase { return true }
        return false
    }

    /// True while the Editor companion owns the bound project's dist seat:
    /// the watch is suspended (or its start deferred) and the preview keeps
    /// whatever bytes were last rendered. The editor host holds the
    /// dist-writer seat while it lives (editor-host.md §7.4); a second
    /// `boris watch` against the same `dist/` would double every rebuild.
    private(set) var editorParked = false

    var statusText: String {
        if editorParked {
            return "Preview paused — the editor companion owns this project's builds."
        }
        switch phase {
        case .idle:
            return "Preview idle."
        case .starting:
            return "Starting boris watch…"
        case .serving(let url):
            if let lastProblem {
                return "Serving \(url.absoluteString) — \(lastProblem)"
            }
            return "Serving \(url.absoluteString)"
        case .failed(let message):
            return message
        }
    }

    private var server: WatchServer?
    private var lifecycleID = UUID()
    private let makeServer: ServerFactory
    private var rootPath: String?
    private var timeoutTask: Task<Void, Never>?
    private weak var coordinator: (any PreviewWatchCoordinating)?
    /// The content root the Editor companion currently owns, if any.
    private var editorOwnedRoot: String?
    /// A `start` deferred while the editor owned the project; replayed on
    /// unpark so the preview comes up the moment the seat frees.
    private var deferredStart: DeferredStart?

    /// A preview start parked behind the editor companion's dist seat.
    private struct DeferredStart {
        let contentRoot: URL
        let projectRoot: URL
        let engine: BorisEngine?
    }

    init(makeServer: @escaping ServerFactory = { engine, contentRoot, projectRoot in
        try engine.previewStart(contentRoot: contentRoot, workingDirectory: projectRoot, port: 0)
    }) {
        self.makeServer = makeServer
    }

    func start(contentRoot: URL, projectRoot: URL, engine: BorisEngine?, coordinator: (any PreviewWatchCoordinating)?) {
        let root = contentRoot.standardizedFileURL.path
        if root == editorOwnedRoot {
            deferStart(
                DeferredStart(contentRoot: contentRoot, projectRoot: projectRoot, engine: engine),
                root: root,
                coordinator: coordinator
            )
            return
        }
        editorParked = false
        deferredStart = nil
        if root == rootPath, let server, server.isRunning {
            self.coordinator = coordinator
            coordinator?.registerWatch(server)
            if let url = server.serveURL {
                phase = .serving(url)
            }
            // Serve event still pending → still starting; the in-flight server
            // owns the timeout. Either way: reuse, no rebuild.
            return
        }
        stop()
        self.coordinator = coordinator
        rootPath = root

        guard let engine else {
            phase = .failed("boris engine not found (make build with a boris checkout)")
            return
        }

        phase = .starting
        scheduleTimeout()
        do {
            let server = try makeServer(engine, contentRoot, projectRoot)
            self.server = server
            coordinator?.registerWatch(server)
            wireCallbacks(server)
            if server.isRunning, let url = server.serveURL { handleServe(url: url) }
        } catch {
            timeoutTask?.cancel()
            timeoutTask = nil
            phase = .failed("could not start preview server: \(error)")
        }
    }

    /// Installs lifecycle-gated server callbacks: a stale server (previous
    /// `start` generation, torn down mid-flight) can never mutate phase.
    private func wireCallbacks(_ server: WatchServer) {
        let lifecycleID = self.lifecycleID
        server.onServe = { [weak self] url in
            Task { @MainActor in
                guard let self, self.lifecycleID == lifecycleID, self.server != nil else { return }
                self.handleServe(url: url)
            }
        }
        server.onProblem = { [weak self] message in
            Task { @MainActor in
                guard let self, self.lifecycleID == lifecycleID, self.server != nil else { return }
                self.handleProblem(message)
            }
        }
        server.onExit = { [weak self] exit in
            Task { @MainActor in
                guard let self, self.lifecycleID == lifecycleID else { return }
                self.handleExit(exit)
            }
        }
    }

    /// The editor companion owns this project's dist seat — park the
    /// watch rather than spawn a second writer. `unparkForEditor`
    /// replays the deferred start.
    private func deferStart(_ start: DeferredStart, root: String, coordinator: (any PreviewWatchCoordinating)?) {
        teardownServer()
        self.coordinator = coordinator
        rootPath = root
        editorParked = true
        deferredStart = start
        phase = .idle
    }

    /// Record the Editor companion holding the dist-writer seat for
    /// `contentRoot` (it connected to this project). A bound watch is
    /// suspended — not stopped — so the parked helper page keeps its
    /// rendered bytes; a start for the same root defers instead of
    /// spawning a second writer. A parked start cancels the serve timeout:
    /// a frozen process cannot report its port.
    func parkForEditor(contentRoot: URL) {
        let root = contentRoot.standardizedFileURL.path
        if editorOwnedRoot != root {
            // The editor moved to a different project: lift the old seat
            // before claiming the new one.
            server?.resume(reason: .editorCompanion)
            editorParked = false
            if case .starting = phase {
                scheduleTimeout()
            }
        }
        editorOwnedRoot = root
        guard rootPath == root else { return }
        editorParked = true
        timeoutTask?.cancel()
        timeoutTask = nil
        server?.suspend(reason: .editorCompanion)
    }

    /// The Editor companion disconnected or closed; the seat frees. A
    /// parked watch resumes (SIGCONT); a deferred start is replayed into a
    /// fresh `start` so the preview comes up on its own.
    ///
    /// `contentRoot` nil releases the seat unconditionally (safety net);
    /// non-nil releases only when the caller held the seat for that root,
    /// so one session cannot lift a different editor's claim.
    func unparkForEditor(contentRoot: URL? = nil) {
        if let contentRoot {
            guard editorOwnedRoot == contentRoot.standardizedFileURL.path else { return }
        }
        guard editorOwnedRoot != nil || editorParked else { return }
        editorOwnedRoot = nil
        editorParked = false
        server?.resume(reason: .editorCompanion)
        if case .starting = phase {
            scheduleTimeout()
        }
        if let pending = deferredStart {
            deferredStart = nil
            start(
                contentRoot: pending.contentRoot,
                projectRoot: pending.projectRoot,
                engine: pending.engine,
                coordinator: coordinator
            )
        }
    }

    /// Surfaces a non-server failure (e.g. an unresolvable content root),
    /// tearing down any live server so nothing leaks.
    func fail(_ message: String) {
        teardownServer()
        deferredStart = nil
        editorParked = false
        rootPath = nil
        phase = .failed(message)
    }

    func stop() {
        teardownServer()
        deferredStart = nil
        editorParked = false
        rootPath = nil
        phase = .idle
    }

    private func teardownServer() {
        lifecycleID = UUID()
        lastProblem = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        if let server {
            coordinator?.unregisterWatch(server)
            server.onServe = nil
            server.onProblem = nil
            server.onExit = nil
            server.stop()
            self.server = nil
        }
    }

    // MARK: Server callbacks (hopped to the main actor)

    private func handleServe(url: URL) {
        timeoutTask?.cancel()
        timeoutTask = nil
        lastProblem = nil
        phase = .serving(url)
    }

    /// Surfaces a watch-stream problem. While serving, the last good build
    /// keeps serving and the problem shows in the status line; before the
    /// port arrives, it fails the phase like a non-zero exit would.
    private func handleProblem(_ message: String) {
        if case .serving = phase {
            lastProblem = message
        } else {
            phase = .failed(message)
        }
    }

    private func handleExit(_ exit: WatchExit) {
        // We stopped it on purpose; the callbacks were cleared first, so the
        // only exits that land here are spontaneous ones.
        guard let server else { return }
        lifecycleID = UUID()
        coordinator?.unregisterWatch(server)
        self.server = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        rootPath = nil
        lastProblem = nil
        deferredStart = nil
        editorParked = false
        if exit.exitCode == 0 {
            phase = .idle
        } else {
            let tail = exit.stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = tail.isEmpty ? "" : " — \(tail.suffix(200))"
            phase = .failed("preview server exited (\(exit.exitCode))\(suffix)")
        }
    }

    private func scheduleTimeout() {
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.failTimeout()
        }
    }

    private func failTimeout() {
        teardownServer()
        rootPath = nil
        phase = .failed("preview server did not report a port within 15s")
    }
}
