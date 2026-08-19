import XCTest

/// M13-2 (#146): a trunk mailbox filters the letter list to that folder;
/// Pages still means all pages.
final class FilterLettersTests: XCTestCase {
    private func graph(nodes: [GraphNode]) -> Graph {
        Graph(
            schemaVersion: "0.3.0",
            frozen: true,
            nodes: nodes,
            edges: [],
            reverseIndex: [],
            nav: []
        )
    }

    private func node(
        index: Int,
        id: String,
        role: PageRole,
        parent: String?,
        title: String
    ) -> GraphNode {
        GraphNode(
            index: index,
            id: id,
            sourcePath: id + ".md",
            role: role,
            parent: parent,
            parentIndex: nil,
            title: title,
            status: "published",
            tags: []
        )
    }

    /// The card's fixture: trunk + child + unrelated trunk.
    private var threeNodeGraph: Graph {
        graph(nodes: [
            node(index: 0, id: "index", role: .trunk, parent: nil, title: "Home"),
            node(index: 1, id: "index/child", role: .satellite, parent: "index", title: "Child"),
            node(index: 2, id: "guides", role: .trunk, parent: nil, title: "Guides"),
        ])
    }

    func testPagesStillReturnsAllThree() {
        let pages = LocalPlayGraph.pages(from: threeNodeGraph)
        XCTAssertEqual(pages.map(\.id), ["index", "index/child", "guides"])
    }

    func testTrunkFilterKeepsTrunkAndDescendants() {
        let pages = LocalPlayGraph.pages(from: threeNodeGraph)
        let filtered = LocalPlayGraph.pages(in: pages, trunkID: "index")
        XCTAssertEqual(filtered.map(\.id), ["index", "index/child"])
        // The unrelated trunk is not part of this folder.
        XCTAssertFalse(filtered.contains { $0.id == "guides" })
        XCTAssertEqual(filtered.map(\.trunkID), ["index", "index"])
        XCTAssertEqual(filtered.map(\.depth), [0, 1])
    }

    func testGrandchildChainIsIncluded() {
        let graph = graph(nodes: [
            node(index: 0, id: "trunk", role: .trunk, parent: nil, title: "Trunk"),
            node(index: 1, id: "trunk/a", role: .satellite, parent: "trunk", title: "A"),
            node(index: 2, id: "trunk/a/b", role: .satellite, parent: "trunk/a", title: "B"),
        ])
        let filtered = LocalPlayGraph.pages(
            in: LocalPlayGraph.pages(from: graph),
            trunkID: "trunk"
        )
        XCTAssertEqual(filtered.map(\.id), ["trunk", "trunk/a", "trunk/a/b"])
        XCTAssertEqual(filtered.map(\.depth), [0, 1, 2])
        XCTAssertEqual(filtered.map(\.trunkID), ["trunk", "trunk", "trunk"])
    }

    func testMissingTrunkIsEmptyNotFallthrough() {
        let pages = LocalPlayGraph.pages(from: threeNodeGraph)
        // Stale id — the graph no longer contains it. Empty is honest.
        XCTAssertTrue(LocalPlayGraph.pages(in: pages, trunkID: "stale").isEmpty)
    }

    func testOrphanSatelliteIsInNoTrunkFolder() {
        let graph = graph(nodes: [
            node(index: 0, id: "index", role: .trunk, parent: nil, title: "Home"),
            node(index: 1, id: "orphan", role: .satellite, parent: nil, title: "Orphan"),
        ])
        let pages = LocalPlayGraph.pages(from: graph)
        // Present in the full list, absent from the trunk folder.
        XCTAssertEqual(pages.map(\.id), ["index", "orphan"])
        XCTAssertEqual(LocalPlayGraph.pages(in: pages, trunkID: "index").map(\.id), ["index"])
    }
}
