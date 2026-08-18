import Foundation
import Observation

/// Process-wide runtime: engine identity, coordinator, and the one
/// preview watch session (lifted from the companion so Play can observe
/// it). Companions and Play ask this type; they do not spawn `boris`.
@MainActor
@Observable
final class AppRuntime {
    private(set) var engine: BorisEngine?
    private(set) var enginePath: String?
    private(set) var engineError: String?
    private(set) var engineVersion: String
    let coordinator = Coordinator()
    let credentials = PublishCredentialManager()
    let previewSession = PreviewSession()

    init() {
        engineVersion = "boris"
        reloadEngine()
    }

    func reloadEngine() {
        if let url = BorisBinary.locate() {
            enginePath = url.path
            do {
                let eng = try BorisEngine(binaryURL: url)
                engine = eng
                engineError = nil
                engineVersion = "boris"
                Task { [weak self] in
                    if let v = try? await eng.version() {
                        await MainActor.run {
                            self?.engineVersion = v.line
                        }
                    }
                }
            } catch {
                engine = nil
                engineError = String(describing: error)
                engineVersion = "boris not found"
            }
        } else {
            engine = nil
            enginePath = nil
            engineError = BorisEngineError.binaryNotFound.description
            engineVersion = "boris not found"
        }
    }

    func statusLine(selectedSourceTitle: String?) -> String {
        let sourceTitle = selectedSourceTitle ?? "No source"
        let verbText: String
        let exitText: String
        if coordinator.isRunning {
            verbText = coordinator.verb?.rawValue ?? "running"
            exitText = "running"
        } else if let lastVerb = coordinator.lastVerb {
            verbText = lastVerb.rawValue
            exitText = coordinator.exitCode.map { "exit \($0)" } ?? "exit 0"
        } else {
            verbText = coordinator.state == .watching ? "watching" : "idle"
            exitText = coordinator.exitCode.map { "exit \($0)" } ?? "exit 0"
        }
        return "\(sourceTitle) · \(verbText) · \(exitText) · \(engineVersion)"
    }

    var statusLine: String {
        statusLine(selectedSourceTitle: nil)
    }
}
