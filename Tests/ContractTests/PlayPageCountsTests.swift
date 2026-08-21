import XCTest

/// A11Y-5 (#243): the sidebar's announced item counts derive from the
/// same graph walk the Pages / trunk letter lists use, so the numbers
/// VoiceOver announces always agree with what the list shows.
final class PlayPageCountsTests: XCTestCase {
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
        parent: String?
    ) -> GraphNode {
        GraphNode(
            index: index,
            id: id,
            sourcePath: id + ".md",
            role: role,
            parent: parent,
            parentIndex: nil,
            title: id,
            status: "published",
            tags: []
        )
    }

    func testCountsMatchFullPageAndTrunkLists() {
        let graph = graph(nodes: [
            node(index: 0, id: "index", role: .trunk, parent: nil),
            node(index: 1, id: "guides", role: .trunk, parent: nil),
            node(index: 2, id: "guides/intro", role: .satellite, parent: "guides"),
            node(index: 3, id: "orphan", role: .satellite, parent: nil),
        ])

        let counts = LocalPlayGraph.counts(from: graph)

        // Pages row always means all pages.
        XCTAssertEqual(counts.pages, 4)
        // Trunk counts only include the trunk rows the sidebar shows
        // (trunk roots), matching the M13-2 filter: trunk + satellites.
        XCTAssertEqual(counts.trunkCounts["index"], 1)
        XCTAssertEqual(counts.trunkCounts["guides"], 2)
        XCTAssertNil(counts.trunkCounts["orphan"])
    }

    func testEmptyGraphHasZeroCounts() {
        let counts = LocalPlayGraph.counts(from: graph(nodes: []))
        XCTAssertEqual(counts.pages, 0)
        XCTAssertTrue(counts.trunkCounts.isEmpty)
    }

    func testSatelliteRootNotCountedAsTrunk() {
        let graph = graph(nodes: [
            node(index: 0, id: "index", role: .trunk, parent: nil),
            node(index: 1, id: "orphan", role: .satellite, parent: nil),
        ])

        let counts = LocalPlayGraph.counts(from: graph)
        XCTAssertEqual(counts.pages, 2)
        XCTAssertEqual(counts.trunkCounts, ["index": 1])
        XCTAssertNil(counts.trunkCounts["orphan"])
    }
}