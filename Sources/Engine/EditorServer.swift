import Foundation

/// How a long-running `boris-editor` process ended.
public struct EditorExit: Sendable {
    public let exitCode: Int32
    public let signalled: Bool
    public let stderrTail: String
}

/// The M6 author companion host (A14 / #75): a long-lived `boris-editor` subprocess.
///
/// Runs `boris-editor <projectRoot> --boris <engineBinary> --port 0` with
/// `cwd = projectRoot`. DIR must be the project folder (the one that
/// contains `content/`) — afterparty `project.discover` rejects a
/// content-tree path with "has no content directory". The startup line
/// on stderr:
///
///     BORIS_EDITOR_URL=http://127.0.0.1:<port>/#token=<32 hex chars>
///
/// `onConnect` fires once with the tokenized URL. `stop()` sends SIGTERM
/// (A14 graceful exit 0).
public final class EditorServer: @unchecked Sendable {
    public var onConnect: ((URL) -> Void)?
    public var onExit: ((EditorExit) -> Void)?

    private let lock = NSLock()
    private var process: Process?
    private let stderrPipe = Pipe()
    private var stderrAccumulator = Data()
    private var stderrTailText = ""
    private var _editorURL: URL?
    private var didConnect = false

    public init(
        editorBinary: URL,
        engineBinary: URL,
        projectRoot: URL,
        uiDir: URL? = nil,
        port: Int = 0
    ) {
        let process = Process()
        process.executableURL = editorBinary
        var args = [
            projectRoot.path,
            "--boris", engineBinary.path,
            "--port", String(port),
        ]
        if let uiDir {
            args.append(contentsOf: ["--ui-dir", uiDir.path])
        }
        process.arguments = args
        process.currentDirectoryURL = projectRoot
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        self.process = process
    }

    deinit {
        stop()
    }

    public var editorURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return _editorURL
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    public func start() throws {
        lock.lock()
        guard let process else {
            lock.unlock()
            throw BorisRunnerError.launchFailed("editor server already stopped")
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

    public func stop() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
    }

    private func consume(_ data: Data) {
        lock.lock()
        stderrAccumulator.append(data)
        if stderrAccumulator.count > 65_536 {
            stderrAccumulator.removeFirst(stderrAccumulator.count - 32_768)
        }
        stderrTailText = String(decoding: stderrAccumulator.suffix(4_096), as: UTF8.self)

        var url: URL?
        var connectCallback: ((URL) -> Void)?
        if !didConnect {
            url = scanEditorURL(in: stderrAccumulator)
            if let url {
                didConnect = true
                _editorURL = url
                connectCallback = onConnect
            }
        }
        lock.unlock()

        if let url, let connectCallback {
            connectCallback(url)
        }
    }

    private func finish(_ process: Process) {
        lock.lock()
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let exit = EditorExit(
            exitCode: process.terminationStatus,
            signalled: process.terminationReason == .uncaughtSignal,
            stderrTail: stderrTailText
        )
        let onExit = self.onExit
        self.process = nil
        lock.unlock()
        onExit?(exit)
    }

    private func scanEditorURL(in data: Data) -> URL? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        for line in str.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("BORIS_EDITOR_URL=") {
                let urlString = String(trimmed.dropFirst("BORIS_EDITOR_URL=".count))
                if let url = try? EditorURL.parse(urlString) {
                    return url
                }
            }
        }
        return nil
    }
}
