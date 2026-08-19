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
    /// The github source awaiting a sign-out confirmation, when any.
    @State private var signOutItem: SourceItem?

    var body: some View {
        Section(isExpanded: $isExpanded) {
            ForEach(WorkspaceMailbox.all(for: item), id: \.self) { box in
                if box == WorkspaceMailbox.pages {
                    // Pages grows trunk-folder children from the decoded
                    // graph (M13-1). No graph yet → no children, not an
                    // error; Chrome never parses JSON.
                    PagesGroup(item: item, store: store)
                } else {
                    MailboxRow(item: item, box: box)
                        .tag(MailboxRowID(sourceID: item.id, mailbox: box))
                        .contextMenu { sourceMenu(item, store: store) }
                }
            }
        } header: {
            SourceAccountHeader(item: item)
                .contextMenu {
                    sourceMenu(item, store: store)
                    if case .github = item {
                        Divider()
                        Button("Sign Out…", role: .destructive) {
                            signOutItem = item
                        }
                    }
                }
        }
        .confirmationDialog(
            signOutPrompt,
            isPresented: Binding(
                get: { signOutItem != nil },
                set: { if !$0 { signOutItem = nil } }
            ),
            titleVisibility: .visible,
            presenting: signOutItem
        ) { item in
            Button("Sign Out") {
                store.signOutGithub(item.id, deleteWorkingCopy: false)
            }
            Button("Sign Out & Move Working Copy to Trash", role: .destructive) {
                store.signOutGithub(item.id, deleteWorkingCopy: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("The GitHub token will be removed from the Keychain. The working copy stays on disk unless you move it to the Trash.")
        }
    }

    private var signOutPrompt: String {
        let name = signOutItem?.title ?? "this GitHub account"
        return "Sign Out of “\(name)”?"
    }
}

/// Pages plus its trunk-folder children. One child row per trunk;
/// the selection value is the trunk **id**. Clicking Pages writes
/// `pages`; clicking a trunk writes its raw id. Expansion is not
/// persisted (resets to expanded each launch).
private struct PagesGroup: View {
    let item: SourceItem
    let store: WorkspaceStore
    @State private var expanded = true

    private var pagesRowID: MailboxRowID {
        MailboxRowID(sourceID: item.id, mailbox: WorkspaceMailbox.pages)
    }

    private var trunks: [PlayPage] {
        guard let graph = store.graph(for: item.id) else { return [] }
        return LocalPlayGraph.trunks(from: graph)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(trunks, id: \.id) { trunk in
                TrunkRow(item: item, trunk: trunk)
                    .tag(MailboxRowID(sourceID: item.id, mailbox: trunk.id))
                    .contextMenu { sourceMenu(item, store: store) }
            }
        } label: {
            MailboxRow(item: item, box: WorkspaceMailbox.pages)
                .tag(pagesRowID)
                .contextMenu { sourceMenu(item, store: store) }
        }
    }
}

/// A trunk folder row under Pages. Label is the trunk title; the
/// selection value is the trunk id (written raw to `mailbox`).
private struct TrunkRow: View {
    let item: SourceItem
    let trunk: PlayPage

    var body: some View {
        Label {
            Text(trunk.title)
                .font(.system(size: 12.5, weight: .regular))
                .lineLimit(1)
        } icon: {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(item.title), \(trunk.title)")
    }
}

@ViewBuilder
fileprivate func sourceMenu(_ item: SourceItem, store: WorkspaceStore) -> some View {
    if !item.isAvailable {
        Button("Relocate…") {
            store.presentRelocatePanel(for: item.id)
        }
    }
    Button("Remove from Sidebar", role: .destructive) {
        store.remove(item.id)
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
