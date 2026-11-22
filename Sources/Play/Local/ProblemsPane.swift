import AppKit
import SwiftUI

/// Activity / problems under the graph list. Reads the coordinator only.
struct ProblemsPane: View {
    var pages: [PlayPage] = []

    @Environment(AppRuntime.self) private var runtime
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var selectedProblemID: String?

    var body: some View {
        let hasProblems = !runtime.coordinator.problems.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            Divider()
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
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            if hasProblems {
                Divider()
                List(runtime.coordinator.problems, selection: $selectedProblemID) { item in
                    ProblemRow(item: item, pages: pages)
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedProblemID = item.id
                            selectProblem(item)
                        }
                        .contextMenu { contextMenu(for: item) }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.severity) \(item.code) \(item.message)")
                        .accessibilityValue(item.path ?? "")
                        .accessibilityAddTraits(.isButton)
                }
                .listStyle(.inset)
                .frame(minHeight: 80, idealHeight: 140, maxHeight: 200)
                .onKeyPress(keys: [.return]) { press in
                    guard let item = currentSelectedProblem else { return .ignored }
                    if press.modifiers.contains(.command) {
                        if let url = revealURL(for: item) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                            return .handled
                        }
                        return .ignored
                    }
                    openInCompose(item)
                    return .handled
                }
                .onKeyPress(.escape) {
                    if selectedProblemID != nil {
                        selectedProblemID = nil
                        return .handled
                    }
                    return .ignored
                }
            }
        }
        .background(.bar)
    }

    private var currentSelectedProblem: ProblemItem? {
        guard let selectedProblemID else { return nil }
        return runtime.coordinator.problems.first(where: { $0.id == selectedProblemID })
    }

    private var activeFolderSource: (any PlayFolderSource)? {
        switch store.selectedSource {
        case .local(let src): return src
        case .github(let src): return src
        case nil: return nil
        }
    }

    private func selectProblem(_ item: ProblemItem) {
        guard let path = item.path else {
            // No location — still surface as a problem, but nothing to select.
            return
        }
        let folderSource = activeFolderSource
        let graph = store.selection.sourceID.flatMap { store.cachedGraph(for: $0) }

        if let resolution = ProblemResolver.resolve(path: path, source: folderSource, graph: graph) {
            switch resolution {
            case .page(let pageID, let pageTitle):
                openPageInCompose(pageID: pageID, pageTitle: pageTitle, path: path, item: item, alwaysOpenCompose: false)
                return
            case .revealFile(let url):
                if let editablePath = ProblemResolver.editableSourcePath(forPath: path, source: folderSource) {
                    let title = URL(fileURLWithPath: editablePath).lastPathComponent
                    openPageInCompose(
                        pageID: editablePath,
                        pageTitle: title,
                        path: editablePath,
                        item: item,
                        alwaysOpenCompose: true
                    )
                    return
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }
        }
    }

    private func openPageInCompose(
        pageID: String,
        pageTitle: String,
        path: String,
        item: ProblemItem,
        alwaysOpenCompose: Bool
    ) {
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
                noun: WorkspaceNoun(kind: "page", id: pageID, title: pageTitle, sourcePath: path)
            )
        }
        if let line = item.line {
            runtime.pendingComposeJump = AppRuntime.ComposeJumpRequest(
                pageID: pageID,
                line: line,
                column: item.column
            )
            openWindow(id: CompanionID.compose)
        } else if alwaysOpenCompose {
            openWindow(id: CompanionID.compose)
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ProblemItem) -> some View {
        Button("Copy") {
            copy(item, asMarkdown: false)
        }
        Button("Copy as Markdown") {
            copy(item, asMarkdown: true)
        }
        Divider()
        if let path = item.path, let line = item.line {
            Button("Open in Compose at line \(line)") {
                openInCompose(item)
            }
        } else if item.path != nil {
            Button("Open in Compose") {
                openInCompose(item)
            }
        }
        if let url = revealURL(for: item) {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } else if item.path != nil {
            Button("Reveal File") {
                if let url = revealURL(for: item) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .disabled(revealURL(for: item) == nil)
        }
    }

    private func revealURL(for item: ProblemItem) -> URL? {
        guard let path = item.path else { return nil }
        return ProblemResolver.resolveFileURL(path: path, source: activeFolderSource)
    }

    private func openInCompose(_ item: ProblemItem) {
        guard let path = item.path else { return }
        let folderSource = activeFolderSource
        let graph = store.selection.sourceID.flatMap { store.cachedGraph(for: $0) }
        guard let resolution = ProblemResolver.resolve(path: path, source: folderSource, graph: graph) else {
            if let url = revealURL(for: item) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            return
        }
        switch resolution {
        case .page(let pageID, let pageTitle):
            openPageInCompose(pageID: pageID, pageTitle: pageTitle, path: path, item: item, alwaysOpenCompose: true)
        case .revealFile(let url):
            if let editablePath = ProblemResolver.editableSourcePath(forPath: path, source: folderSource) {
                let title = URL(fileURLWithPath: editablePath).lastPathComponent
                openPageInCompose(
                    pageID: editablePath,
                    pageTitle: title,
                    path: editablePath,
                    item: item,
                    alwaysOpenCompose: true
                )
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private func copy(_ item: ProblemItem, asMarkdown: Bool) {
        let text: String
        if asMarkdown {
            var md = "- **\(item.code)** (\(item.severity)) \(item.message)"
            if let path = item.path {
                md += " — `\(location(path: path, line: item.line, column: item.column))`"
            }
            text = md
        } else {
            var plain = "\(item.severity) \(item.code): \(item.message)"
            if let path = item.path {
                plain += " — \(location(path: path, line: item.line, column: item.column))"
            }
            text = plain
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func location(path: String, line: Int?, column: Int?) -> String {
        var text = path
        if let line {
            text += ":\(line)"
            if let column { text += ":\(column)" }
        }
        return text
    }
}

private struct ProblemRow: View {
    let item: ProblemItem
    var pages: [PlayPage] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(iconColor)
                .frame(width: 12)
                .help(item.severity)
                .accessibilityHidden(true)

            Text(item.severity)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(severityColor.opacity(0.18), in: Capsule())
                .foregroundStyle(severityColor)
                .help(item.severity)

            Text(item.code)
                .font(.caption2.monospaced().weight(.medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .help(item.code)

            Text(item.message)
                .lineLimit(2)
                .help(item.message)

            Spacer(minLength: 8)

            if let path = item.path {
                Text(location(path: path, line: item.line, column: item.column))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(location(path: path, line: item.line, column: item.column))
            }
        }
        .padding(.vertical, 2)
    }

    private var severityColor: Color {
        item.severity == "error" ? .red : .secondary
    }

    private var iconName: String {
        item.severity == "error" ? "xmark.octagon.fill" : "info.circle.fill"
    }

    private var iconColor: Color {
        item.severity == "error" ? .red : .secondary
    }

    private func location(path: String, line: Int?, column: Int?) -> String {
        if let line, let column {
            return "\(path):\(line):\(column)"
        } else if let line {
            return "\(path):\(line)"
        }
        return path
    }
}
