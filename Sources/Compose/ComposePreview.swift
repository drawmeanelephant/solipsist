import SwiftUI

/// The compose element's preview pane. Renders through the injected
/// `MarkupRenderService` (Oliver-backed in the app; placeholder standalone),
/// debounced so the subprocess render runs only when the author pauses.
struct ComposePreviewView: View {
    let source: String
    let language: ComposeLanguage
    let options: MarkupRenderOptions
    let renderService: any MarkupRenderService

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
                html = rendered
                renderError = nil
            } catch is CancellationError {
                // A newer request superseded this one; keep the last frame.
            } catch {
                renderError = String(describing: error)
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

/// Hosts the rendered fragment. `WKWebView`-free on purpose: the compose
/// preview is a sandboxed HTML fragment view, not a browser surface.
private struct ComposeHTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 12, height: 12)
        apply(html, to: textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        apply(html, to: textView)
    }

    private func apply(_ html: String, to textView: NSTextView) {
        guard
            let data = html.data(using: .utf8),
            let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
            )
        else {
            textView.string = html
            return
        }
        textView.textStorage?.setAttributedString(attributed)
    }
}
