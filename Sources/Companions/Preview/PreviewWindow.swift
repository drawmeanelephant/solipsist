import AppKit
import Observation
import SwiftUI
import WebKit

/// Companion host for `boris watch --serve` (D5). Chassis registers the
/// window and leaves it closed; the Preview lane owns this file.
///
/// When a source is selected the window starts a `WatchServer` for its
/// content root via the shared `AppRuntime.previewSession`; the served
/// helper URL (`…/__boris/`) is loaded into the web view, where the helper
/// page owns the iframe + SSE auto-reload. Closing this window does not
/// stop the watch — Play's reading pane reuses it. The toolbar keeps the
/// manual loopback-paste escape hatch.
struct PreviewWindow: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime

    @State private var model = PreviewWebModel()
    @State private var urlText = ""

    private var session: PreviewSession { runtime.previewSession }

    var body: some View {
        Group {
            if let source = store.selectedSource {
                VStack(spacing: 0) {
                    header(for: source)
                    Divider()
                    toolbar
                    Divider()
                    PreviewWebView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .task(id: source.id) {
                    startPreview(for: source)
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle("Preview")
        .task {
            model.loadBlank()
        }
        .onChange(of: session.serveURL) { _, newURL in
            if let newURL {
                model.load(url: newURL)
            } else {
                model.loadBlank()
            }
        }
    }

    /// Starts (or reuses) the watch server for the selected source's content
    /// root. Ran per source id; switching sources restarts the server.
    private func startPreview(for source: SourceItem) {
        switch source {
        case .local(let local):
            guard
                let projectRoot = try? local.workspaceRoot(),
                let contentRoot = try? local.contentRoot()
            else {
                session.fail("could not resolve the project folder for '\(source.title)'")
                return
            }
            session.start(
                contentRoot: contentRoot,
                projectRoot: projectRoot,
                engine: runtime.engine,
                coordinator: runtime.coordinator
            )
        }
    }

    /// Single entry point the grind lane uses to point the web view at a
    /// `serve-started` / `previewStart` URL. Loopback validation still applies.
    func loadPreview(url: URL) {
        model.load(url: url)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Preview", systemImage: "safari")
        } description: {
            Text("Select a source in the main window, then open Preview.")
        }
    }

    private func header(for source: SourceItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.headline)
                    .lineLimit(1)
                if let path = source.detailLine {
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
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("http://127.0.0.1:8080/__boris/", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)

                Button {
                    model.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
                .disabled(!model.canReload)

                Button {
                    model.openInBrowser()
                } label: {
                    Image(systemName: "safari")
                }
                .help("Open in Browser")
                .disabled(!model.canOpenInBrowser)
            }
            if let rejection = model.rejection {
                Text(rejection)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text(session.statusText)
                .font(.caption)
                .foregroundStyle(session.isFailure ? Color.red : .secondary)
        }
        .padding(8)
    }

    private func submit() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            model.reject("That is not a URL.")
            return
        }
        model.load(url: url)
    }
}

/// Owns the `WKWebView` and the tiny bit of navigation state the toolbar
/// needs. Main-actor confined; the view is its only client.
@MainActor
@Observable
final class PreviewWebModel {
    let webView = WKWebView()

    private(set) var currentURL: URL?
    private(set) var rejection: String?

    var canReload: Bool {
        currentURL != nil || webView.url != nil
    }

    var canOpenInBrowser: Bool {
        guard let url = currentURL else { return false }
        return Self.isLoopback(url)
    }

    func loadBlank() {
        currentURL = nil
        rejection = nil
        if let blank = URL(string: "about:blank") {
            webView.load(URLRequest(url: blank))
        }
    }

    func load(url: URL) {
        guard Self.isAllowed(url) else {
            reject("Only loopback URLs are allowed (http://127.0.0.1 or http://localhost).")
            return
        }
        rejection = nil
        currentURL = url
        webView.load(URLRequest(url: url))
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

    func openInBrowser() {
        guard let url = currentURL, Self.isLoopback(url) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func isAllowed(_ url: URL) -> Bool {
        PreviewURL.isAllowed(url)
    }

    private static func isLoopback(_ url: URL) -> Bool {
        PreviewURL.isLoopback(url)
    }
}

/// Minimal `NSViewRepresentable` so `PreviewWebModel.webView` can live in a
/// SwiftUI window. Navigation is driven by the model; this only hosts the view.
struct PreviewWebView: NSViewRepresentable {
    let model: PreviewWebModel

    func makeNSView(context: Context) -> WKWebView {
        model.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op: the model owns all navigation.
    }
}
