import XCTest

/// #276 — Sidebar navigation rules: source cycling order math and the
/// trunk-filter predicate.
final class SidebarNavigationTests: XCTestCase {
    private var idA = SourceID()
    private var idB = SourceID()
    private var idC = SourceID()

    // MARK: - Source cycling

    func testCycleWalksForwardAndWraps() {
        let ids = [idA, idB, idC]
        XCTAssertEqual(
            SidebarNavigation.cycledSource(current: idA, ids: ids, forward: true), idB
        )
        XCTAssertEqual(
            SidebarNavigation.cycledSource(current: idB, ids: ids, forward: true), idC
        )
        XCTAssertEqual(
            SidebarNavigation.cycledSource(current: idC, ids: ids, forward: true), idA,
            "forward wraps to the first source"
        )
    }

    func testCycleWalksBackwardAndWraps() {
        let ids = [idA, idB, idC]
        XCTAssertEqual(
            SidebarNavigation.cycledSource(current: idC, ids: ids, forward: false), idB
        )
        XCTAssertEqual(
            SidebarNavigation.cycledSource(current: idA, ids: ids, forward: false), idC,
            "backward wraps to the last source"
        )
    }

    func testCycleWithFewerThanTwoSourcesIsNoOp() {
        XCTAssertEqual(
            SidebarNavigation.cycledSource(current: idA, ids: [idA], forward: true), idA
        )
        XCTAssertNil(
            SidebarNavigation.cycledSource(current: nil, ids: [], forward: true)
        )
    }

    func testCycleWithoutSelectionEntersAtNearEnd() {
        let ids = [idA, idB, idC]
        XCTAssertEqual(
            SidebarNavigation.cycledSource(current: nil, ids: ids, forward: true), idA,
            "forward from nothing lands on the first"
        )
        XCTAssertEqual(
            SidebarNavigation.cycledSource(current: nil, ids: ids, forward: false), idC,
            "backward from nothing lands on the last"
        )
    }

    // MARK: - Trunk filter

    func testFilterMatchesCaseInsensitiveSubstring() {
        XCTAssertTrue(SidebarNavigation.matches(filter: "guide", title: "Guides"))
        XCTAssertTrue(SidebarNavigation.matches(filter: "UIDE", title: "Guides"))
        XCTAssertFalse(SidebarNavigation.matches(filter: "recipes", title: "Guides"))
    }

    func testEmptyFilterPassesEverything() {
        XCTAssertTrue(SidebarNavigation.matches(filter: "", title: "Anything"))
        XCTAssertTrue(SidebarNavigation.matches(filter: "   ", title: "Anything"))
    }
}
