import AppKit
import SwiftUI

/// What the Editor companion shows while the web view has no URL.
/// The window auto-starts the host on appear (`.task(id:)` in
/// `EditorWindow`), so `.starting` / `.reconnecting` / `.connected`
/// get a live progress state — "Editor Host Not Running" is only for
/// genuinely idle/failed sessions, where the #267 copy and #280
/// failure guidance do their work.
struct EditorHostStateView: View {
    let session: EditorSession
    let model: EditorWebModel

    var body: some View {
        switch session.phase {
        case .starting, .reconnecting, .connected:
            VStack(spacing: 10) {
                ProgressView()
                Text(session.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle, .failed:
            idleState
        }
    }

    private var idleState: some View {
        ContentUnavailableView {
            Label("Editor Host Not Running", systemImage: "square.and.pencil")
        } description: {
            VStack(alignment: .leading, spacing: 8) {
                if let guidance = errorGuidance {
                    Text(guidance.headline)
                        .font(.body)
                    Text(guidance.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("The Boris editor connects when the host process is running.")
                    // #267: lead with the action; manual connect is the
                    // last-resort sentence, matching #237's collapsed field.
                    Text(EditorIdleCopy.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } actions: {
            Button("Restart Host") {
                session.restart()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!session.canRestart)

            Button("Open in Browser") {
                if let url = session.editorURL ?? model.currentURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(session.editorURL == nil && model.currentURL == nil)
        }
    }

    /// #280: Maps typed failures from the session to actionable guidance;
    /// the case-to-copy switch lives in `EditorFailureGuidance` where it is
    /// compiler-checked against `EditorSessionError`.
    private var errorGuidance: EditorFailureGuidance.Guidance? {
        guard case .failed(let error) = session.phase else { return nil }
        return EditorFailureGuidance.guidance(for: error)
    }
}
