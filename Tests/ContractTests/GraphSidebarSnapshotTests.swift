import XCTest

/// #275 — Live sidebar: the one-pass snapshot that feeds trunk rows and
/// counts without re-walking the graph per render.
final class GraphSidebarSnapshotTests: XCTestCase {
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

    func testSnapshotCountsEachTrunkInOnePass() {
        let snap = LocalPlayGraph.snapshot(from: graph(nodes: [
            node(index: 0, id: "index", role: .trunk, parent: nil, title: "Home"),
            node(index: 1, id: "guides", role: .trunk, parent: nil, title: "Guides"),
            node(index: 2, id: "guides/intro", role: .satellite, parent: "guides", title: "Intro"),
            node(index: 3, id: "guides/advanced", role: .satellite, parent: "guides", title: "Advanced"),
            node(index: 4, id: "recipes", role: .trunk, parent: nil, title: "Recipes"),
            node(index: 5, id: "recipes/pancakes", role: .satellite, parent: "recipes", title: "Pancakes"),
            node(index: 6, id: "orphan", role: .satellite, parent: "missing", title: "Orphan"),
        ]))

        XCTAssertEqual(snap.pageCount, 7)
        XCTAssertEqual(snap.trunks.map(\.id), ["index", "guides", "recipes"])
        XCTAssertEqual(snap.countsByTrunk["guides"], 3, "trunk row + two satellites")
        XCTAssertEqual(snap.countsByTrunk["recipes"], 2)
        XCTAssertEqual(snap.countsByTrunk["index"], 1)
        XCTAssertNil(snap.countsByTrunk["orphan"], "orphans belong to no trunk")
    }

    func testEmptyGraphGivesEmptySnapshot() {
        XCTAssertEqual(LocalPlayGraph.snapshot(from: graph(nodes: [])), .empty)
        XCTAssertEqual(LocalPlayGraph.snapshot(from: graph(nodes: [])).countsByTrunk, [:])
    }

    func testSatellitesWithoutTrunkParentsAreNotFolders() {
        let snap = LocalPlayGraph.snapshot(from: graph(nodes: [
            node(index: 0, id: "lone", role: .satellite, parent: nil, title: "Lone"),
        ]))
        XCTAssertTrue(snap.trunks.isEmpty)
        XCTAssertEqual(snap.pageCount, 1)
        XCTAssertTrue(snap.countsByTrunk.isEmpty)
    }
}
