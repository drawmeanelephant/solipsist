import AppKit
import Observation
import SwiftUI
import WebKit

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
