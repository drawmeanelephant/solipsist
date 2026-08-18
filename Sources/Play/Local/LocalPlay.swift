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
    /// Height of the floating glass toolbar band, measured from the window.
    /// See `ToolbarBandReader` for why this is not the SwiftUI safe area.
    @State private var toolbarBand: CGFloat = 0

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
            ProblemsPane(pages: loadedPages)
        }
        .background(ToolbarBandReader { toolbarBand = $0 })
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
        case .empty:
            ContentUnavailableView {
                Label("No Pages", systemImage: "doc.text")
            } description: {
                Text("This source has no pages. Add Stunts/happy from Settings → Sources or File → Open… to see a working publication.")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No Pages")
            .accessibilityHint("Add Stunts/happy from Settings → Sources or File → Open… to see a working publication.")
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
                // Fixed height — not min/ideal/max: the VSplitView ignores a
                // later ideal-height change from the async band measurement
                // and clips the last row (#130). The list is a short stack
                // only as tall as its rows; the splitter still resizes the
                // reading pane below.
                pageList(pages)
                    .frame(height: listIdealHeight(pages.count))
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
        let selectedID = store.selection.noun?.kind == "page" ? store.selection.noun?.id : nil
        return Group {
            if filtered.isEmpty, !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                // ScrollView, not List: macOS List paints empty zebra slots
                // for leftover height. Mail's message list is only as tall
                // as its rows.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { page in
                            PageRow(page: page, findings: runtime.coordinator.checkFindings)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    if page.id == selectedID {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.18))
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { selectPage(page) }
                                .simultaneousGesture(TapGesture(count: 2).onEnded {
                                    selectPage(page)
                                    openWindow(id: CompanionID.compose)
                                })
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .onKeyPress(.return) {
                    guard store.selection.canEditPage else { return .ignored }
                    openWindow(id: CompanionID.compose)
                    return .handled
                }
                // #130: the main window is `.fullSizeContentView` glass, so
                // the floating toolbar is not in the SwiftUI safe area and
                // the first row would paint underneath the title band. Inset
                // the scroll content by the measured band — the system's own
                // number, not an invented spacer.
                .contentMargins(.top, toolbarBand, for: .scrollContent)
            }
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "Filter by title, id, tag, or status…"
        )
    }

    private func listIdealHeight(_ count: Int) -> CGFloat {
        let rows = CGFloat(min(max(count, 1), 8))
        return toolbarBand + 12 + rows * 44
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

/// Measures the window's floating toolbar band height for #130.
///
/// The main window uses `.fullSizeContentView` + `.glassEffect()`, so the
/// toolbar floats *over* the content and is deliberately absent from the
/// SwiftUI safe area (a `GeometryReader` here reports top == 0). AppKit still
/// reserves the band in `contentLayoutRect`; `frame.height - maxY` is the
/// exact band, which the Pages list uses as its scroll-content inset instead
/// of a hardcoded spacer.
private struct ToolbarBandReader: NSViewRepresentable {
    var onBand: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { measure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { measure(nsView) }
    }

    private func measure(_ view: NSView) {
        guard let window = view.window else { return }
        onBand(max(0, window.frame.height - window.contentLayoutRect.maxY))
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
