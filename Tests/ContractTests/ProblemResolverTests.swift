import XCTest

final class ProblemResolverTests: XCTestCase {
    private var sampleGraph: Graph {
        Graph(
            schemaVersion: "0.4.0",
            frozen: true,
            nodes: [
                GraphNode(
                    index: 0,
                    id: "index",
                    sourcePath: "index.md",
                    role: .trunk,
                    parent: nil,
                    parentIndex: nil,
                    title: "Home",
                    status: "published",
                    tags: nil
                ),
                GraphNode(
                    index: 1,
                    id: "about-team",
                    sourcePath: "about/team.md",
                    role: .satellite,
                    parent: "index",
                    parentIndex: 0,
                    title: "Our Team",
                    status: "draft",
                    tags: nil
                )
            ],
            edges: [],
            reverseIndex: [],
            nav: []
        )
    }

    func testExactMatchResolvesToPage() {
        let resolution = ProblemResolver.resolve(
            path: "index.md",
            source: nil,
            graph: sampleGraph
        )
        XCTAssertEqual(resolution, .page(id: "index", title: "Home"))
    }

    func testNestedPathResolvesToPage() {
        let resolution = ProblemResolver.resolve(
            path: "about/team.md",
            source: nil,
            graph: sampleGraph
        )
        XCTAssertEqual(resolution, .page(id: "about-team", title: "Our Team"))
    }

    func testPathWithLeadingSlashResolvesToPage() {
        let resolution = ProblemResolver.resolve(
            path: "/about/team.md",
            source: nil,
            graph: sampleGraph
        )
        XCTAssertEqual(resolution, .page(id: "about-team", title: "Our Team"))
    }

    func testNonGraphFileResolvesToRevealFileWithoutInventingId() {
        let resolution = ProblemResolver.resolve(
            path: "/path/to/project/boris.json",
            source: nil,
            graph: sampleGraph
        )
        XCTAssertEqual(
            resolution,
            .revealFile(url: URL(fileURLWithPath: "/path/to/project/boris.json"))
        )
    }

    func testUnknownRelativePathWithoutSourceFallsBackGracefully() {
        let resolution = ProblemResolver.resolve(
            path: "unknown.md",
            source: nil,
            graph: sampleGraph
        )
        XCTAssertNil(resolution)
    }

    func testEmptyPathResolvesToNil() {
        let resolution = ProblemResolver.resolve(
            path: "   ",
            source: nil,
            graph: sampleGraph
        )
        XCTAssertNil(resolution)
    }
}
