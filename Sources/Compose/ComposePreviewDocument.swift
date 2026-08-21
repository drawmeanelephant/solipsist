import Foundation

/// Assembles the self-contained HTML document the compose preview loads.
///
/// The fragment (Oliver's render output) is wrapped with the theme CSS
/// inlined as a `<style>` element, so styling needs no file or network
/// access (#230): `loadHTMLString(_:baseURL: nil)` cannot resolve relative
/// resources from the sandboxed web content process, and the app never
/// serves HTTP. Relative image/media URLs in the content are therefore out
/// of scope here — resolving them is the full-site Preview companion's job.
///
/// Pure and unit-testable; the WKWebView host only consumes the result.
enum ComposePreviewDocument {
    /// Loopback origin reported to tests / policy checks. `loadHTMLString`
    /// with a nil baseURL surfaces as `about:blank` in the web view.
    static let aboutBlank = "about:blank"

    /// Minimal readable stylesheet used when no theme CSS resolves.
    /// Honors the system appearance (`color-scheme` + adaptive `canvas`
    /// colors) so dark mode stays legible without a theme dark variant.
    /// Theme CSS is applied verbatim when present — we never rewrite it.
    static let fallbackCSS = """
    :root { color-scheme: light dark; }
    body {
      margin: 0 auto;
      max-width: 64rem;
      padding: 1rem 1.5rem 3rem;
      font-family: system-ui, -apple-system, sans-serif;
      line-height: 1.6;
      color: canvastext;
      background: canvas;
    }
    pre { overflow-x: auto; }
    code, pre { font-family: ui-monospace, monospace; font-size: 0.95em; }
    """

    /// Builds the full document for the preview pane.
    static func html(fragment: String, themeCSS: String?) -> String {
        let css = themeCSS.flatMap { $0.isEmpty ? nil : sanitize($0) } ?? fallbackCSS
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <style>
        \(css)
        </style>
        </head>
        <body>
        \(fragment)
        </body>
        </html>
        """
    }

    /// Neutralizes any `</style…>` inside the injected CSS so a broken or
    /// hostile stylesheet cannot escape the style element into markup.
    /// `<\/` is a valid CSS escape inside strings/identifiers and corrupts
    /// nothing a stylesheet could legitimately contain.
    static func sanitize(_ css: String) -> String {
        css.replacingOccurrences(
            of: "</",
            with: "<\\/",
            options: .caseInsensitive,
            range: css.startIndex..<css.endIndex
        )
    }
}
