import XCTest

/// M13-1 (#145): trunk extraction for the sidebar's Pages children.
final class GraphTrunksTests: XCTestCase {
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

    func testTrunksExtraction() {
        let graph = graph(nodes: [
            node(index: 0, id: "index", role: .trunk, parent: nil, title: "Home"),
            node(index: 1, id: "guides", role: .trunk, parent: nil, title: "Guides"),
            node(index: 2, id: "guides/intro", role: .satellite, parent: "guides", title: "Introduction"),
            node(index: 3, id: "orphan", role: .satellite, parent: nil, title: "Orphan"),
        ])

        // Trunk roots only — satellites (children or rootless) are not folders.
        let trunks = LocalPlayGraph.trunks(from: graph)
        XCTAssertEqual(trunks.map(\.id), ["index", "guides"])
        XCTAssertEqual(trunks.map(\.depth), [0, 0])
        XCTAssertEqual(trunks.map(\.title), ["Home", "Guides"])
        XCTAssertTrue(trunks.allSatisfy { $0.role == .trunk })
    }

    func testEmptyGraphHasNoTrunks() {
        XCTAssertTrue(LocalPlayGraph.trunks(from: graph(nodes: [])).isEmpty)
    }
}
