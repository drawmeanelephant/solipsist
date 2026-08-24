import XCTest

/// #274 — Sidebar expansion persistence. The tree shape (collapsed
/// sources, per-source Pages disclosures) survives relaunch via one
/// UserDefaults payload; rules + codec are pinned here.
@MainActor
final class SidebarExpansionStateTests: XCTestCase {
    private var suiteName: String { "sidebar-expansion-\(UUID().uuidString)" }
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

    func testCollapseExpandRoundTrip() {
        let defaults = makeDefaults()
        let id = SourceID()

        var payload = SidebarExpansionState.load(defaults: defaults)
        XCTAssertFalse(SidebarExpansionState.isCollapsed(payload, id: id), "everything starts expanded")

        payload = SidebarExpansionState.collapsing(payload, id: id)
        XCTAssertTrue(SidebarExpansionState.isCollapsed(payload, id: id))
        SidebarExpansionState.save(payload, defaults: defaults)

        let reloaded = SidebarExpansionState.load(defaults: defaults)
        XCTAssertTrue(SidebarExpansionState.isCollapsed(reloaded, id: id), "collapse survives a reload")
    }

    func testExpandingRemovesCollapseEntry() {
        let id = SourceID()
        var payload = SidebarExpansionState.Payload()
        payload = SidebarExpansionState.collapsing(payload, id: id)
        payload = SidebarExpansionState.expanding(payload, id: id)
        XCTAssertFalse(SidebarExpansionState.isCollapsed(payload, id: id))
    }

    func testPagesDisclosurePersistsPerSource() {
        let defaults = makeDefaults()
        let sourceA = SourceID()
        let sourceB = SourceID()

        var payload = SidebarExpansionState.load(defaults: defaults)
        XCTAssertTrue(SidebarExpansionState.pagesExpanded(payload, id: sourceA), "default is expanded")
        XCTAssertEqual(
            SidebarExpansionState.pagesExpanded(payload, id: sourceA),
            SidebarExpansionState.pagesExpanded(payload, id: sourceB),
            "both sources default the same"
        )

        payload = SidebarExpansionState.settingPages(payload, id: sourceA, expanded: false)
        SidebarExpansionState.save(payload, defaults: defaults)

        let reloaded = SidebarExpansionState.load(defaults: defaults)
        XCTAssertFalse(SidebarExpansionState.pagesExpanded(reloaded, id: sourceA))
        XCTAssertTrue(
            SidebarExpansionState.pagesExpanded(reloaded, id: sourceB),
            "source B keeps the default"
        )
    }

    func testMissingOrGarbagePayloadMeansAllExpanded() {
        let defaults = makeDefaults()
        XCTAssertEqual(
            SidebarExpansionState.load(defaults: defaults),
            SidebarExpansionState.Payload(),
            "no key → everything expanded"
        )
        defaults.set(Data("not json".utf8), forKey: SidebarExpansionState.defaultsKey)
        XCTAssertEqual(
            SidebarExpansionState.load(defaults: defaults),
            SidebarExpansionState.Payload(),
            "undecodable payload degrades to the default shape, never an error"
        )
    }
}
