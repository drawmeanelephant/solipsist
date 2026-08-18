import AppKit
import SwiftUI

/// The letter under the Pages list. Loads the selected page from the shared
/// preview watch when that session is bound to this source; otherwise a
/// contract-backed summary. Never `file://`, never a Markdown renderer.
struct ReadingPane: View {
    let page: PlayPage?
    let source: LocalSource
    let loadGeneration: Int

    @Environment(AppRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow

    @State private var model = ReadingWebModel()
    @State private var relations: [CompletionRelation] = []

    var body: some View {
        Group {
            if let page {
                letter(for: page)
            } else {
                ContentUnavailableView {
                    Label("No Page Selected", systemImage: "envelope.open")
                } description: {
                    Text("Select a page to read it.")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No Page Selected")
                .accessibilityHint("Select a page from the list to read it.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: letterIdentity) {
            await refreshLetter()
        }
        .task(id: completionIdentity) {
            relations = Self.loadRelations(source: source, pageID: page?.id)
        }
    }

    // MARK: - Letter

    private func letter(for page: PlayPage) -> some View {
        VStack(spacing: 0) {
            header(for: page)
            Divider()
            bodyStack(for: page)
        }
    }

    private func header(for page: PlayPage) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: page.role == .trunk ? "doc.text" : "doc")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(headerCaption(for: page))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            if isShowingServedPage {
                servedBadge
            }

            Button {
                openWindow(id: CompanionID.preview)
            } label: {
                Label("Preview", systemImage: "safari")
            }
            .help("Open the full-site Preview companion")

            Button {
                openWindow(id: CompanionID.editor)
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
            .help("Open the hosted editor for this page")

            Button {
                openWindow(id: CompanionID.compose)
            } label: {
                Label("Compose", systemImage: "pencil")
            }
            .help("Open the native Compose editor for this page")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func bodyStack(for page: PlayPage) -> some View {
        ZStack {
            switch letterBody {
            case .starting:
                ProgressView("Starting preview…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading:
                ProgressView("Loading page…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .served:
                ReadingWebView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .summary(let caption):
                summary(for: page, caption: caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summary(for page: PlayPage, caption: String?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let caption {
                    Label(caption, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") {
                        retryServedPage(for: page)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                memoRow("ID", page.id)
                memoRow("Status", display(page.status))
                memoRow("Role", page.role == .trunk ? "Trunk" : "Satellite")
                memoRow("Path", display(page.sourcePath))

                if !page.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        FlowTags(tags: page.tags)
                    }
                }

                if !relations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Relations")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Array(relations.enumerated()), id: \.offset) { _, relation in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(relation.kind)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 72, alignment: .leading)
                                Text(relation.target)
                                    .textSelection(.enabled)
                            }
                            .font(.callout)
                        }
                    }
                }

                if caption == nil, !isBoundToThisSource || !isServing {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "safari")
                            .foregroundStyle(.tertiary)
                        Text("Preview is not running. Open Preview to read the served page here.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func memoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private var servedBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
            Text("Served")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .help("This page is loaded from the running preview watch.")
        .padding(.trailing, 4)
    }

    // MARK: - Watch / load

    private var session: PreviewSession { runtime.previewSession }

    private var isBoundToThisSource: Bool {
        guard let root = try? source.contentRoot() else { return false }
        return session.isBound(to: root)
    }

    private var isServing: Bool {
        if case .serving = session.phase { return true }
        return false
    }

    private var isShowingServedPage: Bool {
        if case .served = letterBody { return true }
        return false
    }

    private enum LetterBody: Equatable {
        case starting
        case loading
        case served
        case summary(caption: String?)
    }

    private var letterBody: LetterBody {
        guard page != nil else { return .summary(caption: nil) }
        if isBoundToThisSource {
            switch session.phase {
            case .starting:
                return .starting
            case .serving:
                switch model.outcome {
                case .idle, .loading:
                    return .loading
                case .loaded:
                    return .served
                case .unavailable(let caption), .failed(let caption):
                    return .summary(caption: caption)
                }
            case .idle, .failed:
                return .summary(caption: nil)
            }
        }
        return .summary(caption: nil)
    }

    private var letterIdentity: String {
        let phaseKey: String
        switch session.phase {
        case .idle:
            phaseKey = "idle"
        case .starting:
            phaseKey = "starting"
        case .serving(let url):
            phaseKey = "serving:\(url.absoluteString)"
        case .failed:
            phaseKey = "failed"
        }
        return "\(loadGeneration)|\(page?.id ?? "")|\(phaseKey)|\(isBoundToThisSource)"
    }

    private var completionIdentity: String {
        "\(source.id.raw.uuidString)|\(page?.id ?? "")"
    }

    @MainActor
    private func refreshLetter() async {
        guard let page else {
            model.reset()
            return
        }
        guard isBoundToThisSource else {
            model.reset()
            return
        }
        switch session.phase {
        case .serving(let helper):
            guard let url = PreviewURL.pageURL(helper: helper, pageID: page.id) else {
                model.fail("Could not derive a served URL for this page.")
                return
            }
            model.load(url: url)
        case .starting, .idle, .failed:
            model.reset()
        }
    }

    private func retryServedPage(for page: PlayPage) {
        guard
            isBoundToThisSource,
            case .serving(let helper) = session.phase,
            let url = PreviewURL.pageURL(helper: helper, pageID: page.id)
        else { return }
        model.retry(url: url)
    }

    private func headerCaption(for page: PlayPage) -> String {
        var parts: [String] = []
        let path = page.sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty { parts.append(path) }
        if !page.status.isEmpty { parts.append(page.status) }
        parts.append(page.role == .trunk ? "Trunk" : "Satellite")
        return parts.joined(separator: "  ·  ")
    }

    private func display(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    /// Decode `.boris/completion.json` the same way Play reads `graph.json`.
    /// Failure omits relations (D8). Does not import Inspector.
    private static func loadRelations(source: LocalSource, pageID: String?) -> [CompletionRelation] {
        guard
            let pageID,
            source.isAvailable,
            let root = try? source.resolve().url
        else { return [] }
        let url = root
            .appendingPathComponent(".boris", isDirectory: true)
            .appendingPathComponent("completion.json")
        guard
            FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url),
            let completion = try? JSONDecoder().decode(Completion.self, from: data),
            let entity = completion.entities.first(where: { $0.id == pageID })
        else { return [] }
        return entity.relations
    }
}

/// Compact wrapping chips for graph tags.
private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 52), spacing: 6, alignment: .leading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}
