import AppKit
import XCTest

@MainActor
final class ComposeHighlighterTests: XCTestCase {
    // MARK: - Markdown

    func testMarkdownHeadingPainted() {
        let attributed = ComposeHighlighter.highlight("# Title", language: .markdown)
        XCTAssertEqual(color(at: 1, in: attributed), NSColor.systemPurple)
        XCTAssertEqual(color(at: 4, in: attributed), NSColor.systemPurple)
    }

    func testMarkdownSevenHashesIsNotHeading() {
        let attributed = ComposeHighlighter.highlight("####### not a heading", language: .markdown)
        XCTAssertEqual(color(at: 1, in: attributed), NSColor.labelColor)
    }

    func testMarkdownLinkPainted() {
        let attributed = ComposeHighlighter.highlight("See [the docs](https://x.dev).", language: .markdown)
        XCTAssertEqual(color(at: 5, in: attributed), NSColor.systemBlue)
    }

    func testMarkdownImagePaintedOverLink() {
        let attributed = ComposeHighlighter.highlight("![alt](img.png)", language: .markdown)
        XCTAssertEqual(color(at: 0, in: attributed), NSColor.systemTeal)
        XCTAssertEqual(color(at: 7, in: attributed), NSColor.systemTeal)
    }

    func testMarkdownCodeSpanPainted() {
        let attributed = ComposeHighlighter.highlight("Use `print(x)` now.", language: .markdown)
        XCTAssertEqual(color(at: 5, in: attributed), NSColor.systemGreen)
    }

    func testMarkdownFencedCodeRegionPaintedLast() throws {
        let text = "# Outer heading\n```\n# not a heading\n```\n"
        let attributed = ComposeHighlighter.highlight(text, language: .markdown)
        // The `#` inside the fence must stay code-colored, not heading-colored.
        let fenceContent = try XCTUnwrap(text.range(of: "# not a heading"))
        let location = text.distance(from: text.startIndex, to: fenceContent.lowerBound)
        XCTAssertEqual(color(at: location, in: attributed), NSColor.systemGreen)
    }

    func testMarkdownWikilinkPainted() {
        let attributed = ComposeHighlighter.highlight("See [[Notes|the note]].", language: .markdown)
        XCTAssertEqual(color(at: 5, in: attributed), NSColor.systemTeal)
    }

    func testMarkdownCalloutPainted() {
        let attributed = ComposeHighlighter.highlight("> [!note] Heads up\n> body", language: .markdown)
        XCTAssertEqual(color(at: 3, in: attributed), NSColor.systemYellow)
    }

    func testMarkdownTaskListPainted() {
        let attributed = ComposeHighlighter.highlight("- [x] done\n- [ ] todo", language: .markdown)
        XCTAssertEqual(color(at: 2, in: attributed), NSColor.systemGreen)
    }

    func testMarkdownFrontmatterPaintedLast() throws {
        let text = "---\n# a yaml comment\n---\n# Real heading"
        let attributed = ComposeHighlighter.highlight(text, language: .markdown)
        // The `#` inside frontmatter must stay gray (data, not content)…
        XCTAssertEqual(color(at: 5, in: attributed), NSColor.systemGray)
        // …while the heading after the fence is purple.
        let heading = try XCTUnwrap(text.range(of: "# Real"))
        let headingStart = text.distance(from: text.startIndex, to: heading.lowerBound)
        XCTAssertEqual(color(at: headingStart + 1, in: attributed), NSColor.systemPurple)
    }

    // MARK: - Textile

    func testTextileSignaturePainted() {
        let attributed = ComposeHighlighter.highlight("h1. The Title", language: .textile)
        XCTAssertEqual(color(at: 0, in: attributed), NSColor.systemPurple)
        XCTAssertEqual(color(at: 2, in: attributed), NSColor.systemPurple)
    }

    func testTextileCodePainted() {
        let attributed = ComposeHighlighter.highlight("Use @code@ here.", language: .textile)
        XCTAssertEqual(color(at: 5, in: attributed), NSColor.systemGreen)
    }

    func testTextilePhrasePainted() {
        let attributed = ComposeHighlighter.highlight("A **strong** phrase.", language: .textile)
        XCTAssertEqual(color(at: 4, in: attributed), NSColor.systemRed)
    }

    func testTextileEmphasisPainted() {
        let attributed = ComposeHighlighter.highlight("An *em* phrase.", language: .textile)
        XCTAssertEqual(color(at: 4, in: attributed), NSColor.systemOrange)
    }

    func testTextileLinkPainted() {
        let attributed = ComposeHighlighter.highlight("\"the docs\":https://x.dev", language: .textile)
        XCTAssertEqual(color(at: 1, in: attributed), NSColor.systemBlue)
    }

    func testTextileImagePainted() {
        let attributed = ComposeHighlighter.highlight("!img.png!", language: .textile)
        XCTAssertEqual(color(at: 1, in: attributed), NSColor.systemTeal)
    }

    func testTextileTableRowPainted() {
        let attributed = ComposeHighlighter.highlight("|a|b|", language: .textile)
        XCTAssertEqual(color(at: 0, in: attributed), NSColor.systemTeal)
    }

    // MARK: - Cooklang

    func testCooklangIngredientPainted() {
        let attributed = ComposeHighlighter.highlight("Add @salt{1%tsp}.", language: .cooklang)
        XCTAssertEqual(color(at: 5, in: attributed), NSColor.systemGreen)
        XCTAssertEqual(color(at: 9, in: attributed), NSColor.systemGreen)
    }

    func testCooklangMultiWordIngredientPainted() {
        let attributed = ComposeHighlighter.highlight("Add @ground black pepper{}.", language: .cooklang)
        // The second word of the braced name is still the ingredient.
        XCTAssertEqual(color(at: 12, in: attributed), NSColor.systemGreen)
    }

    func testCooklangCookwarePainted() {
        let attributed = ComposeHighlighter.highlight("Use #frying pan{2}.", language: .cooklang)
        XCTAssertEqual(color(at: 5, in: attributed), NSColor.systemBlue)
    }

    func testCooklangTimerPainted() {
        let attributed = ComposeHighlighter.highlight("Cook ~{25%minutes}.", language: .cooklang)
        XCTAssertEqual(color(at: 6, in: attributed), NSColor.systemOrange)
    }

    func testCooklangNamedTimerPainted() {
        let attributed = ComposeHighlighter.highlight("Rest ~dough{10%minutes}.", language: .cooklang)
        XCTAssertEqual(color(at: 6, in: attributed), NSColor.systemOrange)
    }

    func testCooklangSectionPainted() {
        let attributed = ComposeHighlighter.highlight("= Ingredients", language: .cooklang)
        XCTAssertEqual(color(at: 0, in: attributed), NSColor.systemPurple)
    }

    func testCooklangNotePainted() {
        let attributed = ComposeHighlighter.highlight("> Do not skip this.", language: .cooklang)
        XCTAssertEqual(color(at: 2, in: attributed), NSColor.systemTeal)
    }

    func testCooklangCommentPainted() {
        let attributed = ComposeHighlighter.highlight("-- a comment\nAdd @salt{}", language: .cooklang)
        XCTAssertEqual(color(at: 2, in: attributed), NSColor.secondaryLabelColor)
    }

    func testCooklangTokenInsideCommentStaysComment() {
        let attributed = ComposeHighlighter.highlight("-- add @salt here", language: .cooklang)
        XCTAssertEqual(color(at: 8, in: attributed), NSColor.secondaryLabelColor)
    }

    // MARK: - Incremental repaint (LATER-3.2)

    func testChangedRangeInsertion() {
        let range = ComposeHighlighter.changedRange(old: "hello world", new: "hello big world")
        XCTAssertEqual(range.location, 6)
        XCTAssertEqual(range.length, 4) // "big "
    }

    func testChangedRangeDeletion() {
        let range = ComposeHighlighter.changedRange(old: "hello big world", new: "hello world")
        XCTAssertEqual(range.location, 6)
        XCTAssertEqual(range.length, 0)
    }

    func testChangedRangeReplacement() {
        let range = ComposeHighlighter.changedRange(old: "abc", new: "axc")
        XCTAssertEqual(range.location, 1)
        XCTAssertEqual(range.length, 1)
    }

    func testChangedRangeNoChange() {
        let range = ComposeHighlighter.changedRange(old: "same", new: "same")
        XCTAssertEqual(range.location, 4)
        XCTAssertEqual(range.length, 0)
    }

    func testRepaintLineMatchesFullPaint() throws {
        let text = "# Title\n\nSome **bold** and `code`.\n\n# Later\n"
        let full = ComposeHighlighter.highlight(text, language: .markdown)
        let storage = baseStorage(text)
        // Repaint only the bold/code line.
        let line = try XCTUnwrap(text.range(of: "Some **bold** and `code`."))
        let location = text.utf16.distance(from: text.startIndex, to: line.lowerBound)
        let length = text.utf16.distance(from: line.lowerBound, to: line.upperBound)
        let target = NSRange(location: location, length: length)
        ComposeHighlighter.repaint(text, language: .markdown, in: target, storage: storage)
        for offset in 0..<length {
            XCTAssertEqual(
                color(at: target.location + offset, in: storage),
                color(at: target.location + offset, in: full),
                "offset \(offset)"
            )
        }
        // Bold painted by the incremental path too.
        let boldStart = try XCTUnwrap(text.range(of: "**bold**"))
        let boldOffset = text.utf16.distance(from: text.startIndex, to: boldStart.lowerBound) + 2
        XCTAssertEqual(color(at: boldOffset, in: storage), NSColor.systemRed)
    }

    func testRepaintLeavesOutsideRangeUntouched() throws {
        let text = "# Title\n\nSome **bold**.\n"
        let storage = baseStorage(text)
        let target = (text as NSString).lineRange(for: NSRange(location: 0, length: 1))
        ComposeHighlighter.repaint(text, language: .markdown, in: target, storage: storage)
        // The bold line was never repainted: still plain base color.
        let boldStart = try XCTUnwrap(text.range(of: "**bold**"))
        let boldOffset = text.utf16.distance(from: text.startIndex, to: boldStart.lowerBound) + 2
        XCTAssertEqual(color(at: boldOffset, in: storage), NSColor.labelColor)
    }

    func testRepaintFrontmatterLineMatchesFullPaint() throws {
        let text = "---\ntitle: x\n---\n\n# Body\n"
        let full = ComposeHighlighter.highlight(text, language: .markdown)
        let storage = baseStorage(text)
        let target = (text as NSString).lineRange(for: NSRange(location: 0, length: 1))
        ComposeHighlighter.repaint(text, language: .markdown, in: target, storage: storage)
        XCTAssertEqual(color(at: 1, in: storage), color(at: 1, in: full))
        XCTAssertEqual(color(at: 1, in: storage), NSColor.systemGray)
    }

    // MARK: - Helpers

    private func color(at location: Int, in attributed: NSAttributedString) -> NSColor? {
        guard location < attributed.length else { return nil }
        return attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    private func baseStorage(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }
}
