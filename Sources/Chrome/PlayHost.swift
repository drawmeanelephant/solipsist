import SwiftUI

/// Middle slot. Dispatches to the play surface for the selected source kind.
/// New kinds add a case here (one line) and a folder under `Sources/Play/`.
///
/// Also binds the shared `PreviewSession` to the selected source so the
/// reading pane can observe the watch when the companion is closed. Does
/// not auto-start from idle.
struct PlayHost: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        Group {
            if let item = store.selectedSource {
                switch item {
                case .local(let source):
                    LocalPlay(source: source)
                }
            } else if store.sources.isEmpty {
                EmptyStateView(
                    title: "No Sources",
                    systemImage: "folder.badge.plus",
                    message: "Open a folder with boris.json (e.g. Stunts/happy) to begin.",
                    actionTitle: "Open…",
                    action: { store.presentOpenPanel() }
                )
            } else {
                EmptyStateView(
                    title: "No Source Selected",
                    systemImage: "sidebar.left",
                    message: "Select a source from the sidebar to view its publication."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncPreviewSession() }
        .onChange(of: store.selection.sourceID) { syncPreviewSession() }
        .onChange(of: store.selectedSource?.isAvailable) { syncPreviewSession() }
    }

    private func syncPreviewSession() {
        let session = runtime.previewSession
        guard
            case .local(let local) = store.selectedSource,
            local.isAvailable,
            let content = try? local.contentRoot(),
            let project = try? local.workspaceRoot()
        else {
            if session.phase != .idle { session.stop() }
            return
        }
        switch session.phase {
        case .idle, .failed:
            return
        case .starting, .serving:
            if !session.isBound(to: content) {
                session.start(
                    contentRoot: content,
                    projectRoot: project,
                    engine: runtime.engine,
                    coordinator: runtime.coordinator
                )
            }
        }
    }
}
