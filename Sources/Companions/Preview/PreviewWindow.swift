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
///
/// #234: Pinch-to-zoom (trackpad) and ⌘+/-/0 zoom controls are supported.
/// Zoom level is persisted per-source in UserDefaults and restored when
/// switching between sources.
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
                    model.setSource(id: source.id.raw.uuidString)
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
        .onChange(of: model.zoomLevel) { _, _ in
            model.persistZoom()
        }
    }

    /// Starts (or reuses) the watch server for the selected source's content
    /// root. Ran per source id; switching sources restarts the server.
    private func startPreview(for source: SourceItem) {
        let folder: (any PlayFolderSource)?
        switch source {
        case .local(let local): folder = local
        case .github(let github): folder = github
        }
        guard let folder,
              let projectRoot = try? folder.workspaceRoot(),
              let contentRoot = try? folder.contentRoot()
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
        .glassEffect()
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("http://127.0.0.1:8080/__boris/", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                    .accessibilityLabel("Preview URL")

                Button {
                    model.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload")
                .accessibilityAddTraits(.isButton)
                .help("Reload")
                .disabled(!model.canReload)

                Button {
                    model.openInBrowser()
                } label: {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("Open in Browser")
                .accessibilityAddTraits(.isButton)
                .help("Open in Browser")
                .disabled(!model.canOpenInBrowser)

                Divider().frame(height: 16)

                Button {
                    model.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .accessibilityLabel("Zoom Out")
                .accessibilityAddTraits(.isButton)
                .help("Zoom Out (⌘-)")

                Text("\(Int(model.zoomLevel * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 40)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())

                Button {
                    model.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .accessibilityLabel("Zoom In")
                .accessibilityAddTraits(.isButton)
                .help("Zoom In (⌘+)")

                Button {
                    model.zoomReset()
                } label: {
                    Image(systemName: "1.magnifyingglass")
                }
                .accessibilityLabel("Reset Zoom")
                .accessibilityAddTraits(.isButton)
                .help("Reset Zoom (⌘0)")
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
        .onKeyPress("+") {
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            model.zoomIn()
            return .handled
        }
        .onKeyPress("-") {
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            model.zoomOut()
            return .handled
        }
        .onKeyPress("0") {
            guard NSEvent.modifierFlags.contains(.command) else { return .ignored }
            model.zoomReset()
            return .handled
        }
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
///
/// #234: Pinch-to-zoom is enabled on the WKWebView; ⌘+/-/0 shortcuts
/// drive `zoomIn()` / `zoomOut()` / `zoomReset()`. Zoom level is
/// persisted per-source in UserDefaults.
@MainActor
@Observable
final class PreviewWebModel {
    let webView = WKWebView()

    private(set) var currentURL: URL?
    private(set) var rejection: String?

    /// #234: Current zoom level (1.0 = 100%). Published so the toolbar
    /// percentage label can observe it. Synced from the WKWebView's
    /// `magnification` via KVO.
    private(set) var zoomLevel: CGFloat = 1.0

    /// #234: Source ID for per-source zoom persistence in UserDefaults.
    private var sourceID: String?

    private static let minZoom: CGFloat = 0.25
    private static let maxZoom: CGFloat = 4.0
    private static let zoomStep: CGFloat = 1.25

    /// KVO observation token for `webView.magnification`. Stored so the
    /// observation survives across method calls and is cleaned up on
    /// deinit. `nonisolated(unsafe)` so `deinit` can invalidate it.
    private nonisolated(unsafe) var magnificationObservation: NSKeyValueObservation?

    init() {
        webView.allowsMagnification = true
        magnificationObservation = webView.observe(\.magnification) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                self?.zoomLevel = webView.magnification
            }
        }
    }

    deinit {
        magnificationObservation?.invalidate()
    }

    var canReload: Bool {
        currentURL != nil || webView.url != nil
    }

    var canOpenInBrowser: Bool {
        guard let url = currentURL else { return false }
        return Self.isLoopback(url)
    }

    /// #234: Bind the source ID for per-source zoom persistence.
    func setSource(id: String) {
        sourceID = id
        restoreZoom()
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

    // MARK: - Zoom (#234)

    /// Zoom in by 1.25× (matching trackpad feel), clamped to `maxZoom`.
    func zoomIn() {
        webView.magnification = min(webView.magnification * Self.zoomStep, Self.maxZoom)
    }

    /// Zoom out by 1/1.25×, clamped to `minZoom`.
    func zoomOut() {
        webView.magnification = max(webView.magnification / Self.zoomStep, Self.minZoom)
    }

    /// Reset zoom to 100%.
    func zoomReset() {
        webView.magnification = 1.0
    }

    /// #234: Restore the persisted zoom level for the current source.
    /// Called from `setSource(id:)` and after the page finishes loading
    /// to override any magnification reset that the navigation causes.
    func restoreZoom() {
        guard let sourceID else { return }
        let stored = UserDefaults.standard.double(forKey: zoomKey(sourceID))
        let level = stored > 0 ? stored : 1.0
        webView.magnification = level
    }

    /// Called from the view's `onChange(of: zoomLevel)` to persist the
    /// user's zoom preference per-source.
    func persistZoom() {
        guard let sourceID else { return }
        UserDefaults.standard.set(Double(zoomLevel), forKey: zoomKey(sourceID))
    }

    private func zoomKey(_ sourceID: String) -> String {
        "preview.zoom.\(sourceID)"
    }

    // MARK: - URL helpers

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
