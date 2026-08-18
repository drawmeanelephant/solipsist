import Foundation
import Observation

/// Drives the M6 author companion surface (A14 / #75): owns the `boris-editor`
/// subprocess host lifetime and hands the tokenized session URL to the editor web view.
@MainActor
@Observable
final class EditorSession {
    enum Phase: Equatable {
        case idle
        case starting
        case connected(URL)
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    var editorURL: URL? {
        if case .connected(let url) = phase { return url }
        return nil
    }

    var isFailure: Bool {
        if case .failed = phase { return true }
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
        case .failed(let message):
            return message
        }
    }

    private var server: EditorServer?
    private var rootPath: String?
    private var timeoutTask: Task<Void, Never>?

    func start(contentRoot: URL, projectRoot: URL, engine: BorisEngine?) {
        let root = contentRoot.standardizedFileURL.path
        if root == rootPath, let server, server.isRunning {
            if let url = server.editorURL {
                phase = .connected(url)
            }
            return
        }
        stop()
        rootPath = root

        guard let engine else {
            phase = .failed("Boris engine not available.")
            return
        }

        guard let editorBinary = findEditorBinary(relativeTo: engine.binaryURL) else {
            phase = .failed("boris-editor binary not found. Set SOLIPSIST_BORIS_EDITOR_BIN or build the editor host.")
            return
        }

        phase = .starting
        scheduleTimeout()
        do {
            let server = try engine.editorStart(
                editorBinary: editorBinary,
                contentRoot: contentRoot,
                workingDirectory: projectRoot,
                port: 0
            )
            self.server = server
            server.onConnect = { [weak self] url in
                Task { @MainActor in self?.handleConnect(url: url) }
            }
            server.onExit = { [weak self] exit in
                Task { @MainActor in self?.handleExit(exit) }
            }
        } catch {
            timeoutTask?.cancel()
            timeoutTask = nil
            phase = .failed("Could not start editor host: \(error)")
        }
    }

    func fail(_ message: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        server?.onConnect = nil
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
            server.onConnect = nil
            server.onExit = nil
            server.stop()
            self.server = nil
        }
        rootPath = nil
        phase = .idle
    }

    private func handleConnect(url: URL) {
        timeoutTask?.cancel()
        timeoutTask = nil
        phase = .connected(url)
    }

    private func handleExit(_ exit: EditorExit) {
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
            phase = .failed("Editor host exited (\(exit.exitCode))\(suffix)")
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
        rootPath = nil
        phase = .failed("Editor host did not report a token URL within 15s.")
    }

    private func findEditorBinary(relativeTo engineBinary: URL) -> URL? {
        let env = ProcessInfo.processInfo.environment["SOLIPSIST_BORIS_EDITOR_BIN"]
        if let env, !env.isEmpty, FileManager.default.isExecutableFile(atPath: env) {
            return URL(fileURLWithPath: env)
        }

        let sibling = engineBinary.deletingLastPathComponent().appendingPathComponent("boris-editor")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        let bundled = Bundle.main.url(forResource: "boris-editor", withExtension: nil)
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        return nil
    }
}
