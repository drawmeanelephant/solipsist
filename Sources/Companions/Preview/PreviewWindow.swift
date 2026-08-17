import AppKit
import Observation
import SwiftUI
import WebKit

/// Companion host for `boris watch --serve`. Chassis registers the window
/// and leaves it closed. The Preview lane owns this file.
///
/// The grind lane will later add `BorisEngine.previewStart/Stop` and point
/// this window at the served URL by calling `loadPreview(url:)`. Until then
/// the web view starts blank and a human can paste a loopback URL into the
/// toolbar.
struct PreviewWindow: View {
    @Environment(WorkspaceStore.self) private var store

    @State private var model = PreviewWebModel()
    @State private var urlText = ""

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
            } else {
                emptyState
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle("Preview")
        .task {
            model.loadBlank()
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
