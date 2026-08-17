import SwiftUI

/// Left column. A source list, Mail-style — accounts, not a file tree.
struct SourceSidebar: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: selectedSource) {
            Section("Sources") {
                ForEach(store.sources) { item in
                    SourceRow(item: item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Remove from Sidebar", role: .destructive) {
                                store.remove(item.id)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Sources")
        .overlay {
            if store.sources.isEmpty {
                EmptyStateView(
                    title: "No Sources",
                    systemImage: "tray",
                    message: "Open a local folder to add a source.",
                    actionTitle: "Open…",
                    action: { store.presentOpenPanel() }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { store.presentOpenPanel() }) {
                    Label("Open…", systemImage: "plus")
                }
                .help("Open a local folder")
            }
        }
    }

    private var selectedSource: Binding<SourceID?> {
        Binding(
            get: { store.selection.sourceID },
            set: { store.select($0) }
        )
    }
}

private struct SourceRow: View {
    let item: SourceItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                if let detail = item.detailLine {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } icon: {
            Image(systemName: item.symbolName)
                .symbolVariant(item.isAvailable ? .none : .slash)
                .foregroundStyle(item.isAvailable ? .primary : .secondary)
        }
        .help(item.detailLine ?? item.title)
    }
}
