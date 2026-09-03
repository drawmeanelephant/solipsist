import XCTest

/// #297 — width-adaptive Pages split: the branch rule and the two
/// independent clamp regimes (stacked `topHeight`, wide `leftWidth`).
/// The view turns these numbers into frames; the rules live here so
/// they are pinnable without a window.
final class PagesSplitGeometryTests: XCTestCase {
    // MARK: - Branch

    func testWideBranchAtOrAboveBreakpoint() {
        XCTAssertTrue(PagesSplitGeometry.isWide(width: 720), "≥ means wide — no oscillation at exactly 720")
        XCTAssertTrue(PagesSplitGeometry.isWide(width: 1440))
    }

    func testStackedBranchBelowBreakpoint() {
        XCTAssertFalse(PagesSplitGeometry.isWide(width: 719.5))
        XCTAssertFalse(PagesSplitGeometry.isWide(width: 0))
        // A tall narrow window (half-screen on a 13" MacBook) stays
        // stacked — the breakpoint is width-only, not aspect.
        XCTAssertFalse(PagesSplitGeometry.isWide(width: 600))
    }

    func testCrossingBreakpointFlipsOnce() {
        // Dragging across 720 flips exactly once: below is stacked,
        // at-or-above is wide, and back again — no hysteresis band.
        let around = [718, 719, 720, 721, 722]
        let modes = around.map { PagesSplitGeometry.isWide(width: CGFloat($0)) }
        XCTAssertEqual(modes, [false, false, true, true, true])
    }

    // MARK: - Wide-mode clamp

    func testLeftWidthClampedBelowMinimum() {
        XCTAssertEqual(PagesSplitGeometry.clampedLeftWidth(80, totalWidth: 1200), 220)
        XCTAssertEqual(PagesSplitGeometry.clampedLeftWidth(0, totalWidth: 1200), 220)
    }

    func testLeftWidthClampedAboveLetterFloor() {
        // 1200 − 360 = 840 max list width; dragging past it holds 840.
        XCTAssertEqual(PagesSplitGeometry.clampedLeftWidth(1000, totalWidth: 1200), 840)
        XCTAssertEqual(PagesSplitGeometry.clampedLeftWidth(841, totalWidth: 1200), 840)
    }

    func testLeftWidthPassesThroughInBounds() {
        XCTAssertEqual(PagesSplitGeometry.clampedLeftWidth(280, totalWidth: 1200), 280)
        XCTAssertEqual(PagesSplitGeometry.clampedLeftWidth(500, totalWidth: 1200), 500)
    }

    func testLeftWidthWhenWindowCannotHonorBothFloors() {
        // Between the breakpoint (720) and 220 + 360 = 580… the wide
        // branch only runs ≥ 720, so both floors always fit; but a
        // pathological total just at the breakpoint still honors the
        // letter floor first: max list = 720 − 360 = 360.
        XCTAssertEqual(PagesSplitGeometry.clampedLeftWidth(280, totalWidth: 720), 280)
        XCTAssertEqual(PagesSplitGeometry.clampedLeftWidth(650, totalWidth: 720), 360)
    }

    // MARK: - Stacked-mode clamp (M10 values, unchanged)

    func testTopHeightClamped() {
        XCTAssertEqual(PagesSplitGeometry.clampedTopHeight(20, availableHeight: 800), 90)
        // 800 − 120 = 680 max; dragging past holds 680.
        XCTAssertEqual(PagesSplitGeometry.clampedTopHeight(750, availableHeight: 800), 680)
        XCTAssertEqual(PagesSplitGeometry.clampedTopHeight(200, availableHeight: 800), 200)
    }

    func testTopHeightFloorWinsWhenHeightTooSmall() {
        // A tiny available height still returns the 90 floor, never a
        // negative or letter-less layout.
        XCTAssertEqual(PagesSplitGeometry.clampedTopHeight(200, availableHeight: 100), 90)
        XCTAssertEqual(PagesSplitGeometry.clampedTopHeight(200, availableHeight: 0), 90)
    }

    // MARK: - Independence

    func testTopHeightIndependentOfLeftWidth() {
        // The two states never write each other: clamping one leaves
        // the other's clamp rule untouched (no shared mutable bound).
        let top = PagesSplitGeometry.clampedTopHeight(200, availableHeight: 800)
        let left = PagesSplitGeometry.clampedLeftWidth(280, totalWidth: 1200)
        XCTAssertEqual(top, 200)
        XCTAssertEqual(left, 280)
        // Setting a wide ratio does not alter the stacked rule and
        // vice versa — verified by re-deriving each from raw values.
        XCTAssertEqual(PagesSplitGeometry.clampedTopHeight(200, availableHeight: 800), top)
        XCTAssertEqual(PagesSplitGeometry.clampedLeftWidth(280, totalWidth: 1200), left)
    }

    func testDefaultsMatchIssueSpec() {
        XCTAssertEqual(PagesSplitGeometry.defaultLeftWidth, 280, "~280 default list width")
        XCTAssertEqual(PagesSplitGeometry.wideBreakpoint, 720, "720 breakpoint")
        XCTAssertEqual(PagesSplitGeometry.defaultTopHeight, 200, "M10 default stacked height")
    }
}
