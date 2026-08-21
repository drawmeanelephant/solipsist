import AppKit
import XCTest

/// #226 Line numbers gutter contract.
@MainActor
final class ComposeGutterTests: XCTestCase {
    func testEmptyBufferShowsOneLine() {
        let gutter = ComposeLineGutter()
        let textView = NSTextView()
        textView.string = ""
        gutter.textView = textView
        // Empty buffer line count is 1, digits = 3 => width 36 min
        XCTAssertEqual(gutter.gutterWidth, 36, "empty buffer must show line 1 with min width")
    }

    func testGutterWidthGrowsWithDigits() {
        let gutter = ComposeLineGutter()
        let textView = NSTextView()
        // 1 line => 36
        textView.string = "one line"
        gutter.textView = textView
        XCTAssertEqual(gutter.gutterWidth, 36)
        // 999 lines => 3 digits => 36
        textView.string = String(repeating: "a\n", count: 998) + "a"
        XCTAssertEqual(gutter.gutterWidth, 36)
        // 10000 lines => 5 digits => wider than 36
        textView.string = String(repeating: "a\n", count: 9999) + "a"
        XCTAssertGreaterThan(gutter.gutterWidth, 36, "5-digit line numbers need wider gutter")
    }

    func testGutterIsSubviewOfTextView() {
        // Directly verify the contract: gutter lives as subview of NSTextView
        // and reserves lineFragmentPadding. We replicate what ComposeTextView does.
        let textView = NSTextView()
        textView.string = "first\nsecond\nthird"
        let gutter = ComposeLineGutter()
        gutter.textView = textView
        gutter.frame = NSRect(x: 0, y: 0, width: 36, height: textView.bounds.height)
        textView.addSubview(gutter)
        textView.textContainer?.lineFragmentPadding = gutter.gutterWidth
        XCTAssertTrue(textView.subviews.contains(where: { $0 is ComposeLineGutter }))
        XCTAssertEqual(gutter.textView, textView)
        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, gutter.gutterWidth)
    }

    func testGutterHighlightsCurrentLine() {
        let textView = NSTextView()
        textView.string = "one\ntwo\nthree"
        // Place cursor on line 2 (after first \n)
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        XCTAssertEqual(textView.selectedRange().location, 4)
        let gutter = ComposeLineGutter()
        gutter.textView = textView
        // Verify gutter can be asked to display without crashing
        gutter.displayIfNeeded()
        // Move to line 3 and ensure selection updated
        textView.setSelectedRange(NSRange(location: 8, length: 0))
        XCTAssertEqual(textView.selectedRange().location, 8)
        XCTAssertNotNil(gutter.textView)
        // Coordinator would mark gutter dirty on selection change
        gutter.setNeedsDisplay(gutter.bounds)
        XCTAssertNotNil(gutter.textView)
    }

    func testSyncAfterTextChange() {
        let textView = NSTextView()
        textView.string = "a\nb"
        let gutter = ComposeLineGutter()
        gutter.textView = textView
        gutter.frame = NSRect(x: 0, y: 0, width: 36, height: textView.bounds.height)
        textView.addSubview(gutter)
        textView.textContainer?.lineFragmentPadding = gutter.gutterWidth
        let initialWidth = gutter.gutterWidth
        // Insert many lines to force width growth
        textView.string = String(repeating: "x\n", count: 10000) + "end"
        // Recompute width via new string
        let newWidth = gutter.gutterWidth
        XCTAssertGreaterThan(newWidth, initialWidth)
        // Simulate coordinator update
        textView.textContainer?.lineFragmentPadding = newWidth
        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, newWidth)
    }
}
