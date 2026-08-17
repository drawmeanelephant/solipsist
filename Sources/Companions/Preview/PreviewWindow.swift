import SwiftUI

/// Companion host for `boris watch --serve`. Chassis registers the window
/// and leaves it closed. The Preview lane owns this file.
struct PreviewWindow: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("Preview", systemImage: "safari")
        } description: {
            Text(description)
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle("Preview")
    }

    private var description: String {
        if let source = store.selectedSource {
            return "Preview for “\(source.title)” will load via boris watch --serve."
        }
        return "Select a source in the main window, then open Preview."
    }
}
