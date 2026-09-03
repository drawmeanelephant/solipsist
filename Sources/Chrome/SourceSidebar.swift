import SwiftUI

/// Left column. Each source is an account header; mailboxes are the folders.
/// The tree shape (collapsed sources, Pages disclosures) persists across
/// launches via `WorkspaceStore.expansion` (#274).
struct SourceSidebar: View {
    @Environment(WorkspaceStore.self) private var store

    @State private var toolbarBand: CGFloat = 0
    /// #276: sidebar filter — case-insensitive trunk-title substring,
    /// in-session only (never persisted).
    @State private var folderFilter = ""

    var body: some View {
        List(selection: selectedRow) {
            ForEach(store.sources) { item in
                SourceSection(
                    item: item,
                    isExpanded: isExpanded(for: item.id),
                    store: store,
                    folderFilter: folderFilter
                )
            }
        }
        .listStyle(.sidebar)
        .searchable(
            text: $folderFilter,
            placement: .sidebar,
            prompt: "Filter folders"
        )
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
            get: { !store.expansion.collapsedSources.contains(sourceID.raw.uuidString) },
            set: { store.setSourceExpanded(sourceID, expanded: $0) }
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
    /// #276: trunk-title filter handed down from the sidebar search field.
    var folderFilter: String = ""
    /// The github source awaiting a sign-out confirmation, when any.
    @State private var signOutItem: SourceItem?

    var body: some View {
        // #296: the Recipes row is conditional on the cached graph
        // carrying ≥1 recipe node — same cached-only read as PagesGroup,
        // so a markdown-only source never sees the row.
        let graph = store.cachedGraph(for: item.id)
        Section(isExpanded: $isExpanded) {
            ForEach(WorkspaceMailbox.all(for: item, graph: graph), id: \.self) { box in
                if box == WorkspaceMailbox.pages {
                    // Pages grows trunk-folder children from the decoded
                    // graph (M13-1). No graph yet → no children, not an
                    // error; Chrome never parses JSON.
                    PagesGroup(item: item, store: store, folderFilter: folderFilter)
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
/// `pages`; clicking a trunk writes its raw id. Expansion persists
/// per source via the store (#274).
private struct PagesGroup: View {
    let item: SourceItem
    let store: WorkspaceStore
    /// #276: trunk-title filter; empty passes everything through.
    var folderFilter: String = ""

    private var pagesRowID: MailboxRowID {
        MailboxRowID(sourceID: item.id, mailbox: WorkspaceMailbox.pages)
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { SidebarExpansionState.pagesExpanded(store.expansion, id: item.id) },
            set: { store.setPagesExpanded(item.id, expanded: $0) }
        )
    }

    /// #275: cached-only read + one-pass snapshot. The async seed below
    /// fills the cache without ever decoding during body evaluation.
    private var snapshot: LocalPlayGraph.SidebarSnapshot {
        store.cachedGraph(for: item.id).map(LocalPlayGraph.snapshot) ?? .empty
    }

    private var visibleTrunks: [PlayPage] {
        snapshot.trunks.filter { SidebarNavigation.matches(filter: folderFilter, title: $0.title) }
    }

    var body: some View {
        let snap = snapshot
        Group {
            if visibleTrunks.isEmpty {
                MailboxRow(
                    item: item,
                    box: WorkspaceMailbox.pages,
                    count: snap.pageCount == 0 ? nil : snap.pageCount
                )
                .tag(pagesRowID)
                .contextMenu { sourceMenu(item, store: store) }
            } else {
                DisclosureGroup(isExpanded: isExpanded) {
                    ForEach(visibleTrunks, id: \.id) { trunk in
                        TrunkRow(item: item, trunk: trunk, count: snap.countsByTrunk[trunk.id] ?? 0)
                            .tag(MailboxRowID(sourceID: item.id, mailbox: trunk.id))
                            .contextMenu { sourceMenu(item, store: store) }
                    }
                } label: {
                    MailboxRow(
                        item: item,
                        box: WorkspaceMailbox.pages,
                        count: snap.pageCount == 0 ? nil : snap.pageCount
                    )
                    .tag(pagesRowID)
                    .contextMenu { sourceMenu(item, store: store) }
                }
            }
        }
        // #275: seed the cache off-main when this section first appears.
        .task(id: item.id) {
            store.requestGraph(for: item.id)
        }
    }
}

/// A trunk folder row under Pages. Label is the trunk title; the
/// selection value is the trunk id (written raw to `mailbox`).
private struct TrunkRow: View {
    let item: SourceItem
    let trunk: PlayPage
    var count: Int = 0
    @Environment(WorkspaceStore.self) private var store

    private var isSelected: Bool {
        store.selection.sourceID == item.id && store.selection.mailbox == trunk.id
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)
            Text(trunk.title)
                .font(.system(size: 12.5, weight: .regular))
                .lineLimit(1)
            if count > 0 {
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(trunk.title), \(count) pages")
        .accessibilityValue(isSelected ? "selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Trunk folder")
    }
}

/// #276: Reveal / Copy Path / Sync Now join Relocate and Remove — every
/// action rides an existing store API.
@ViewBuilder
fileprivate func sourceMenu(_ item: SourceItem, store: WorkspaceStore) -> some View {
    if !item.isAvailable {
        Button("Relocate…") {
            store.presentRelocatePanel(for: item.id)
        }
    } else {
        Button("Reveal in Finder") {
            store.revealInFinder(item.id)
        }
        Button("Copy Path") {
            store.copyPath(item.id)
        }
        if case .github = item, item.isSyncing {
            Button("Cancel Sync") {
                store.cancelSyncGithub(item.id)
            }
        } else if case .github = item {
            Button("Sync Now") {
                Task { await store.syncGithub(item.id) }
            }
        }
    }
    Divider()
    Button("Remove from Sidebar", role: .destructive) {
        store.remove(item.id)
    }
}

private struct MailboxRow: View {
    let item: SourceItem
    let box: String
    var count: Int? = nil
    @Environment(WorkspaceStore.self) private var store

    private var isSelected: Bool {
        store.selection.sourceID == item.id && WorkspaceMailbox.display(store.selection.mailbox) == WorkspaceMailbox.display(box)
    }

    /// VoiceOver label for the row. A count (Pages row) is announced like
    /// the trunk rows do ("…, N pages") so the announced number matches the
    /// visual badge; no count → label only.
    private var accessibilityLabelText: String {
        let name = "\(item.title), \(WorkspaceMailbox.displayName(box))"
        guard let count, count > 0 else { return name }
        return "\(name), \(count) pages"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: WorkspaceMailbox.symbolName(box))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
                .accessibilityHidden(true)
            Text(WorkspaceMailbox.displayName(box))
                .font(.system(size: 12.5, weight: .regular))
                .lineLimit(1)
            if let count, count > 0 {
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(isSelected ? "selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                // #274: the checkout branch is known at add/load time —
                // surface it instead of hiding it in the Remote mailbox.
                if let branch = item.branch, !branch.isEmpty, item.isAvailable {
                    Label(branch, systemImage: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !item.isAvailable {
                    Text("Unreachable — Relocate / Remove")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            Spacer()
            // #274: git work in flight is visible at a glance.
            if item.isSyncing {
                ProgressView()
                    .controlSize(.small)
                    .help("Syncing…")
                    .accessibilityLabel("Syncing")
            }
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
        // #274: source headers are VoiceOver rotor landmarks.
        .accessibilityAddTraits(.isHeader)
    }
}
