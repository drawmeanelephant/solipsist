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

    /// The helper URL (`…/__boris/`) the web view should load, if serving.
    var serveURL: URL? {
        if case .serving(let url) = phase { return url }
        return nil
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
            return "Serving \(url.absoluteString)"
        case .failed(let message):
            return message
        }
    }

    private var server: WatchServer?
    private var rootPath: String?
    private var timeoutTask: Task<Void, Never>?

    func start(contentRoot: URL, projectRoot: URL, engine: BorisEngine?) {
        let root = contentRoot.standardizedFileURL.path
        if root == rootPath, let server, server.isRunning {
            if let url = server.serveURL {
                phase = .serving(url)
            }
            // Port line still pending → still starting; the in-flight server
            // owns the timeout. Either way: reuse, no rebuild.
            return
        }
        stop()
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
            server.onServe = { [weak self] url in
                Task { @MainActor in self?.handleServe(url: url) }
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
        timeoutTask?.cancel()
        timeoutTask = nil
        server?.onServe = nil
        server?.onExit = nil
        server?.stop()
        server = nil
        rootPath = nil
        phase = .failed(message)
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        if let server {
            server.onServe = nil
            server.onExit = nil
            server.stop()
            self.server = nil
        }
        rootPath = nil
        phase = .idle
    }

    // MARK: Server callbacks (hopped to the main actor)

    private func handleServe(url: URL) {
        timeoutTask?.cancel()
        timeoutTask = nil
        phase = .serving(url)
    }

    private func handleExit(_ exit: WatchExit) {
        // We stopped it on purpose; the callbacks were cleared first, so the
        // only exits that land here are spontaneous ones.
        guard server != nil else { return }
        server = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        rootPath = nil
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
        server?.stop()
        server = nil
        timeoutTask = nil
        rootPath = nil        phase = .failed("preview server did not report a port within 15s")
    }
}
