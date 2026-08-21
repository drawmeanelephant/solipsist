import Foundation
import WebKit

/// Navigation policy for the compose preview web view (#230): exactly one
/// main-frame navigation is allowed — the load the host initiated. Every
/// other request (link clicks, sub-frames, programmatic navigation,
/// back/forward) is cancelled. Pure so the contract is testable without
/// driving WebKit.
enum ComposePreviewSandbox {
    static func allows(initialLoadPending: Bool, isMainFrame: Bool) -> Bool {
        initialLoadPending && isMainFrame
    }
}

/// Owns the load lifecycle for one preview web view: dedupes reloads,
/// arms the single allowed navigation per load, and enforces the sandbox.
/// Main-actor confined; the SwiftUI representable is the only client.
@MainActor
final class ComposePreviewCoordinator: NSObject {
    private var lastLoaded: String?
    private var initialLoadPending = false

    /// Loads the document unless it is already what the view shows (a
    /// SwiftUI pass re-runs `updateNSView` constantly; reloading would
    /// flicker and reset scroll on every keystroke).
    func reloadIfChanged(_ html: String, in webView: WKWebView) {
        guard html != lastLoaded else { return }
        load(html, in: webView)
    }

    func load(_ html: String, in webView: WKWebView) {
        lastLoaded = html
        initialLoadPending = true
        webView.loadHTMLString(html, baseURL: nil)
    }
}

extension ComposePreviewCoordinator: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame == true
        let allow = ComposePreviewSandbox.allows(
            initialLoadPending: initialLoadPending,
            isMainFrame: isMainFrame
        )
        // Consume the grant even if the delegate is skipped for the
        // initial load — didFinish/didFail close it below as well.
        if isMainFrame { initialLoadPending = false }
        decisionHandler(allow ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        initialLoadPending = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        initialLoadPending = false
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        initialLoadPending = false
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Target=_blank / window.open never leaves the pane.
        nil
    }
}
