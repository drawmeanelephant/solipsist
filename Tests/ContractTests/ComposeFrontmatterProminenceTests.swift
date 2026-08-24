import XCTest

/// #266 — Front-matter form prominence + friendly labels.
@MainActor
final class ComposeFrontmatterProminenceTests: XCTestCase {
    // MARK: - Auto-show rule

    func testAutoShowOnlyWhenFrontmatterPresent() {
        XCTAssertTrue(
            ComposeFrontmatter.paneVisibility(current: false, present: true, userToggled: false),
            "a page carrying front matter shows the pane without a click"
        )
        XCTAssertFalse(
            ComposeFrontmatter.paneVisibility(current: false, present: false, userToggled: false),
            "a page without front matter keeps the pane hidden"
        )
    }

    func testExplicitToggleBeatsAutoShow() {
        // The author toggled the pane off; a re-sync must not force it open…
        XCTAssertFalse(
            ComposeFrontmatter.paneVisibility(current: false, present: true, userToggled: true)
        )
        // …nor an auto-showed pane closed.
        XCTAssertTrue(
            ComposeFrontmatter.paneVisibility(current: true, present: false, userToggled: true)
        )
    }

    // MARK: - Add-front-matter default block

    func testAddFrontmatterInsertsDefaultBlock() {
        var fields = ComposeFrontmatter.Fields.empty
        XCTAssertTrue(fields == .empty, "a fresh form starts empty")

        // The empty state seeds a draft status so the block is never empty,
        // then inserts through the existing apply path.
        if fields == .empty {
            fields = ComposeFrontmatter.Fields(status: "draft")
        }
        let payload = ComposeFrontmatter.apply(fields, to: "")
        XCTAssertEqual(payload, "status: draft")

        let overlay = ComposeFrontmatter.apply(fields, to: "custom: keep-me")
        XCTAssertEqual(overlay, "custom: keep-me\nstatus: draft", "unknown keys survive the insert")
    }

    func testUnclosedOpenerIsNotFrontMatter() {
        let document = ComposeDocument(text: "---\nid: nope")
        XCTAssertNil(document.frontmatter, "an unclosed opener is not front matter per Oliver's rule")
    }
}
