import XCTest

/// #263 — Compose formatting toolbar transforms.
///
/// Every toolbar verb compiles to a pure buffer transform derived from
/// Oliver's documented Markdown / Textile syntax. These tests pin the
/// marker tables and the selection semantics; no AppKit views involved.
final class ComposeFormatToolbarTests: XCTestCase {
    // MARK: - Harness

    /// Applies a format and returns the resulting buffer plus selection.
    private func run(
        _ format: ComposeFormat,
        on text: String,
        location: Int,
        length: Int = 0,
        language: ComposeLanguage = .markdown
    ) -> (result: String, selection: NSRange)? {
        guard
            let edit = ComposeFormat.apply(
                format, to: text,
                selectedRange: NSRange(location: location, length: length),
                language: language
            )
        else { return nil }
        let buffer = NSMutableString(string: text)
        buffer.replaceCharacters(in: edit.replacedRange, with: edit.replacement)
        return (buffer as String, edit.selection)
    }

    // MARK: - Wraps

    func testBoldWrapsSelection() throws {
        let outcome = try XCTUnwrap(run(.bold, on: "say hello now", location: 4, length: 5))
        XCTAssertEqual(outcome.result, "say **hello** now")
        XCTAssertEqual(outcome.selection, NSRange(location: 6, length: 5), "the wrapped word stays selected")
    }

    func testItalicEmptySelectionPlacesCursorInside() throws {
        let outcome = try XCTUnwrap(run(.italic, on: "word ", location: 5))
        XCTAssertEqual(outcome.result, "word **")
        XCTAssertEqual(outcome.selection, NSRange(location: 6, length: 0), "cursor sits inside the marker pair")
    }

    func testMarkdownStrikethroughUsesTildes() throws {
        let outcome = try XCTUnwrap(run(.strikethrough, on: "gone", location: 0, length: 4))
        XCTAssertEqual(outcome.result, "~~gone~~")
    }

    func testCodeSpanWrapsWithBackticks() throws {
        let outcome = try XCTUnwrap(run(.codeSpan, on: "x = 1", location: 0, length: 5))
        XCTAssertEqual(outcome.result, "`x = 1`")
    }

    // MARK: - Link

    func testLinkKeepsTextSelected() throws {
        let outcome = try XCTUnwrap(run(.link, on: "read docs", location: 5, length: 4))
        XCTAssertEqual(outcome.result, "read [docs](url)")
        XCTAssertEqual(outcome.selection, NSRange(location: 6, length: 4), "text stays selected for typing over")
    }

    func testLinkEmptySelectionInsertsPlaceholderSelected() throws {
        let outcome = try XCTUnwrap(run(.link, on: "", location: 0))
        XCTAssertEqual(outcome.result, "[text](url)")
        XCTAssertEqual(outcome.selection, NSRange(location: 1, length: 4))
    }

    func testTextileLinkUsesQuotedColonForm() throws {
        let outcome = try XCTUnwrap(run(.link, on: "see this", location: 4, length: 4, language: .textile))
        XCTAssertEqual(outcome.result, "see \"this\":url")
        XCTAssertEqual(outcome.selection, NSRange(location: 5, length: 4))
    }

    // MARK: - Line prefixes

    func testHeadingPrefixesEachSelectedLine() throws {
        let outcome = try XCTUnwrap(
            run(.heading(level: 2), on: "one\ntwo\nthree", location: 0, length: 7)
        )
        XCTAssertEqual(outcome.result, "## one\n## two\nthree")
        XCTAssertEqual(outcome.selection.location, 0, "selection maps onto the edited lines")
        XCTAssertEqual(outcome.selection.length, "## one\n## two".count)
    }

    func testHeadingReplacesExistingLevelInsteadOfStacking() throws {
        let outcome = try XCTUnwrap(run(.heading(level: 3), on: "# title", location: 3))
        XCTAssertEqual(outcome.result, "### title")
    }

    func testTextileHeadingReplacesLabel() throws {
        let outcome = try XCTUnwrap(
            run(.heading(level: 2), on: "h1. old", location: 4, language: .textile)
        )
        XCTAssertEqual(outcome.result, "h2. old")
    }

    func testNumberedListIncrementsPerLine() throws {
        let outcome = try XCTUnwrap(run(.numberedList, on: "a\nb\nc", location: 0, length: 5))
        XCTAssertEqual(outcome.result, "1. a\n2. b\n3. c")
    }

    func testTextileNumberedUsesHashPerLine() throws {
        let outcome = try XCTUnwrap(
            run(.numberedList, on: "a\nb", location: 0, length: 3, language: .textile)
        )
        XCTAssertEqual(outcome.result, "# a\n# b")
    }

    func testBulletPrefixesOnlySelectedLines() throws {
        let outcome = try XCTUnwrap(run(.bulletList, on: "keep\nmine\nkeep", location: 5, length: 4))
        XCTAssertEqual(outcome.result, "keep\n- mine\nkeep")
    }

    func testQuotePrefixesEverySelectedLine() throws {
        let outcome = try XCTUnwrap(run(.quote, on: "deep\nthoughts", location: 0, length: 12))
        XCTAssertEqual(outcome.result, "> deep\n> thoughts")
    }

    func testEmptyBufferListInsertsWithCursorAfterPrefix() throws {
        let outcome = try XCTUnwrap(run(.bulletList, on: "", location: 0))
        XCTAssertEqual(outcome.result, "- ")
        XCTAssertEqual(outcome.selection, NSRange(location: 2, length: 0))
    }

    func testCursorAtLineStartLandsAfterInsertedPrefix() throws {
        let outcome = try XCTUnwrap(run(.bulletList, on: "item", location: 0))
        XCTAssertEqual(outcome.result, "- item")
        XCTAssertEqual(outcome.selection, NSRange(location: 2, length: 0))
    }

    // MARK: - Language tables

    func testTextileMarkersDiffer() throws {
        let bold = try XCTUnwrap(run(.bold, on: "hi", location: 0, length: 2, language: .textile))
        XCTAssertEqual(bold.result, "*hi*")
        let italic = try XCTUnwrap(run(.italic, on: "hi", location: 0, length: 2, language: .textile))
        XCTAssertEqual(italic.result, "_hi_")
        let strike = try XCTUnwrap(run(.strikethrough, on: "hi", location: 0, length: 2, language: .textile))
        XCTAssertEqual(strike.result, "-hi-")
        let code = try XCTUnwrap(run(.codeSpan, on: "hi", location: 0, length: 2, language: .textile))
        XCTAssertEqual(code.result, "@hi@")
    }

    func testCooklangHasNoFormats() {
        XCTAssertFalse(ComposeLanguage.cooklang.supportsFormatting)
        XCTAssertNil(ComposeFormat.apply(.bold, to: "sugar", selectedRange: NSRange(location: 0, length: 5), language: .cooklang))
        XCTAssertTrue(ComposeLanguage.markdown.supportsFormatting)
        XCTAssertTrue(ComposeLanguage.textile.supportsFormatting)
    }

    func testStaleSelectionBeyondBufferIsClamped() throws {
        let outcome = try XCTUnwrap(run(.bold, on: "tiny", location: 900, length: 900))
        XCTAssertEqual(outcome.result, "tiny****")
        XCTAssertEqual(outcome.selection, NSRange(location: 6, length: 0))
    }

    // MARK: - Preview options reset (#263 popover)

    func testPreviewOptionsResetRestoresDefaults() {
        var mutated = MarkupRenderOptions()
        mutated.wikilinks = true
        mutated.taskLists = true
        mutated.frontmatter = .toml
        mutated.rawHTML = .rejected
        mutated.profile = .xhtml
        XCTAssertNotEqual(mutated, MarkupRenderOptions())

        // What the Reset button assigns.
        let reset = MarkupRenderOptions()
        XCTAssertEqual(reset.profile, .html)
        XCTAssertEqual(reset.rawHTML, .allowed)
        XCTAssertEqual(reset.frontmatter, .none)
        for enabled in [
            reset.wikilinks, reset.callouts, reset.smartypants, reset.footnotes,
            reset.definitionLists, reset.headingAttributes, reset.strikethrough,
            reset.headingIDs, reset.taskLists,
        ] {
            XCTAssertFalse(enabled, "every Markdown extension stays off by default")
        }
    }
}
