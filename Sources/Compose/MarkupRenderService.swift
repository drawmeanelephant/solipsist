import Foundation

/// Author-facing render options, mirroring Oliver's `ParseOptions` (the
/// rendering engine behind Boris): every extension is off by default, and
/// the profile / frontmatter / raw-HTML policies map 1:1 to Oliver's CLI
/// flags. `docs/FEATURE-MATRIX.md` pins each behavior.
struct MarkupRenderOptions: Equatable, Sendable {
    enum Profile: String, Sendable {
        case html
        case xhtml
    }

    enum RawHTMLPolicy: String, Sendable {
        case allowed
        case escaped
        case rejected
    }

    enum FrontmatterPolicy: String, Sendable {
        case none
        case yaml
        case toml
    }

    var profile: Profile = .html
    var wikilinks = false
    var callouts = false
    var smartypants = false
    var footnotes = false
    var definitionLists = false
    var headingAttributes = false
    var strikethrough = false
    var headingIDs = false
    var taskLists = false
    var rawHTML: RawHTMLPolicy = .allowed
    var frontmatter: FrontmatterPolicy = .none
}

/// The seam between the compose element and a renderer.
///
/// The rendering engine behind Boris is **Oliver** (`oliver render --from
/// markdown|textile|cooklang`). Solipsist's rule is that only the Engine
/// lane starts subprocesses, so the real implementation lives behind
/// `OliverRenderService` (Engine seam). The element ships the placeholder
/// below so the preview pane is functional and testable standalone.
protocol MarkupRenderService: Sendable {
    /// Renders a source buffer to an HTML fragment for the given options.
    func render(
        _ source: String,
        language: ComposeLanguage,
        options: MarkupRenderOptions
    ) async throws -> MarkupRenderResult
}

/// What a renderer returns: the HTML fragment plus any parse diagnostics
/// (LATER-3.1 — Oliver's span-based diagnostics mapped into the compose
/// seam). The editor shows diagnostics in the problems pane; the preview
/// shows only the HTML.
struct MarkupRenderResult: Sendable {
    let html: String
    let diagnostics: [ComposeDiagnostic]

    init(html: String, diagnostics: [ComposeDiagnostic] = []) {
        self.html = html
        self.diagnostics = diagnostics
    }
}

/// Placeholder: HTML-escapes the source so the preview is safe and shows
/// exactly what was authored. Same escape policy as Oliver's text writer
/// (`& < > "` and NUL → U+FFFD) so the swap to the real renderer changes
/// content, not posture. No diagnostics — the placeholder has no parser.
struct PlaceholderRenderService: MarkupRenderService {
    func render(
        _ source: String,
        language: ComposeLanguage,
        options: MarkupRenderOptions
    ) async throws -> MarkupRenderResult {
        let escaped = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\u{0}", with: "\u{FFFD}")
        let html = "<pre style=\"white-space: pre-wrap; font: 12px ui-monospace;\">\(escaped)</pre>"
        return MarkupRenderResult(html: html)
    }
}
