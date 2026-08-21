import XCTest

/// #228 Status bar — cursor + word/char counts.
@MainActor
final class ComposeStatusBarTests: XCTestCase {
    func testWordCountEmptyShowsZero() {
        let doc = ComposeDocument(text: "", language: .markdown)
        XCTAssertEqual(doc.wordCount, 0)
        XCTAssertEqual(doc.characterCount, 0)
        XCTAssertTrue(doc.wordCountText.contains("0 words"))
        XCTAssertTrue(doc.characterCountText.contains("0 chars"))
    }

    func testWordCountUpdatesOnInsert() {
        let doc = ComposeDocument(text: "hello", language: .markdown)
        XCTAssertEqual(doc.wordCount, 1)
        doc.text = "hello world"
        XCTAssertEqual(doc.wordCount, 2)
        doc.text = "hello   world" // multiple spaces
        XCTAssertEqual(doc.wordCount, 2, "consecutive spaces must not create extra words")
    }

    func testWordCountHandlesPunctuationAndHyphens() {
        let doc = ComposeDocument(text: "well-known trait", language: .markdown)
        // NSString .byWords may count hyphenated as one or two; we just verify it is at least 2
        XCTAssertGreaterThanOrEqual(doc.wordCount, 2)
        doc.text = "don't count"
        XCTAssertEqual(doc.wordCount, 2)
    }

    func testWordCountHandlesMultipleSpacesAndNewlines() {
        let doc = ComposeDocument(text: "one  two\nthree\tfour", language: .markdown)
        XCTAssertEqual(doc.wordCount, 4)
    }

    func testCharacterCountAndSelected() {
        let doc = ComposeDocument(text: "hello", language: .markdown)
        XCTAssertEqual(doc.characterCount, 5)
        XCTAssertTrue(doc.characterCountText.contains("5 chars"))
        doc.updateCursor(NSRange(location: 1, length: 2))
        XCTAssertEqual(doc.selectedLength, 2)
        XCTAssertTrue(doc.characterCountText.contains("2 selected"))
        doc.updateCursor(NSRange(location: 0, length: 0))
        XCTAssertEqual(doc.selectedLength, 0)
        XCTAssertTrue(doc.characterCountText.contains("5 chars"))
    }

    func testCursorLineColumnStart() {
        let doc = ComposeDocument(text: "first\nsecond\nthird", language: .markdown)
        doc.updateCursor(NSRange(location: 0, length: 0))
        XCTAssertEqual(doc.cursorLine, 1)
        XCTAssertEqual(doc.cursorColumn, 1)
        XCTAssertEqual(doc.cursorText, "Ln 1, Col 1")
    }

    func testCursorPositionUpdatesOnNavigation() {
        let doc = ComposeDocument(text: "a\nbb\nccc", language: .markdown)
        // "a" line1, "\n" at 1, "bb" line2 starts at 2, "ccc" line3 starts at 5
        doc.updateCursor(NSRange(location: 2, length: 0)) // start of line 2
        XCTAssertEqual(doc.cursorLine, 2)
        XCTAssertEqual(doc.cursorColumn, 1)
        doc.updateCursor(NSRange(location: 3, length: 0)) // second char of line 2
        XCTAssertEqual(doc.cursorLine, 2)
        XCTAssertEqual(doc.cursorColumn, 2)
        doc.updateCursor(NSRange(location: 5, length: 0)) // start of line 3
        XCTAssertEqual(doc.cursorLine, 3)
        XCTAssertEqual(doc.cursorColumn, 1)
    }

    func testCursorPositionAtEndOfLine() {
        let doc = ComposeDocument(text: "hello", language: .markdown)
        doc.updateCursor(NSRange(location: 5, length: 0)) // after "hello"
        XCTAssertEqual(doc.cursorLine, 1)
        XCTAssertEqual(doc.cursorColumn, 6)
    }

    func testCursorTrailingNewLineCreatesNewLine() {
        let doc = ComposeDocument(text: "a\n", language: .markdown)
        doc.updateCursor(NSRange(location: 2, length: 0)) // after trailing \n
        XCTAssertEqual(doc.cursorLine, 2)
        XCTAssertEqual(doc.cursorColumn, 1)
        XCTAssertEqual(doc.cursorText, "Ln 2, Col 1")
    }

    func testCursorHandlesCRLF() {
        let doc = ComposeDocument(text: "a\r\nb", language: .markdown)
        // \r\n is one line break; "a" line1, "b" line2
        // Location 3 is 'b' start (0:a,1:\r,2:\n,3:b)
        doc.updateCursor(NSRange(location: 3, length: 0))
        XCTAssertEqual(doc.cursorLine, 2)
        XCTAssertEqual(doc.cursorColumn, 1)
    }

    func testCursorEmptyBuffer() {
        let doc = ComposeDocument(text: "", language: .markdown)
        doc.updateCursor(NSRange(location: 0, length: 0))
        XCTAssertEqual(doc.cursorLine, 1)
        XCTAssertEqual(doc.cursorColumn, 1)
    }

    func testLoadResetsCursor() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-status-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        try "hello\nworld".write(to: url, atomically: true, encoding: .utf8)
        let doc = ComposeDocument(text: "old", language: .markdown)
        doc.updateCursor(NSRange(location: 2, length: 0))
        XCTAssertEqual(doc.cursorLine, 1)
        try doc.load(from: url)
        XCTAssertEqual(doc.cursorLine, 1)
        XCTAssertEqual(doc.cursorColumn, 1)
        XCTAssertEqual(doc.selectedLength, 0)
    }
}
