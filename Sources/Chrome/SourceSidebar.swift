import SwiftUI

/// Left column. Each source is an account header; mailboxes are the folders.
struct SourceSidebar: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        List(selection: selectedRow) {
            ForEach(store.sources) { item in
                Section {
                    ForEach(WorkspaceMailbox.all, id: \.self) { box in
                        Label(
                            WorkspaceMailbox.displayName(box),
                            systemImage: WorkspaceMailbox.symbolName(box)
                        )
                        .tag(MailboxRowID(sourceID: item.id, mailbox: box))
                        .contextMenu { sourceMenu(item) }
                    }
                } header: {
                    SourceAccountHeader(item: item)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.select(item.id, mailbox: WorkspaceMailbox.pages)
                        }
                        .contextMenu { sourceMenu(item) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mailboxes")
        .overlay {
            if store.sources.isEmpty {
                EmptyStateView(
                    title: "No Sources",
                    systemImage: "folder.badge.plus",
                    message: "Open a folder with boris.json (e.g. Stunts/happy) to get started.",
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

    private var selectedRow: Binding<MailboxRowID?> {
        Binding(
            get: {
                guard let id = store.selection.sourceID else { return nil }
                return MailboxRowID(
                    sourceID: id,
                    mailbox: WorkspaceMailbox.display(store.selection.mailbox)
                )
            },
            set: { row in
                guard let row else {
                    store.select(nil)
                    return
                }
                store.select(row.sourceID, mailbox: row.mailbox)
            }
        )
    }

    @ViewBuilder
    private func sourceMenu(_ item: SourceItem) -> some View {
        if !item.isAvailable {
            Button("Relocate…") {
                store.presentRelocatePanel(for: item.id)
            }
        }
        Button("Remove from Sidebar", role: .destructive) {
            store.remove(item.id)
        }
    }
}

private struct SourceAccountHeader: View {
    let item: SourceItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                if !item.isAvailable {
                    Text("Unreachable — Relocate / Remove")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if let detail = item.detailLine {
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
                .foregroundStyle(item.isAvailable ? Color.primary : Color.orange)
        }
        .help(
            item.isAvailable
                ? (item.detailLine ?? item.title)
                : "Unreachable — Relocate / Remove"
        )
    }
}
