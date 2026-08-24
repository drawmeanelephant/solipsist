import AppKit
import XCTest

/// #264 — Compose reading comfort: the type-size ladder (⌘+/⌘−/⌘0), its
/// UserDefaults persistence, and the gutter toggle's padding collapse.
@MainActor
final class ComposeReadingComfortTests: XCTestCase {
    private var suiteName: String { "compose-typography-\(UUID().uuidString)" }
    private var suites: [String] = []

    private func makeDefaults() -> UserDefaults {
        let name = suiteName
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func tearDown() {
        for name in suites {
            UserDefaults().removePersistentDomain(forName: name)
        }
        suites.removeAll()
    }

    // MARK: - Size ladder

    func testFontSizeStepsClampAtBounds() {
        let typography = ComposeTypography(defaults: makeDefaults())
        XCTAssertEqual(typography.size, 13)

        // Walk up to the ceiling.
        for _ in 0..<20 {
            typography.zoomIn()
        }
        XCTAssertEqual(typography.size, 21, "the ladder clamps at 21")

        // Walk down to the floor.
        for _ in 0..<30 {
            typography.zoomOut()
        }
        XCTAssertEqual(typography.size, 11, "the ladder clamps at 11")
    }

    func testActualSizeRestoresDefault() {
        let typography = ComposeTypography(defaults: makeDefaults())
        typography.zoomIn()
        typography.zoomIn()
        XCTAssertEqual(typography.size, 15)

        typography.resetToActualSize()
        XCTAssertEqual(typography.size, 13)
        XCTAssertEqual(typography.font.pointSize, 13)
    }

    func testStoredSizeIsClampedAndPersisted() {
        let defaults = makeDefaults()
        defaults.set(99.0, forKey: ComposeTypography.sizeStorageKey)
        XCTAssertEqual(ComposeTypography(defaults: defaults).size, 21)

        defaults.set(2.0, forKey: ComposeTypography.sizeStorageKey)
        XCTAssertEqual(ComposeTypography(defaults: defaults).size, 11)

        let typography = ComposeTypography(defaults: defaults)
        typography.zoomIn()
        XCTAssertEqual(
            defaults.double(forKey: ComposeTypography.sizeStorageKey), 12,
            "size changes persist to machine state"
        )
    }

    // MARK: - Gutter toggle

    func testLineNumbersDefaultOnAndPersist() {
        let defaults = makeDefaults()
        XCTAssertTrue(ComposeTypography(defaults: defaults).showsLineNumbers)

        let typography = ComposeTypography(defaults: defaults)
        typography.setLineNumbers(false)
        XCTAssertFalse(ComposeTypography(defaults: defaults).showsLineNumbers)
    }

    func testGutterToggleCollapsesPadding() {
        let coordinator = ComposeTextView.Coordinator(document: ComposeDocument(text: "a\nb\nc"))
        let textView = NSTextView()
        coordinator.textView = textView
        coordinator.hostedTextView = textView

        let gutter = ComposeLineGutter()
        gutter.textView = textView
        coordinator.gutter = gutter

        // Visible: reserved padding tracks the gutter width.
        coordinator.showsLineNumbers = true
        coordinator.updateGutterWidth()
        coordinator.applyGutterVisibility()
        XCTAssertFalse(gutter.isHidden)
        XCTAssertGreaterThanOrEqual(textView.textContainer?.lineFragmentPadding ?? 0, 36)

        // Hidden: digits gone and the reserved padding collapses to the
        // base inset.
        coordinator.showsLineNumbers = false
        coordinator.updateGutterWidth()
        coordinator.applyGutterVisibility()
        XCTAssertTrue(gutter.isHidden)
        XCTAssertEqual(textView.textContainer?.lineFragmentPadding, 5)
    }

    // MARK: - Paragraph spacing

    func testParagraphStyleCarriesLineSpacing() {
        let typography = ComposeTypography(defaults: makeDefaults())
        XCTAssertEqual(typography.paragraphStyle.lineSpacing, 4)
    }
}
