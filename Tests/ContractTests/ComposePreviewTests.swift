import XCTest

final class ComposePreviewTests: XCTestCase {
    private func render(_ source: String, language: ComposeLanguage) async throws -> String {
        try await PlaceholderRenderService().render(
            source,
            language: language,
            options: MarkupRenderOptions()
        )
    }

    func testPlaceholderEscapesHTML() async throws {
        let html = try await render("<b>&\"</b>", language: .markdown)
        XCTAssertTrue(html.contains("&lt;b&gt;&amp;&quot;&lt;/b&gt;"))
        XCTAssertFalse(html.contains("<b>"))
        XCTAssertFalse(html.contains("&amp;lt;")) // no double-escape
    }

    func testPlaceholderEscapesPerLanguage() async throws {
        let markdown = try await render("1 < 2", language: .markdown)
        let textile = try await render("1 < 2", language: .textile)
        let cooklang = try await render("1 < 2", language: .cooklang)
        XCTAssertEqual(markdown, textile)
        XCTAssertEqual(markdown, cooklang)
        XCTAssertTrue(markdown.contains("&lt;"))
    }

    func testPlaceholderReplacesNUL() async throws {
        let html = try await render("a\u{0}b", language: .cooklang)
        XCTAssertTrue(html.contains("\u{FFFD}"))
        XCTAssertFalse(html.contains("\u{0}"))
    }

    func testPlaceholderIgnoresOptions() async throws {
        var options = MarkupRenderOptions()
        options.wikilinks = true
        options.profile = .xhtml
        let html = try await PlaceholderRenderService().render(
            "See [[Notes]].",
            language: .markdown,
            options: options
        )
        XCTAssertTrue(html.contains("[[Notes]]"))
    }
}
