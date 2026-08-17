import SwiftUI

/// Right drawer. Renders inspector sections for the current selection; it
/// does not own that selection. The Inspector lane fills the sections.
struct InspectorDrawer: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        Group {
            if store.selection.sourceID == nil {
                drawerNote("Select a source to inspect its options.")
            } else if store.selection.noun == nil {
                drawerNote("Select something in the play place to inspect it.")
            } else {
                drawerNote("Inspector sections arrive with the Inspector lane.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func drawerNote(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
