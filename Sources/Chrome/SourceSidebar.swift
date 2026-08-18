import SwiftUI

/// Left column. Each source is an account header; mailboxes are the folders.
struct SourceSidebar: View {
    @Environment(WorkspaceStore.self) private var store

    @State private var toolbarBand: CGFloat = 0
    @State private var collapsedSources: Set<SourceID> = []

    var body: some View {
        List(selection: selectedRow) {
            ForEach(store.sources) { item in
                SourceSection(
                    item: item,
                    isExpanded: isExpanded(for: item.id),
                    store: store
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mailboxes")
        .safeAreaPadding(.top, max(toolbarBand, 62))
        .background(ToolbarBandReader { toolbarBand = $0 })
        .overlay {
            if store.sources.isEmpty {
                EmptyStateView(
                    title: "No Sources",
                    systemImage: "folder.badge.plus",
                    message: "Add a folder with boris.json from Settings → Sources or File → Open… (for example Stunts/happy).",
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

    private func isExpanded(for sourceID: SourceID) -> Binding<Bool> {
        Binding(
            get: { !collapsedSources.contains(sourceID) },
            set: { expanded in
                if expanded {
                    collapsedSources.remove(sourceID)
                } else {
                    collapsedSources.insert(sourceID)
                }
            }
        )
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
}

private struct SourceSection: View {
    let item: SourceItem
    @Binding var isExpanded: Bool
    let store: WorkspaceStore

    var body: some View {
        Section(isExpanded: $isExpanded) {
            ForEach(WorkspaceMailbox.all, id: \.self) { box in
                MailboxRow(item: item, box: box)
                    .tag(MailboxRowID(sourceID: item.id, mailbox: box))
                    .contextMenu { sourceMenu(item) }
            }
        } header: {
            SourceAccountHeader(item: item)
                .contextMenu { sourceMenu(item) }
        }
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

private struct MailboxRow: View {
    let item: SourceItem
    let box: String

    var body: some View {
        Label {
            Text(WorkspaceMailbox.displayName(box))
                .font(.system(size: 12.5, weight: .regular))
        } icon: {
            Image(systemName: WorkspaceMailbox.symbolName(box))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(item.title), \(WorkspaceMailbox.displayName(box))")
    }
}

private struct SourceAccountHeader: View {
    let item: SourceItem

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: item.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .symbolVariant(item.isAvailable ? .none : .slash)
                .foregroundStyle(item.isAvailable ? Color.accentColor : Color.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !item.isAvailable {
                    Text("Unreachable — Relocate / Remove")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .help(
            item.isAvailable
                ? (item.detailLine ?? item.title)
                : "Unreachable — Relocate / Remove"
        )
        .accessibilityLabel(
            item.isAvailable
                ? item.title
                : "\(item.title), unreachable"
        )
        .accessibilityHint(
            item.isAvailable
                ? "Select this account"
                : "Unreachable. Relocate or remove this source."
        )
    }
}
