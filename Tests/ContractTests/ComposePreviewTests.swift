import XCTest

final class ComposePreviewTests: XCTestCase {
    private func render(_ source: String, language: ComposeLanguage) async throws -> MarkupRenderResult {
        try await PlaceholderRenderService().render(
            source,
            language: language,
            options: MarkupRenderOptions()
        )
    }

    func testPlaceholderEscapesHTML() async throws {
        let result = try await render("<b>&\"</b>", language: .markdown)
        XCTAssertTrue(result.html.contains("&lt;b&gt;&amp;&quot;&lt;/b&gt;"))
        XCTAssertFalse(result.html.contains("<b>"))
        XCTAssertFalse(result.html.contains("&amp;lt;")) // no double-escape
    }

    func testPlaceholderEscapesPerLanguage() async throws {
        let markdown = try await render("1 < 2", language: .markdown)
        let textile = try await render("1 < 2", language: .textile)
        let cooklang = try await render("1 < 2", language: .cooklang)
        XCTAssertEqual(markdown.html, textile.html)
        XCTAssertEqual(markdown.html, cooklang.html)
        XCTAssertTrue(markdown.html.contains("&lt;"))
    }

    func testPlaceholderReplacesNUL() async throws {
        let result = try await render("a\u{0}b", language: .cooklang)
        XCTAssertTrue(result.html.contains("\u{FFFD}"))
        XCTAssertFalse(result.html.contains("\u{0}"))
    }

    func testPlaceholderIgnoresOptions() async throws {
        var options = MarkupRenderOptions()
        options.wikilinks = true
        options.profile = .xhtml
        let result = try await PlaceholderRenderService().render(
            "See [[Notes]].",
            language: .markdown,
            options: options
        )
        XCTAssertTrue(result.html.contains("[[Notes]]"))
    }

    func testPlaceholderCarriesNoDiagnostics() async throws {
        let result = try await render("# fine", language: .markdown)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }
}
