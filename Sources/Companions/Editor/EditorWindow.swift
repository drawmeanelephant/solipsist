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
                return "Malformed editor URL."
            case .notLoopback:
                return "Editor URL must use a loopback host (127.0.0.1 or localhost)."
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

/// Companion host for `boris-editor` (Svelte).
/// Receives and verifies `BORIS_EDITOR_URL=` tokens and loads the editor inside WKWebView.
struct EditorWindow: View {
    @Environment(WorkspaceStore.self) private var store

    @State private var inputLine: String = ""
    @State private var currentURL: URL?
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
                        EditorWebView(url: currentURL)
                    } else {
                        ContentUnavailableView {
                            Label("Editor Host Not Running", systemImage: "square.and.pencil")
                        } description: {
                            Text("The Boris editor for “\(source.title)” will connect when the host process is running. Paste a BORIS_EDITOR_URL= line above to connect manually.")
                        }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No Source Selected", systemImage: "folder")
                } description: {
                    Text("Select a source in the main window, then open the editor.")
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        if let source = store.selectedSource {
            return "Editor — \(source.title)"
        }
        return "Editor"
    }

    private func toolbarView(source: SourceItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: source.symbolName)
                .foregroundStyle(.secondary)

            TextField("BORIS_EDITOR_URL=http://127.0.0.1:<port>/#token=…", text: $inputLine)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .onSubmit {
                    submitLine()
                }

            Button {
                submitLine()
            } label: {
                Text("Connect")
            }

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

    private func submitLine() {
        do {
            let url = try EditorURL.parse(inputLine)
            errorMessage = nil
            currentURL = url
        } catch let err as EditorURL.ParseError {
            errorMessage = err.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EditorWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}
