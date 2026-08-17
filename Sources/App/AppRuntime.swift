import Foundation
import Observation

/// Process-wide runtime: the engine identity, not the workspace.
/// Companions and the status bar read this; they do not spawn `boris`.
@MainActor
@Observable
final class AppRuntime {
    let engine: BorisEngine?
    let enginePath: String?
    let engineError: String?

    init() {
        if let url = BorisBinary.locate() {
            enginePath = url.path
            do {
                engine = try BorisEngine(binaryURL: url)
                engineError = nil
            } catch {
                engine = nil
                engineError = String(describing: error)
            }
        } else {
            engine = nil
            enginePath = nil
            engineError = BorisEngineError.binaryNotFound.description
        }
    }

    var statusLine: String {
        if let enginePath {
            return "engine \(URL(fileURLWithPath: enginePath).lastPathComponent)"
        }
        return "engine not found"
    }
}
