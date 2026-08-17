import AppKit
import Observation
import SwiftUI
import WebKit

/// Helper parser for Boris editor token launch lines.
public enum EditorURL {
    public enum ParseError: LocalizedError, Equatable {
        case empty
        case invalidURL
        case notLoopback
        case missingTokenFragment
        case invalidTokenHex

        public var errorDescription: String? {
            switch self {
            case .empty:
                return "Please enter a BORIS_EDITOR_URL line or URL."
            case .invalidURL:
                return "That is not a valid URL."
            case .notLoopback:
                return "Editor URL must use a loopback host (http://127.0.0.1 or http://localhost)."
            case .missingTokenFragment:
                return "Editor URL must include a #token= fragment."
            case .invalidTokenHex:
                return "Editor token fragment must be hexadecimal characters."
            }
        }
    }

    /// Parses a `BORIS_EDITOR_URL=http://127.0.0.1:<port>/#token=<hex>` line or raw URL.
    public static func parse(_ raw: String) throws -> URL {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("BORIS_EDITOR_URL=") {
            trimmed = String(trimmed.dropFirst("BORIS_EDITOR_URL=".count))
        }
        guard !trimmed.isEmpty else {
            throw ParseError.empty
        }
        guard let components = URLComponents(string: trimmed), let url = components.url else {
            throw ParseError.invalidURL
        }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" else {
            throw ParseError.invalidURL
        }
        guard let host = components.host?.lowercased(), (host == "127.0.0.1" || host == "localhost" || host == "::1") else {
            throw ParseError.notLoopback
        }
        guard let fragment = components.fragment, fragment.hasPrefix("token=") else {
            throw ParseError.missingTokenFragment
        }
        let token = String(fragment.dropFirst("token=".count))
        guard !token.isEmpty, token.allSatisfy({ $0.isHexDigit }) else {
            throw ParseError.invalidTokenHex
        }

        return url
    }
}

/// Companion host for `boris-editor` (Svelte). Chassis registers the window
/// and leaves it closed. The Editor lane owns this file.
///
/// The grind lane will later add engine-spawned editor tokens and call
/// `loadEditor(url:)`. Until then the window shows the editor status and
/// lets a human paste a `BORIS_EDITOR_URL=` token line into the toolbar.
struct EditorWindow: View {
    @Environment(WorkspaceStore.self) private var store

    @State private var model = EditorWebModel()
    @State private var urlText = ""

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
            } else {
                emptyState
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle("Editor")
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
            Text("The Boris editor for “\(source.title)” will connect when the host process is running. Paste a BORIS_EDITOR_URL= line above to connect manually.")
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
                TextField("BORIS_EDITOR_URL=http://127.0.0.1:49152/#token=…", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)

                Button("Connect", action: submit)

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
final class EditorWebModel {
    let webView = WKWebView()

    private(set) var currentURL: URL?
    private(set) var rejection: String?

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

    func openInBrowser() {
        guard let url = currentURL, Self.isLoopback(url) else { return }
        NSWorkspace.shared.open(url)
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
