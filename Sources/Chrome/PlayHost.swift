import SwiftUI

/// Middle slot. Dispatches to the play surface for the selected source kind.
/// New kinds add a case here (one line) and a folder under `Sources/Play/`.
struct PlayHost: View {
    @Environment(WorkspaceStore.self) private var store

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
    }
}
