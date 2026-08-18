import SwiftUI

/// Play surface for a local folder: mailbox contents plus, for Pages, a
/// reading pane for the selected letter.
///
/// Reads `<source>/.boris/graph.json` when present; otherwise asks
/// `BorisEngine.buildIR` to produce it. Selection is written to
/// `WorkspaceStore` as `noun.kind == "page"` with `sourcePath` — the
/// drawer and companions only read it.
struct LocalPlay: PlaySurface {
    let source: LocalSource

    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow

    @State private var state: LoadState = .idle
    @State private var searchText = ""
    @State private var loadGeneration = 0

    var body: some View {
        Group {
            switch WorkspaceMailbox.display(store.selection.mailbox) {
            case WorkspaceMailbox.outputs:
                OutputsPane(source: source)
            case WorkspaceMailbox.publish:
                PublishPane(source: source)
            case WorkspaceMailbox.plan:
                PlanPane(source: source)
            case WorkspaceMailbox.activity:
                ActivityPane()
            default:
                pagesMailbox
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(source.title)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                ProblemsPane(pages: loadedPages)
                    .frame(minHeight: 88, idealHeight: 148, maxHeight: 220)
            }
        }
        .task(id: source.id) {
            await load()
        }
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
        switch state {
        case .idle, .reading, .building:
            ProgressView(progressTitle)
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            ContentUnavailableView {
                Label(source.title, systemImage: "folder")
            } description: {
                Text("This folder is unreachable. Relocate it or remove it from the sidebar.")
            } actions: {
                Button("Relocate…") {
                    store.presentRelocatePanel(for: source.id)
                }
                Button("Remove", role: .destructive) {
                    store.remove(source.id)
                }
            }
        case .empty:
            ContentUnavailableView {
                Label("No Pages", systemImage: "doc.text")
            } description: {
                Text("The graph for this folder has no pages. Open a folder with boris.json (e.g. Stunts/happy) to view pages.")
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Graph Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { reload() }
            }
        case .ready(let pages):
            VSplitView {
                pageList(pages)
                    .frame(minHeight: 120)
                ReadingPane(
                    page: selectedPlayPage,
                    source: source,
                    loadGeneration: loadGeneration
                )
                .frame(minHeight: 160)
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
                            openWindow(id: CompanionID.editor)
                        })
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .onKeyPress(.return) {
                    guard store.selection.canEditPage else { return .ignored }
                    openWindow(id: CompanionID.editor)
                    return .handled
                }
            }
        }
        .searchable(text: $searchText, prompt: "Filter by title, id, tag, or status…")
    }

    private var selectedPageID: Binding<String?> {
        Binding(
            get: {
                let noun = store.selection.noun
                return noun?.kind == "page" ? noun?.id : nil
            },
            set: { newID in
                let currentID = store.selection.noun?.kind == "page" ? store.selection.noun?.id : nil
                if newID != nil, newID == currentID {
                    loadGeneration += 1
                }
                guard
                    let newID,
                    case .ready(let pages) = state,
                    let page = pages.first(where: { $0.id == newID })
                else {
                    store.select(noun: nil)
                    return
                }
                selectPage(page)
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
        refreshNoun(against: pages)
    }

    /// Keep the page noun honest after a graph reload: rewrite title +
    /// `sourcePath` when the id still exists, otherwise drop the letter.
    private func refreshNoun(against pages: [PlayPage]) {
        guard store.selection.noun?.kind == "page", let id = store.selection.noun?.id else {
            return
        }
        if let page = pages.first(where: { $0.id == id }) {
            store.select(
                noun: WorkspaceNoun(
                    kind: "page",
                    id: page.id,
                    title: page.title,
                    sourcePath: page.sourcePath
                )
            )
        } else {
            store.select(noun: nil)
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
