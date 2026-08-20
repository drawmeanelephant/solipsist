import AppKit
import SwiftUI

/// Play surface for a folder-backed source (Local, or a GitHub working
/// copy — M15): mailbox contents plus, for Pages, a reading pane for the
/// selected letter. The surfaces are identical for both kinds; the GitHub
/// source resolves to its working copy and additionally offers the
/// Remote mailbox (branch, ahead/behind, Sync).
///
/// Reads `<source>/.boris/graph.json` when present; otherwise asks
/// `BorisEngine.buildIR` to produce it. Selection is written to
/// `WorkspaceStore` as `noun.kind == "page"` with `sourcePath` — the
/// drawer and companions only read it.
struct LocalPlay: PlaySurface {
    let source: any PlayFolderSource

    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow

    @State private var state: LoadState = .idle
    @State private var searchText = ""
    @State private var loadGeneration = 0
    /// Height of the floating glass toolbar band, measured from the window.
    /// See `ToolbarBandReader` for why this is not the SwiftUI safe area.
    @State private var toolbarBand: CGFloat = 0

    var body: some View {
        Group {
            switch WorkspaceMailbox.display(store.selection.mailbox) {
            case WorkspaceMailbox.pages:
                pagesMailbox
            case WorkspaceMailbox.outputs:
                OutputsPane(source: source)
            case WorkspaceMailbox.publish:
                PublishPane(source: source)
            case WorkspaceMailbox.plan:
                PlanPane(source: source)
            case WorkspaceMailbox.activity:
                ActivityPane()
            case WorkspaceMailbox.contentAudit:
                ContentAuditPane(source: source)
            case WorkspaceMailbox.remote:
                if let github = source as? GithubSource {
                    RemoteMailboxView(source: github)
                } else {
                    // Unreachable: the Remote row only exists for github
                    // sources. Honest fallback rather than a crash.
                    trunkMailbox
                }
            case WorkspaceMailbox.issues:
                if let github = source as? GithubSource {
                    IssuesMailboxView(source: github)
                } else {
                    // Unreachable: the Issues row only exists for github
                    // sources. Honest fallback rather than a crash.
                    trunkMailbox
                }
            case WorkspaceMailbox.pulls:
                if let github = source as? GithubSource {
                    PullRequestsMailboxView(source: github)
                } else {
                    // Unreachable: the Pull Requests row only exists for
                    // github sources. Honest fallback rather than a crash.
                    trunkMailbox
                }
            default:
                // Unknown mailbox is a trunk id (M13): Pages means all;
                // a trunk id means that folder and its descendants.
                trunkMailbox
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(source.title)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ProblemsPane(pages: loadedPages)
        }
        .background(ToolbarBandReader { toolbarBand = $0 })
        .environment(\.toolbarBand, toolbarBand)
        .task(id: source.id) {
            await load()
        }
    }

    /// The raw mailbox value when it is a trunk id (not one of the known
    /// M10 tokens and not nil). Trunk ids come from `graph.parent` only.
    private var trunkID: String? {
        guard
            let mailbox = store.selection.mailbox,
            !WorkspaceMailbox.isKnown(mailbox)
        else { return nil }
        return mailbox
    }

    /// The letter list for the current trunk folder, or the full list when
    /// the mailbox is Pages. Empty when the id is stale — never all pages.
    private var displayedPages: [PlayPage] {
        guard let trunkID else { return loadedPages }
        return LocalPlayGraph.pages(in: loadedPages, trunkID: trunkID)
    }

    private var loadedPages: [PlayPage] {
        if case .ready(let pages) = state {
            return pages
        }
        return []
    }

    private var selectedPlayPage: PlayPage? {
        guard
            let noun = store.selection.noun,
            noun.kind == "page",
            case .ready(let pages) = state
        else { return nil }
        return pages.first(where: { $0.id == noun.id })
    }

    @ViewBuilder
    private var pagesMailbox: some View {
        mailboxContent(pages: loadedPages, empty: .noPages)
    }

    /// Unknown mailbox = trunk id: the folder's letter list, or an honest
    /// empty state when the folder has none in the current graph.
    @ViewBuilder
    private var trunkMailbox: some View {
        mailboxContent(pages: displayedPages, empty: .emptyFolder)
    }

    private enum MailboxEmptyKind {
        /// The source's graph has no pages at all.
        case noPages
        /// The trunk folder has no pages in the current graph (or its id
        /// is stale — the graph no longer contains it).
        case emptyFolder
    }

    @ViewBuilder
    private func mailboxContent(pages: [PlayPage], empty: MailboxEmptyKind) -> some View {
        switch state {
        case .idle, .reading, .building:
            ProgressView(progressTitle)
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            unreachableContent
        case .failed(let message):
            failedContent(message)
        case .empty:
            emptyContent(empty)
        case .ready where pages.isEmpty:
            emptyContent(empty)
        case .ready:
            pagesSplit(pages)
        }
    }

    private var unreachableContent: some View {
        ContentUnavailableView {
            Label(source.title, systemImage: "folder")
                .accessibilityLabel("\(source.title), unreachable")
        } description: {
            Text("This folder is unreachable. Relocate it from File → Relocate Source… or Settings → Sources, or remove it.")
        } actions: {
            Button("Relocate…") {
                store.presentRelocatePanel(for: source.id)
            }
            Button("Remove", role: .destructive) {
                store.remove(source.id)
            }
        }
    }

    @ViewBuilder
    private func emptyContent(_ kind: MailboxEmptyKind) -> some View {
        switch kind {
        case .noPages:
            ContentUnavailableView {
                Label("No Pages", systemImage: "doc.text")
            } description: {
                Text("This source has no pages. Add Stunts/happy from Settings → Sources or File → Open… to see a working publication.")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No Pages")
            .accessibilityHint("Add Stunts/happy from Settings → Sources or File → Open… to see a working publication.")
        case .emptyFolder:
            ContentUnavailableView {
                Label("No Pages in This Folder", systemImage: "folder")
            } description: {
                Text("This folder has no pages in the current graph.")
            }
            .accessibilityLabel("No Pages in This Folder")
        }
    }

    private func failedContent(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Graph Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { reload() }
        }
    }

    @State private var topHeight: CGFloat = 200

    @ViewBuilder
    private func pagesSplit(_ pages: [PlayPage]) -> some View {
        GeometryReader { proxy in
            let totalHeight = proxy.size.height
            let availableHeight = max(totalHeight - 10, 100)
            let clampedTop = min(max(topHeight, 90), availableHeight - 120)

            VStack(spacing: 0) {
                pageList(pages)
                    .frame(height: clampedTop)

                ZStack {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)

                    Capsule()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 36, height: 4)
                }
                .frame(height: 9)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            topHeight = min(max(clampedTop + value.translation.height, 90), availableHeight - 120)
                        }
                )

                ReadingPane(
                    page: selectedPlayPage,
                    source: source,
                    loadGeneration: loadGeneration
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - List

    private func pageList(_ pages: [PlayPage]) -> some View {
        let filtered = LocalPlayGraph.filter(pages: pages, query: searchText)
        return Group {
            if filtered.isEmpty, !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(filtered, selection: selectedPageID) { page in
                    PageRow(page: page, findings: runtime.coordinator.checkFindings)
                        .tag(page.id)
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            selectPage(page)
                            openWindow(id: CompanionID.compose)
                        })
                        .contextMenu {
                            Button("Compose (Native)") {
                                selectPage(page)
                                openWindow(id: CompanionID.compose)
                            }
                            Button("Edit Page in Boris Editor") {
                                selectPage(page)
                                openWindow(id: CompanionID.editor)
                            }
                        }
                }
                .listStyle(.inset)
                .safeAreaPadding(.top, toolbarBand)
                .onKeyPress(.return) {
                    guard store.selection.canEditPage else { return .ignored }
                    openWindow(id: CompanionID.compose)
                    return .handled
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "Filter by title, id, tag, or status…"
        )
    }

    private var selectedPageID: Binding<String?> {
        Binding(
            get: {
                if store.selection.noun?.kind == "page" {
                    return store.selection.noun?.id
                }
                return nil
            },
            set: { newID in
                guard let newID else {
                    store.select(noun: nil)
                    return
                }
                if let page = loadedPages.first(where: { $0.id == newID }) {
                    selectPage(page)
                }
            }
        )
    }

    private func selectPage(_ page: PlayPage) {
        store.select(
            noun: WorkspaceNoun(
                kind: "page",
                id: page.id,
                title: page.title,
                sourcePath: page.sourcePath
            )
        )
    }

    private var progressTitle: String {
        switch state {
        case .building: return "Building IR…"
        default: return "Reading graph…"
        }
    }

    // MARK: - Load

    private func reload() {
        Task { await load() }
    }

    @MainActor
    private func load() async {
        guard source.isAvailable else {
            state = .unavailable
            return
        }
        state = .reading

        let root: URL
        do {
            root = try source.resolve().url
        } catch {
            state = .failed(String(describing: error))
            return
        }

        let graphURL = root
            .appendingPathComponent(".boris", isDirectory: true)
            .appendingPathComponent("graph.json")

        if FileManager.default.fileExists(atPath: graphURL.path) {
            do {
                apply(try decodeGraph(at: graphURL))
            } catch {
                state = .failed("Could not read graph.json: \(error.localizedDescription)")
            }
            return
        }

        guard let engine = runtime.engine else {
            state = .failed(runtime.engineError ?? "Engine not found.")
            return
        }

        state = .building
        let contentRoot: URL
        let outDir: URL
        do {
            contentRoot = try source.contentRoot()
            outDir = try source.artifactDirectory(named: ".boris")
        } catch {
            state = .failed(String(describing: error))
            return
        }

        runtime.coordinator.beginTreeWrite()
        defer { runtime.coordinator.endTreeWrite() }
        do {
            let build = try await engine.buildIR(contentRoot: contentRoot, outDir: outDir)
            guard !Task.isCancelled else { return }
            if let graph = build.graph, build.report.ok {
                guard ContractSchema.status(ofIR: graph.schemaVersion) == .supported else {
                    state = .failed(unknownSchemaMessage(graph.schemaVersion))
                    return
                }
                apply(graph)
                return
            }
            let count = build.report.diagnostics.count
            state = .failed(
                "IR build failed (exit \(build.exitCode)) — \(count) diagnostic\(count == 1 ? "" : "s")."
            )
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(String(describing: error))
        }
    }

    private func apply(_ graph: Graph) {
        // D8: never trust an unknown/newer shape as truth.
        guard ContractSchema.status(ofIR: graph.schemaVersion) == .supported else {
            state = .failed(unknownSchemaMessage(graph.schemaVersion))
            return
        }
        let pages = LocalPlayGraph.pages(from: graph)
        state = pages.isEmpty ? .empty : .ready(pages)
        // Push the decoded graph so the sidebar can show trunk folders
        // without Chrome re-parsing JSON (M13-1).
        store.updateGraph(graph, for: source.id)
        refreshNoun(against: pages)
    }

    /// Keep the page noun honest after a graph reload: rewrite title +
    /// `sourcePath` when the id still exists, otherwise drop the letter.
    private func refreshNoun(against pages: [PlayPage]) {
        if let noun = store.selection.noun, noun.kind == "page" {
            if let page = pages.first(where: { $0.id == noun.id }) {
                store.select(
                    noun: WorkspaceNoun(
                        kind: "page",
                        id: page.id,
                        title: page.title,
                        sourcePath: page.sourcePath
                    )
                )
                return
            } else {
                store.select(noun: nil)
            }
        }
        if store.selection.noun == nil, let first = pages.first {
            selectPage(first)
        }
    }

    private func unknownSchemaMessage(_ version: String) -> String {
        "graph.json schemaVersion \"\(version)\" is not a known IR version "
            + "(supported: \(ContractSchema.supportedIR.sorted().joined(separator: ", "))). "
            + "Refusing to render an unknown shape."
    }

    private func decodeGraph(at url: URL) throws -> Graph {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Graph.self, from: data)
    }

    private enum LoadState {
        case idle
        case reading
        case building
        case unavailable
        case empty
        case ready([PlayPage])
        case failed(String)
    }
}

private struct PageRow: View {
    let page: PlayPage
    let findings: [AnalysisFinding]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if page.depth > 0 {
                Color.clear.frame(width: CGFloat(page.depth) * 16)
            }
            Image(systemName: page.role == .trunk ? "doc.text" : "doc")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                    .lineLimit(1)
                Text(page.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            ForEach(pageFindings, id: \.code) { finding in
                FindingBadge(finding: finding)
            }

            if !page.status.isEmpty {
                Text(page.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help("\(page.title) · \(page.status) · \(page.id)")
    }

    private var pageFindings: [AnalysisFinding] {
        findings.filter { $0.type == "page" && $0.value == page.id }
    }
}

private struct FindingBadge: View {
    let finding: AnalysisFinding

    var body: some View {
        Text(badgeLabel)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
            .help("\(finding.code): \(finding.value) (count \(finding.count))")
    }

    private var badgeLabel: String {
        switch finding.code {
        case "WUNREFERENCED":
            return "unreferenced"
        default:
            return finding.code
        }
    }
}
