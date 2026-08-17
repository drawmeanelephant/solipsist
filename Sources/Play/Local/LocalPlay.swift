import SwiftUI

/// Play surface for a local folder. Chassis ships the empty host; M3 fills it.
struct LocalPlay: PlaySurface {
    let source: LocalSource

    var body: some View {
        ContentUnavailableView {
            Label(source.title, systemImage: "folder")
        } description: {
            Text(source.isAvailable
                ? "The graph, outputs, and activity for this folder will appear here."
                : "This folder is no longer reachable. Remove it from the sidebar or reopen it.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(source.title)
    }
}
