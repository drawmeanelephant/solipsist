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

    // MARK: - Polished status bar helpers (M14 / #208)

    var statusVerbText: String {
        if coordinator.isRunning {
            return coordinator.verb?.rawValue ?? "running"
        }
        if let lastVerb = coordinator.lastVerb {
            return lastVerb.rawValue
        }
        return coordinator.state == .watching ? "watching" : "idle"
    }

    var statusExitText: String {
        if coordinator.isRunning { return "running" }
        return coordinator.exitCode.map { "exit \($0)" } ?? "exit 0"
    }

    var statusExitIsFailure: Bool {
        guard !coordinator.isRunning else { return false }
        if let code = coordinator.exitCode { return code != 0 }
        return false
    }

    var statusTooltip: String? {
        guard let last = coordinator.activityHistory.first else { return nil }
        var parts: [String] = []
        if let ns = last.durationNs {
            parts.append(formatDuration(ns))
        }
        if let timings = last.timings {
            if let total = timings.totalNs, last.durationNs != total {
                parts.append("total \(formatDuration(total))")
            }
            if let phases = timings.phases, !phases.isEmpty {
                let sorted = phases.sorted { $0.key < $1.key }
                let phaseStr = sorted.map { "\($0.key): \(formatDuration($0.value))" }
                    .joined(separator: ", ")
                parts.append(phaseStr)
            }
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }

    private func formatDuration(_ ns: Int) -> String {
        if ns < 1_000 { return "\(ns) ns" }
        if ns < 1_000_000 { return "\(ns / 1_000) µs" }
        if ns < 1_000_000_000 { return "\(ns / 1_000_000) ms" }
        let seconds = Double(ns) / 1_000_000_000.0
        return String(format: "%.2f s", seconds)
    }

    // MARK: - Compose line-jump (M11 #207)

    struct ComposeJumpRequest: Equatable, Sendable {
        let pageID: String
        let line: Int
        let column: Int?
    }

    var pendingComposeJump: ComposeJumpRequest?
}
