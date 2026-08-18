import XCTest

final class ComposeLanguageTests: XCTestCase {
    // MARK: - Extension detection

    func testMarkdownExtensions() {
        for ext in ["md", "markdown", "mdown"] {
            let url = URL(fileURLWithPath: "/tmp/doc.\(ext)")
            XCTAssertEqual(
                ComposeLanguage.detect(fileURL: url, contents: ""),
                .markdown,
                "extension .\(ext) should select markdown"
            )
        }
    }

    func testTextileExtension() {
        let url = URL(fileURLWithPath: "/tmp/doc.textile")
        XCTAssertEqual(ComposeLanguage.detect(fileURL: url, contents: ""), .textile)
    }

    func testCooklangExtensions() {
        for ext in ["cook", "menu"] {
            let url = URL(fileURLWithPath: "/tmp/recipe.\(ext)")
            XCTAssertEqual(
                ComposeLanguage.detect(fileURL: url, contents: ""),
                .cooklang,
                "extension .\(ext) should select cooklang"
            )
        }
    }

    // MARK: - Content sniffing (no extension)

    func testSniffCooklangIngredient() {
        let text = "Add @salt{1%tsp} and @ground black pepper{} to the pot.\n"
        XCTAssertEqual(ComposeLanguage.detect(fileURL: nil, contents: text), .cooklang)
    }

    func testSniffCooklangSection() {
        let text = "= Stew\n\nSimmer for ~{25%minutes}.\n"
        XCTAssertEqual(ComposeLanguage.detect(fileURL: nil, contents: text), .cooklang)
    }

    func testSniffTextileHeading() {
        XCTAssertEqual(
            ComposeLanguage.detect(fileURL: nil, contents: "h1. The Title\n\nBody text."),
            .textile
        )
    }

    func testSniffTextileSignature() {
        XCTAssertEqual(
            ComposeLanguage.detect(fileURL: nil, contents: "p. A styled paragraph\n\nMore."),
            .textile
        )
    }

    func testSniffMarkdownHeading() {
        XCTAssertEqual(
            ComposeLanguage.detect(fileURL: nil, contents: "# Title\n\nSome *body*."),
            .markdown
        )
    }

    func testSniffEmptyFallsBackToMarkdown() {
        XCTAssertEqual(ComposeLanguage.detect(fileURL: nil, contents: ""), .markdown)
    }

    func testSniffPlainProseFallsBackToMarkdown() {
        XCTAssertEqual(ComposeLanguage.detect(fileURL: nil, contents: "Just words."), .markdown)
    }

    // MARK: - Frontend surface

    func testDisplayNames() {
        XCTAssertEqual(ComposeLanguage.markdown.displayName, "Markdown")
        XCTAssertEqual(ComposeLanguage.textile.displayName, "Textile")
        XCTAssertEqual(ComposeLanguage.cooklang.displayName, "Cooklang")
    }

    func testConformanceNotesReferenceOliverWalls() {
        XCTAssertTrue(ComposeLanguage.markdown.conformanceNote.contains("652/652"))
        XCTAssertTrue(ComposeLanguage.cooklang.conformanceNote.contains("60/60"))
    }

    func testAllLanguagesSupportFrontmatter() {
        for language in ComposeLanguage.allCases {
            XCTAssertTrue(language.supportsFrontmatter)
        }
    }
}
