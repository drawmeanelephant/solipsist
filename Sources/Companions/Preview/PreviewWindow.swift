import SwiftUI
import WebKit

/// Companion host for `boris watch --serve`.
/// Loads loopback previews with reload and external browser controls.
struct PreviewWindow: View {
    @Environment(WorkspaceStore.self) private var store

    @State private var urlString: String = "http://127.0.0.1:8080/__boris/"
    @State private var currentURL: URL?
    @State private var reloadTrigger: UUID = UUID()
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let source = store.selectedSource {
                VStack(spacing: 0) {
                    toolbarView(source: source)
                    Divider()

                    if let errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(errorMessage)
                                .font(.caption)
                            Spacer()
                            Button("Dismiss") { self.errorMessage = nil }
                                .buttonStyle(.plain)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                    }

                    if let currentURL {
                        PreviewWebView(url: currentURL, reloadTrigger: reloadTrigger)
                    } else {
                        ContentUnavailableView {
                            Label("Preview Ready", systemImage: "safari")
                        } description: {
                            Text("Enter a local preview URL (e.g. http://127.0.0.1:8080/__boris/) or wait for boris watch --serve.")
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Source Selected", systemImage: "folder")
                } description: {
                    Text("Select a source in the main window to enable live preview.")
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        if let source = store.selectedSource {
            return "Preview — \(source.title)"
        }
        return "Preview"
    }

    private func toolbarView(source: SourceItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: source.symbolName)
                .foregroundStyle(.secondary)

            TextField("http://127.0.0.1:<port>/__boris/", text: $urlString)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .onSubmit {
                    submitURL()
                }

            Button {
                submitURL()
            } label: {
                Text("Go")
            }

            Button {
                reloadTrigger = UUID()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .help("Reload Preview")
            .disabled(currentURL == nil)

            Button {
                if let currentURL {
                    NSWorkspace.shared.open(currentURL)
                }
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            .help("Open in Default Web Browser")
            .disabled(currentURL == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func submitURL() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Invalid URL format."
            return
        }
        guard Self.isLoopback(url: url) else {
            errorMessage = "Only loopback addresses (127.0.0.1 / localhost) are permitted."
            return
        }
        errorMessage = nil
        loadPreview(url: url)
    }

    /// External entrypoint for BorisEngine preview Start / serve-started notification.
    public func loadPreview(url: URL) {
        guard Self.isLoopback(url: url) else { return }
        urlString = url.absoluteString
        currentURL = url
        reloadTrigger = UUID()
    }

    public static func isLoopback(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}

private struct PreviewWebView: NSViewRepresentable {
    let url: URL
    let reloadTrigger: UUID

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastTrigger != reloadTrigger {
            context.coordinator.lastTrigger = reloadTrigger
            if webView.url == url {
                webView.reload()
            } else {
                webView.load(URLRequest(url: url))
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(reloadTrigger: reloadTrigger)
    }

    final class Coordinator {
        var lastTrigger: UUID

        init(reloadTrigger: UUID) {
            self.lastTrigger = reloadTrigger
        }
    }
}
