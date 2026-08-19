import Foundation

/// The Oliver-backed `MarkupRenderService`: renders buffers through the
/// Engine's `OliverRenderer` subprocess seam. The mapping between the
/// compose surface's types and Oliver's frontends / flags lives here, so
/// the Engine lane never imports the Compose lane.
struct OliverRenderService: MarkupRenderService {
    var renderer: OliverRenderer

    init(renderer: OliverRenderer = OliverRenderer()) {
        self.renderer = renderer
    }

    func render(
        _ source: String,
        language: ComposeLanguage,
        options: MarkupRenderOptions
    ) async throws -> MarkupRenderResult {
        var engineOptions = Self.engineOptions(options)
        engineOptions.diagnostics = true
        let result = try await renderer.render(
            source: source,
            frontend: Self.frontend(for: language),
            options: engineOptions
        )
        return MarkupRenderResult(
            html: result.html,
            diagnostics: Self.composeDiagnostics(from: result.diagnostics)
        )
    }

    /// Maps Oliver's span-based diagnostics into the compose problems seam.
    /// Only the rendered fields are read; unknown severities degrade to a
    /// warning (D8) and `span.start` becomes the click-to-line character
    /// index.
    static func composeDiagnostics(from diagnostics: [OliverDiagnostic]) -> [ComposeDiagnostic] {
        diagnostics.map { diagnostic in
            ComposeDiagnostic(
                severity: diagnostic.severity == "error" ? .error : .warning,
                message: diagnostic.message ?? diagnostic.code ?? "render diagnostic",
                line: diagnostic.line,
                characterIndex: diagnostic.span?.start
            )
        }
    }

    // MARK: - Mapping (pure, tested)

    static func frontend(for language: ComposeLanguage) -> OliverFrontend {
        switch language {
        case .markdown: return .markdown
        case .textile: return .textile
        case .cooklang: return .cooklang
        }
    }

    static func engineOptions(_ options: MarkupRenderOptions) -> OliverRenderOptions {
        var engine = OliverRenderOptions()
        engine.profile = options.profile == .xhtml ? .xhtml : .html
        engine.wikilinks = options.wikilinks
        engine.callouts = options.callouts
        engine.smartypants = options.smartypants
        engine.footnotes = options.footnotes
        engine.definitionLists = options.definitionLists
        engine.headingAttributes = options.headingAttributes
        engine.strikethrough = options.strikethrough
        engine.headingIDs = options.headingIDs
        engine.taskLists = options.taskLists
        switch options.rawHTML {
        case .allowed: engine.rawHTML = .allowed
        case .escaped: engine.rawHTML = .escaped
        case .rejected: engine.rawHTML = .rejected
        }
        switch options.frontmatter {
        case .none: engine.frontmatter = .none
        case .yaml: engine.frontmatter = .yaml
        case .toml: engine.frontmatter = .toml
        }
        return engine
    }
}
