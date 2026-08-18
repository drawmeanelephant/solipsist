import XCTest

final class OliverRenderServiceTests: XCTestCase {
    // MARK: - Mapping (pure)

    func testFrontendMapping() {
        XCTAssertEqual(OliverRenderService.frontend(for: .markdown), .markdown)
        XCTAssertEqual(OliverRenderService.frontend(for: .textile), .textile)
        XCTAssertEqual(OliverRenderService.frontend(for: .cooklang), .cooklang)
    }

    func testOptionsMappingPreservesFlags() {
        var options = MarkupRenderOptions()
        options.wikilinks = true
        options.strikethrough = true
        options.frontmatter = .yaml
        options.rawHTML = .rejected
        options.profile = .xhtml

        let engine = OliverRenderService.engineOptions(options)
        XCTAssertTrue(engine.wikilinks)
        XCTAssertTrue(engine.strikethrough)
        XCTAssertFalse(engine.callouts)
        XCTAssertEqual(engine.frontmatter, .yaml)
        XCTAssertEqual(engine.rawHTML, .rejected)
        XCTAssertEqual(engine.profile, .xhtml)
        XCTAssertEqual(
            engine.arguments(frontend: .markdown),
            ["render", "--from", "markdown", "--to", "xhtml", "--wikilinks",
             "--strikethrough", "--raw-html", "rejected", "--frontmatter", "yaml"]
        )
    }

    // MARK: - End to end (skipped in CI without an oliver binary)

    func testRenderMarkdownThroughOliver() async throws {
        let renderer = try rendererFromEnvironment()
        let result = try await renderer.render(
            source: "# Hello *world*",
            frontend: .markdown,
            options: OliverRenderOptions()
        )
        XCTAssertEqual(result.html.trimmingCharacters(in: .whitespacesAndNewlines), "<h1>Hello <em>world</em></h1>")
    }

    func testRenderCooklangThroughOliver() async throws {
        let renderer = try rendererFromEnvironment()
        let result = try await renderer.render(
            source: "Add @salt{1%tsp} and simmer ~{25%minutes}.",
            frontend: .cooklang,
            options: OliverRenderOptions()
        )
        XCTAssertTrue(result.html.contains("<article class=\"recipe\">"))
        XCTAssertTrue(result.html.contains("data-quantity=\"1\""))
        XCTAssertTrue(result.html.contains("datetime=\"PT25M\""))
    }

    func testRenderWithExtensionFlagThroughOliver() async throws {
        let renderer = try rendererFromEnvironment()
        var options = OliverRenderOptions()
        options.wikilinks = true
        let result = try await renderer.render(
            source: "See [[Notes]].",
            frontend: .markdown,
            options: options
        )
        XCTAssertTrue(result.html.contains("<a href=\"Notes\">Notes</a>"))
    }

    func testServiceRenderReturnsHTMLFragment() async throws {
        guard let bin = ProcessInfo.processInfo.environment["SOLIPSIST_OLIVER_BIN"], !bin.isEmpty else {
            throw XCTSkip("SOLIPSIST_OLIVER_BIN not set")
        }
        let service = OliverRenderService(renderer: OliverRenderer(binaryURL: URL(fileURLWithPath: bin)))
        let html = try await service.render("h1. Title", language: .textile, options: MarkupRenderOptions())
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
    }

    // MARK: - Helpers

    private func rendererFromEnvironment() throws -> OliverRenderer {
        guard let bin = ProcessInfo.processInfo.environment["SOLIPSIST_OLIVER_BIN"], !bin.isEmpty else {
            throw XCTSkip("SOLIPSIST_OLIVER_BIN not set")
        }
        return OliverRenderer(binaryURL: URL(fileURLWithPath: bin))
    }
}
