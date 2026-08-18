import AppKit
import SwiftUI

/// Activity / problems under the graph list. Reads the coordinator only.
struct ProblemsPane: View {
    var pages: [PlayPage] = []

    @Environment(AppRuntime.self) private var runtime
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if runtime.coordinator.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(runtime.coordinator.summary)
                    .lineLimit(1)
                Spacer()
                if let exit = runtime.coordinator.exitCode {
                    Text("exit \(exit)")
                        .foregroundStyle(exit == 0 ? Color.secondary : Color.red)
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            if !runtime.coordinator.problems.isEmpty {
                Divider()
                List(runtime.coordinator.problems, selection: selectedProblem) { item in
                    ProblemRow(item: item)
                        .tag(item.id)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private var selectedProblem: Binding<String?> {
        Binding(
            get: { nil },
            set: { id in
                guard
                    let id,
                    let item = runtime.coordinator.problems.first(where: { $0.id == id }),
                    let path = item.path
                else { return }
                let localSource: LocalSource?
                if case .local(let src) = store.selectedSource {
                    localSource = src
                } else {
                    localSource = nil
                }

                var graph: Graph?
                if let localSource, let root = try? localSource.resolve().url {
                    let graphURL = root
                        .appendingPathComponent(".boris", isDirectory: true)
                        .appendingPathComponent("graph.json")
                    if let data = try? Data(contentsOf: graphURL) {
                        graph = try? JSONDecoder().decode(Graph.self, from: data)
                    }
                }

                guard let resolution = ProblemResolver.resolve(path: path, source: localSource, graph: graph) else {
                    return
                }

                switch resolution {
                case .page(let pageID, let pageTitle):
                    store.select(mailbox: WorkspaceMailbox.pages)
                    if let page = pages.first(where: { $0.id == pageID })
                        ?? LocalPlayGraph.resolvePage(forSourcePath: path, in: pages)
                    {
                        store.select(
                            noun: WorkspaceNoun(
                                kind: "page",
                                id: page.id,
                                title: page.title,
                                sourcePath: page.sourcePath
                            )
                        )
                    } else {
                        store.select(
                            noun: WorkspaceNoun(kind: "page", id: pageID, title: pageTitle)
                        )
                    }
                case .revealFile(let url):
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        )
    }
}

private struct ProblemRow: View {
    let item: ProblemItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.severity)
                .font(.caption2)
                .foregroundStyle(item.severity == "error" ? Color.red : Color.secondary)
                .frame(width: 44, alignment: .leading)
            Text(item.code)
                .font(.caption.monospaced())
            Text(item.message)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let path = item.path {
                Text(location(path: path, line: item.line, column: item.column))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func location(path: String, line: Int?, column: Int?) -> String {
        var text = path
        if let line {
            text += ":\(line)"
            if let column {
                text += ":\(column)"
            }
        }
        return text
    }
}
