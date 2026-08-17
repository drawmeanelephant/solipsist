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
            } else {
                EmptyStateView(
                    title: "No Source",
                    systemImage: "tray",
                    message: "Open a local folder to begin."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
