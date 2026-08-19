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
                urlText = targeted.absoluteString
                model.load(url: targeted)
            }
        }
        .onDisappear {
            session.stop()
        }
    }

    private func startEditor(for source: SourceItem) {
        switch source {
        case .local(let local):
            guard
                let projectRoot = try? local.workspaceRoot(),
                let contentRoot = try? local.contentRoot()
            else {
                session.fail("Could not resolve project folder for '\(source.title)'")
                return
            }
            session.start(
                contentRoot: contentRoot,
                projectRoot: projectRoot,
                engine: runtime.engine
            )
        case .github(let github):
            session.fail("The editor for \(github.owner)/\(github.repository) lands with the working-copy slice.")
        }
    }

    /// Single entry point for pointing the web view at an editor URL.
    func loadEditor(url: URL) {
        model.load(url: url)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Editor", systemImage: "square.and.pencil")
        } description: {
            Text("Select a source in the main window, then open the editor.")
        }
    }

    private func idleState(for source: SourceItem) -> some View {
        ContentUnavailableView {
            Label("Editor Host Not Running", systemImage: "square.and.pencil")
        } description: {
            Text(
                session.statusText.isEmpty
                    ? "The Boris editor will connect when the host process is running. Paste a BORIS_EDITOR_URL= line above to connect manually."
                    : session.statusText
            )
        } actions: {
            Button("Open in Browser") {
                if let url = session.editorURL ?? model.currentURL {
                    NSWorkspace.shared.open(url)
                }
            }
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
                navButtons

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                phaseIndicator

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

    private var navButtons: some View {
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

    private var phaseIndicator: some View {
        HStack(spacing: 5) {
            phaseIcon
            Text(phaseLabel)
                .font(.caption)
                .foregroundStyle(phaseColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch session.phase {
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
        switch session.phase {
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

    private var phaseColor: Color {
        session.isFailure ? .red : .secondary
    }

    private func submit() {
        do {
            let url = try EditorURL.parse(urlText)
            model.load(url: url)
        } catch let err as EditorURL.ParseError {
            model.reject(err.localizedDescription)
        } catch {
            model.reject(error.localizedDescription)
        }
    }
}

/// Owns the `WKWebView` and navigation state for the Editor companion.
@MainActor
@Observable
final class EditorWebModel: NSObject {
    let webView: WKWebView

    private(set) var currentURL: URL?
    private(set) var rejection: String?
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    @ObservationIgnored
    private var observations: [NSKeyValueObservation] = []

    override init() {
        webView = WKWebView()
        super.init()
        observeNavigation()
    }

    var canReload: Bool {
        currentURL != nil || webView.url != nil
    }

    var canOpenInBrowser: Bool {
        guard let url = currentURL else { return false }
        return Self.isLoopback(url)
    }

    func load(url: URL) {
        do {
            let parsed = try EditorURL.parse(url.absoluteString)
            rejection = nil
            currentURL = parsed
            webView.load(URLRequest(url: parsed))
        } catch {
            rejection = error.localizedDescription
        }
    }

    func reject(_ message: String) {
        rejection = message
    }

    func reload() {
        if webView.url != nil {
            webView.reload()
        } else if let url = currentURL {
            webView.load(URLRequest(url: url))
        }
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    func openInBrowser() {
        guard let url = currentURL, Self.isLoopback(url) else { return }
        NSWorkspace.shared.open(url)
    }

    /// WKWebView properties are main-thread only, so KVO fires on the main
    /// actor; mirror the ones the toolbar gates on into observable state.
    private func observeNavigation() {
        observations = [
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, change in
                MainActor.assumeIsolated {
                    self?.isLoading = change.newValue ?? false
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, change in
                MainActor.assumeIsolated {
                    self?.canGoBack = change.newValue ?? false
                }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, change in
                MainActor.assumeIsolated {
                    self?.canGoForward = change.newValue ?? false
                }
            },
        ]
    }

    private static func isLoopback(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}

/// Minimal `NSViewRepresentable` hosting `EditorWebModel.webView`.
struct EditorWebView: NSViewRepresentable {
    let model: EditorWebModel

    func makeNSView(context: Context) -> WKWebView {
        model.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op: the model drives navigation.
    }
}
