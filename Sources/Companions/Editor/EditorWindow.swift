import SwiftUI

/// Companion host for `boris-editor` (Svelte). Chassis registers the window
/// and leaves it closed. The Editor lane owns this file.
struct EditorWindow: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("Editor", systemImage: "square.and.pencil")
        } description: {
            Text(description)
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle("Editor")
    }

    private var description: String {
        if let source = store.selectedSource {
            return "The Boris editor for “\(source.title)” will load here."
        }
        return "Select a source in the main window, then open the editor."
    }
}
