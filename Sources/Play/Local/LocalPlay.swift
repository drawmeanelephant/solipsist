import SwiftUI

/// Play surface for a local folder: the publication as a Mail-style list.
///
/// Reads `<source>/.boris/graph.json` when present; otherwise asks
/// `BorisEngine.buildIR` to produce it. Selection is written to
/// `WorkspaceStore` as `noun.kind == "page"` — the drawer only reads it.
struct LocalPlay: PlaySurface {
    let source: LocalSource

    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime
    @State private var state: LoadState = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .reading, .building:
                ProgressView(progressTitle)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                ContentUnavailableView {
                    Label(source.title, systemImage: "folder")
                } description: {
                    Text("This folder is no longer reachable. Remove it from the sidebar or reopen it.")
                }
            case .empty:
                ContentUnavailableView {
                    Label("No Pages", systemImage: "doc.text")
                } description: {
                    Text("The graph for this folder has no pages.")
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
                pageList(pages)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(source.title)
        .task(id: source.id) {
            await load()
        }
    }

    // MARK: - List

    private func pageList(_ pages: [PlayPage]) -> some View {
        List(pages, selection: selectedPageID) { page in
            PageRow(page: page)
                .tag(page.id)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var selectedPageID: Binding<String?> {
        Binding(
            get: {
                let noun = store.selection.noun
                return noun?.kind == "page" ? noun?.id : nil
            },
            set: { newID in
                guard
                    let newID,
                    case .ready(let pages) = state,
                    let page = pages.first(where: { $0.id == newID })
                else {
                    store.select(noun: nil)
                    return
                }
                store.select(
                    noun: WorkspaceNoun(kind: "page", id: page.id, title: page.title)
                )
            }
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
        let contentRoot = Self.contentRoot(for: root)
        let outDir = root.appendingPathComponent(".boris", isDirectory: true)

        do {
            let build = try await engine.buildIR(contentRoot: contentRoot, outDir: outDir)
            guard !Task.isCancelled else { return }
            if let graph = build.graph, build.report.ok {
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
        let pages = LocalPlayGraph.pages(from: graph)
        state = pages.isEmpty ? .empty : .ready(pages)
    }

    private func decodeGraph(at url: URL) throws -> Graph {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Graph.self, from: data)
    }

    /// A folder with both `content/` and `boris.json` is a project root.
    /// `--input content`, cwd = source, `--out .boris`.
    private static func contentRoot(for sourceRoot: URL) -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let content = sourceRoot.appendingPathComponent("content", isDirectory: true)
        let profile = sourceRoot.appendingPathComponent("boris.json")
        let hasContent = fm.fileExists(atPath: content.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
        let hasProfile = fm.fileExists(atPath: profile.path)
        if hasContent && hasProfile {
            return content
        }
        return sourceRoot
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
            Text(page.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help("\(page.title) · \(page.status) · \(page.id)")
    }
}
