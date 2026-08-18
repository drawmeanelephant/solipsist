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
    ) async throws -> String {
        let result = try await renderer.render(
            source: source,
            frontend: Self.frontend(for: language),
            options: Self.engineOptions(options)
        )
        return result.html
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
