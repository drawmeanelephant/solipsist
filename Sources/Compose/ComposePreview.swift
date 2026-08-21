import SwiftUI
import WebKit

/// The compose element's preview pane. Renders through the injected
/// `MarkupRenderService` (Oliver-backed in the app; placeholder standalone),
/// debounced so the subprocess render runs only when the author pauses.
struct ComposePreviewView: View {
    let source: String
    let language: ComposeLanguage
    let options: MarkupRenderOptions
    let renderService: any MarkupRenderService
    /// Theme CSS resolved from the source's profile / `themes/` directory
    /// (#230). Nil → the fallback stylesheet. The host resolves it; this
    /// view never touches the workspace.
    var themeCSS: String?
    /// Receives the mapped diagnostics after each render (LATER-3.1). The
    /// editor owns the problems pane; the preview only renders HTML.
    var onDiagnostics: ([ComposeDiagnostic]) -> Void = { _ in }

    @State private var html: String?
    @State private var renderError: String?

    var body: some View {
        Group {
            if let html {
                ComposeHTMLPreview(html: html)
            } else if let renderError {
                ContentUnavailableView {
                    Label("Render Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(renderError)
                        .multilineTextAlignment(.center)
                }
            } else {
                ProgressView("Rendering…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: PreviewRequest(language: language, options: options, source: source)) {
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let rendered = try await renderService.render(source, language: language, options: options)
                guard !Task.isCancelled else { return }
                // Wrap the fragment with the theme CSS here so the web view
                // receives one self-contained document (#230).
                html = ComposePreviewDocument.html(fragment: rendered.html, themeCSS: themeCSS)
                renderError = nil
                onDiagnostics(rendered.diagnostics)
            } catch is CancellationError {
                // A newer request superseded this one; keep the last frame.
            } catch {
                renderError = String(describing: error)
                // Never swallow: the problems pane sees the render failure too.
                onDiagnostics([ComposeDiagnostic(severity: .error, message: String(describing: error))])
            }
        }
    }
}

/// Equatable request identity so `.task(id:)` restarts (and cancels) the
/// previous render whenever the buffer, language, or options change.
private struct PreviewRequest: Equatable {
    let language: ComposeLanguage
    let options: MarkupRenderOptions
    let source: String
}

/// Hosts the rendered document in a sandboxed `WKWebView` (#230): full CSS,
/// JavaScript, and media support without an in-process HTML parse. The web
/// view uses a non-persistent data store (no disk cache) and loads the
/// self-contained document with `baseURL: nil` — styling needs no file or
/// network access, and there is no app-side HTTP server (D11). Navigation
/// policy lives in `ComposePreviewCoordinator`.
private struct ComposeHTMLPreview: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> ComposePreviewCoordinator {
        ComposePreviewCoordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(html, in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.reloadIfChanged(html, in: webView)
    }
}
