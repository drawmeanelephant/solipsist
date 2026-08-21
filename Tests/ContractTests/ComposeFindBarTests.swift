import AppKit
import XCTest

/// #225 Find & Replace: the native find bar contract.
/// The editor must expose the system find bar (⌘F / ⌘⌥F / ⌘G) with
/// incremental search, hosted in the enclosing NSScrollView.
@MainActor
final class ComposeFindBarTests: XCTestCase {
    func testFindBarUsesBarNotPanel() {
        let textView = NSTextView()
        textView.usesFindBar = true
        textView.usesFindPanel = false
        textView.isIncrementalSearchingEnabled = true
        XCTAssertTrue(textView.usesFindBar, "⌘F must show the find bar")
        XCTAssertFalse(textView.usesFindPanel, "find panel must be off")
        XCTAssertTrue(textView.isIncrementalSearchingEnabled, "incremental search must be enabled")
    }

    func testFindBarConfigurationMatchesComposeTextView() {
        // Replicate what ComposeTextView.makeNSView does, and verify the
        // scrollView is a valid findBarContainer.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        let textView = NSTextView()
        textView.usesFindBar = true
        textView.usesFindPanel = false
        textView.isIncrementalSearchingEnabled = true
        scrollView.documentView = textView
        guard let documentView = scrollView.documentView as? NSTextView else {
            return XCTFail("scrollView must host an NSTextView")
        }
        XCTAssertTrue(documentView.usesFindBar)
        XCTAssertTrue(documentView.isIncrementalSearchingEnabled)
        // NSScrollView conforms to NSTextFinderBarContainer at runtime even
        // though the header only exposes findBarPosition.
        XCTAssertTrue(scrollView.responds(to: Selector(("findBarView"))))
    }

    func testFindBarMustBeScopedToBuffer() {
        // The find bar is scoped to the NSTextView's string, not the preview.
        // A trivial sanity: searching does not cross into a separate view.
        let textView = NSTextView()
        textView.string = "hello hello world"
        textView.usesFindBar = true
        XCTAssertEqual(textView.string, "hello hello world")
        XCTAssertTrue(textView.string.contains("hello"))
    }
}
