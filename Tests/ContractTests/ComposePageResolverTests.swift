import XCTest

final class ComposePageResolverTests: XCTestCase {
    private let sampleGraphJSON = """
    {
      "schemaVersion": "ir-graph-0.3.0",
      "frozen": true,
      "nodes": [
        {
          "index": 0,
          "id": "index",
          "sourcePath": "index.md",
          "role": "trunk",
          "parent": null,
          "parentIndex": null,
          "title": "Index",
          "status": null,
          "tags": [],
          "bodyOffset": null
        },
        {
          "index": 1,
          "id": "guides/getting-started",
          "sourcePath": "guides/getting-started.md",
          "role": "satellite",
          "parent": "index",
          "parentIndex": 0,
          "title": "Getting Started",
          "status": "draft",
          "tags": ["guide"],
          "bodyOffset": 120
        }
      ],
      "edges": [],
      "reverseIndex": [],
      "nav": []
    }
    """

    func testGraphURLShape() {
        let root = URL(fileURLWithPath: "/tmp/proj")
        XCTAssertEqual(
            ComposePageResolver.graphURL(workspaceRoot: root).path,
            "/tmp/proj/.boris/graph.json"
        )
    }

    func testFileURLJoinsContentRootAndSourcePath() {
        let contentRoot = URL(fileURLWithPath: "/tmp/proj/content")
        XCTAssertEqual(
            ComposePageResolver.fileURL(contentRoot: contentRoot, sourcePath: "guides/getting-started.md").path,
            "/tmp/proj/content/guides/getting-started.md"
        )
    }

    func testPageLookupById() throws {
        let graph = try JSONDecoder().decode(Graph.self, from: Data(sampleGraphJSON.utf8))
        let node = try XCTUnwrap(ComposePageResolver.page(id: "guides/getting-started", in: graph))
        XCTAssertEqual(node.sourcePath, "guides/getting-started.md")
        XCTAssertEqual(node.title, "Getting Started")
        XCTAssertEqual(node.status, "draft")
    }

    func testPageLookupMissReturnsNil() throws {
        let graph = try JSONDecoder().decode(Graph.self, from: Data(sampleGraphJSON.utf8))
        XCTAssertNil(ComposePageResolver.page(id: "no-such-page", in: graph))
    }

    func testPageLookupThroughGraphFile() throws {
        let workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-resolver-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let boris = workspaceRoot.appendingPathComponent(".boris", isDirectory: true)
        try FileManager.default.createDirectory(at: boris, withIntermediateDirectories: true)
        try Data(sampleGraphJSON.utf8).write(to: ComposePageResolver.graphURL(workspaceRoot: workspaceRoot))

        let node = try XCTUnwrap(
            ComposePageResolver.page(id: "index", workspaceRoot: workspaceRoot)
        )
        XCTAssertEqual(node.sourcePath, "index.md")
    }
}
