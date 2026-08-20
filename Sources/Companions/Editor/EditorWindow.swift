import AppKit
import Observation
import SwiftUI
import WebKit

/// Companion host for `boris-editor` (Svelte). Chassis registers the window
/// and leaves it closed; the editor opens against the selected page.
///
/// The window starts an `EditorSession` for the selected source's project
/// root, then loads the tokenized `BORIS_EDITOR_URL=` into the web view
/// with `open=` set from the page `sourcePath` (A15 / boris#649; ignored
/// by today's shell). The header names the selected page and its
/// `sourcePath`. Manual URL paste and "Open in Browser" stay as the
/// loopback fallback.
struct EditorWindow: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime

    @State private var model = EditorWebModel()
    @State private var urlText = ""
    @State private var session = EditorSession()

    var body: some View {
        Group {
            if let source = store.selectedSource {
                VStack(spacing: 0) {
                    header(for: source)
                    Divider()
                    toolbar
                    Divider()
                    if model.currentURL != nil {
                        EditorWebView(model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        idleState(for: source)
                    }
                }
                .task(id: source.id) {
                    startEditor(for: source)
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle("Editor")
        .onChange(of: session.editorURL) { _, newURL in
            if let newURL {
                let targeted = EditorURL.opening(newURL, sourcePath: pageSourcePath)
                urlText = EditorURL.maskedDisplayString(for: targeted)
                model.load(url: targeted)
            }
        }
        .onDisappear {
            session.stop()
        }
    }

    private func startEditor(for source: SourceItem) {
        let folder: (any PlayFolderSource)?
        switch source {
        case .local(let local): folder = local
        case .github(let github): folder = github
        }
        guard let folder,
              let projectRoot = try? folder.workspaceRoot(),
              let contentRoot = try? folder.contentRoot()
        else {
            session.fail("Could not resolve project folder for '\(source.title)'")
            return
        }
        session.start(
            contentRoot: contentRoot,
            projectRoot: projectRoot,
            engine: runtime.engine
        )
    }

    /// Single entry point for pointing the web view at an editor URL.
    func loadEditor(url: URL) {
        model.load(url: url)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Editor", systemImage: "square.and.pencil")
        } description: {
            Text("Select a page in the main window, then choose File → Edit Page (⌘⇧E) to open the editor.")
        }
    }

    private func idleState(for source: SourceItem) -> some View {
        ContentUnavailableView {
            Label("Editor Host Not Running", systemImage: "square.and.pencil")
        } description: {
            Text(
                session.statusText.isEmpty
                    ? "The Boris editor connects when the host process is running. "
                    + "File → Edit Page opens the editor; paste a BORIS_EDITOR_URL= line above to connect manually."
                    : session.statusText
            )
        } actions: {
            Button("Restart Host") {
                session.restart()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!session.canRestart)

            Button("Open in Browser") {
                if let url = session.editorURL ?? model.currentURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(session.editorURL == nil && model.currentURL == nil)
        }
    }

    private func header(for source: SourceItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle(for: source))
                    .font(.headline)
                    .lineLimit(1)
                if let path = headerSubtitle(for: source) {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .glassEffect()
    }

    /// Mail-compose chrome: when the editor was opened from a page, name that
    /// page; otherwise fall back to the source itself.
    private func headerTitle(for source: SourceItem) -> String {
        if let noun = store.selection.noun, noun.kind == "page", !noun.title.isEmpty {
            return noun.title
        }
        return source.title
    }

    private func headerSubtitle(for source: SourceItem) -> String? {
        if let path = pageSourcePath {
            return path
        }
        return source.detailLine
    }

    /// Graph `sourcePath` when the editor was opened from a page.
    private var pageSourcePath: String? {
        guard let noun = store.selection.noun, noun.kind == "page",
              let path = noun.sourcePath, !path.isEmpty
        else { return nil }
        return path
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                EditorNavButtons(model: model)

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                EditorPhaseIndicator(phase: session.phase, isFailure: session.isFailure)

                Spacer()

                Button {
                    session.restart()
                } label: {
                    Label("Restart Host", systemImage: "arrow.counterclockwise")
                }
                .help("Restart boris-editor")
                .disabled(!session.canRestart)

                Button {
                    model.openInBrowser()
                } label: {
                    Image(systemName: "safari")
                }
                .help("Open in Browser")
                .disabled(!model.canOpenInBrowser)
            }

            HStack(spacing: 8) {
                TextField("BORIS_EDITOR_URL=http://127.0.0.1:49152/#token=…", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)

                Button("Connect", action: submit)
            }

            if let rejection = model.rejection {
                Text(rejection)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
    }

    private func submit() {
        if urlText.contains("••••"), let current = session.editorURL ?? model.currentURL {
            let targeted = EditorURL.opening(current, sourcePath: pageSourcePath)
            model.load(url: targeted)
            return
        }
        do {
            let url = try EditorURL.parse(urlText)
            model.load(url: url)
            urlText = EditorURL.maskedDisplayString(for: url)
        } catch let err as EditorURL.ParseError {
            model.reject(err.localizedDescription)
        } catch {
            model.reject(error.localizedDescription)
        }
    }
}

private struct EditorNavButtons: View {
    let model: EditorWebModel

    var body: some View {
        HStack(spacing: 2) {
            Button {
                model.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Back")
            .disabled(!model.canGoBack)

            Button {
                model.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Forward")
            .disabled(!model.canGoForward)

            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")
            .disabled(!model.canReload)
        }
        .buttonStyle(.borderless)
    }
}

private struct EditorPhaseIndicator: View {
    let phase: EditorSession.Phase
    let isFailure: Bool

    var body: some View {
        HStack(spacing: 5) {
            phaseIcon
            Text(phaseLabel)
                .font(.caption)
                .foregroundStyle(isFailure ? Color.red : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch phase {
        case .idle:
            Image(systemName: "circle.dotted")
        case .starting:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .idle:
            return "Not connected"
        case .starting:
            return "Starting boris-editor…"
        case .connected(let url):
            return "Connected · \(url.host ?? "loopback")"
        case .failed(let message):
            return message
        }
    }
}
