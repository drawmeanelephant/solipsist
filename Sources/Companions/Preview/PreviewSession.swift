import Foundation
import Observation

/// Drives the M4 preview surface (D5): owns the `boris watch --serve`
/// lifetime for the selected source and hands the served helper URL to the
/// preview web view.
///
/// Main-actor confined. `start` is idempotent for the same content root —
/// reopening the window reuses a live server instead of rebuilding. A
/// server takes over when the port line (`preview: http://127.0.0.1:PORT/`)
/// arrives on stderr; if it never arrives within 15 seconds, the phase
/// degrades to `failed` and the server is stopped so it cannot linger.
@MainActor
@Observable
final class PreviewSession {
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

    var statusText: String {
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
    private var rootPath: String?
    private var timeoutTask: Task<Void, Never>?
    private weak var coordinator: Coordinator?

    func start(contentRoot: URL, projectRoot: URL, engine: BorisEngine?, coordinator: Coordinator?) {
        self.coordinator = coordinator
        let root = contentRoot.standardizedFileURL.path
        if root == rootPath, let server, server.isRunning {
            coordinator?.registerWatch(server)
            if let url = server.serveURL {
                phase = .serving(url)
            }
            // Port line still pending → still starting; the in-flight server
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
            let server = try engine.previewStart(
                contentRoot: contentRoot,
                workingDirectory: projectRoot,
                port: 0
            )
            self.server = server
            coordinator?.registerWatch(server)
            server.onServe = { [weak self] url in
                Task { @MainActor in self?.handleServe(url: url) }
            }
            server.onProblem = { [weak self] message in
                Task { @MainActor in self?.handleProblem(message) }
            }
            server.onExit = { [weak self] exit in
                Task { @MainActor in self?.handleExit(exit) }
            }
        } catch {
            timeoutTask?.cancel()
            timeoutTask = nil
            phase = .failed("could not start preview server: \(error)")
        }
    }

    /// Surfaces a non-server failure (e.g. an unresolvable content root),
    /// tearing down any live server so nothing leaks.
    func fail(_ message: String) {
        teardownServer()
        rootPath = nil
        phase = .failed(message)
    }

    func stop() {
        teardownServer()
        rootPath = nil
        phase = .idle
    }

    private func teardownServer() {
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
        coordinator?.unregisterWatch(server)
        self.server = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        rootPath = nil
        lastProblem = nil
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
