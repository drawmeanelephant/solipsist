import Observation
import SwiftUI
import WebKit

/// Navigation outcome for the reading-pane web view. 404 and transport
/// failure fall back to the contract summary; the model never loads `file://`.
enum ReadingLoadOutcome: Equatable {
    case idle
    case loading
    case loaded
    case unavailable(String)
    case failed(String)
}

/// Owns the letter's `WKWebView`. Main-actor confined; Play is the only client.
@MainActor
@Observable
final class ReadingWebModel: NSObject {
    let webView: WKWebView
    private(set) var outcome: ReadingLoadOutcome = .idle

    override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        webView.allowsMagnification = true
    }

    func load(url: URL) {
        guard PreviewURL.isAllowed(url) else {
            outcome = .failed("Only loopback URLs are allowed.")
            return
        }
        outcome = .loading
        webView.stopLoading()
        webView.load(URLRequest(url: url))
    }

    func reset() {
        outcome = .idle
        webView.stopLoading()
    }

    func retry(url: URL) {
        load(url: url)
    }

    func fail(_ message: String) {
        outcome = .failed(message)
    }

    private func handleHTTPFailure(_ status: Int) {
        let caption: String
        if status == 404 {
            caption = "This page is not at the served URL yet. Build HTML or wait for watch."
        } else {
            caption = "The served page returned HTTP \(status)."
        }
        outcome = status == 404 ? .unavailable(caption) : .failed(caption)
    }

    private func handleTransportFailure(_ error: Error) {
        if case .unavailable = outcome { return }
        if case .failed = outcome { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }
        outcome = .failed(error.localizedDescription)
    }
}

extension ReadingWebModel: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        let allowed = url.map { PreviewURL.isAllowed($0) } ?? false
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let status = (navigationResponse.response as? HTTPURLResponse)?.statusCode
        if navigationResponse.isForMainFrame, let status, status >= 400 {
            decisionHandler(.cancel)
            handleHTTPFailure(status)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleTransportFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleTransportFailure(error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard outcome == .loading else { return }
        outcome = .loaded
    }
}

/// Hosts `ReadingWebModel.webView`. Navigation stays on the model.
struct ReadingWebView: NSViewRepresentable {
    let model: ReadingWebModel

    func makeNSView(context: Context) -> WKWebView {
        model.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op: the model owns all navigation.
    }
}
