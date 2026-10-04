import XCTest

final class SpikePolicyTests: XCTestCase {
    private func graph(ids: [String]) -> Graph {
        let nodes = ids.enumerated().map { index, id in
            GraphNode(
                index: index, id: id, sourcePath: "\(id).md", role: .trunk,
                parent: nil, parentIndex: nil, title: id, status: nil, tags: []
            )
        }
        return Graph(schemaVersion: "0.4.0", frozen: true, nodes: nodes, edges: [], reverseIndex: [], nav: [])
    }

    func testDefaultImpactComesFromTheReturnedGraph() throws {
        for id in ["getting-started", "guides/getting-started", "another-publication/home"] {
            XCTAssertEqual(try SpikePolicy.impactTarget(in: graph(ids: [id]), requested: nil), id)
        }
    }

    func testExplicitPageMustExistInTheSuppliedGraph() throws {
        let corpus = graph(ids: ["index", "guides/getting-started"])
        XCTAssertEqual(try SpikePolicy.impactTarget(in: corpus, requested: "guides/getting-started"), "guides/getting-started")
        XCTAssertThrowsError(try SpikePolicy.impactTarget(in: corpus, requested: "getting-started")) { error in
            XCTAssertEqual(SpikePolicy.exitCode(for: error), 2)
            XCTAssertTrue(String(describing: error).contains("guides/getting-started"))
        }
    }

    func testEmptyAndMissingGraphsAreControlledFailures() {
        XCTAssertThrowsError(try SpikePolicy.impactTarget(in: graph(ids: []), requested: nil)) { error in
            XCTAssertEqual(SpikePolicy.exitCode(for: error), 1)
            XCTAssertTrue(String(describing: error).contains("no pages"))
        }
        XCTAssertThrowsError(try SpikePolicy.impactTarget(in: nil, requested: nil)) { error in
            XCTAssertEqual(SpikePolicy.exitCode(for: error), 3)
            XCTAssertTrue(String(describing: error).contains("graph.json"))
        }
    }

    func testNonzeroExitKeepsItsCodeAndDiagnostics() throws {
        try SpikePolicy.requireSuccess(0, command: "impact")
        for code: Int32 in [1, 2, 3, 71] {
            XCTAssertThrowsError(try SpikePolicy.requireSuccess(code, command: "impact", stderr: "useful engine error")) { error in
                XCTAssertEqual(SpikePolicy.exitCode(for: error), code)
                XCTAssertTrue(String(describing: error).contains("useful engine error"))
            }
        }
    }

    func testMissingReportRetainsTheEngineFailureAndOutput() {
        let failure = BorisAnalysisFailure(
            command: "impact", exitCode: 2, reportError: "missing impact report",
            stdout: "command output", stderr: "unknown page"
        )
        XCTAssertEqual(SpikePolicy.exitCode(for: failure), 2)
        XCTAssertTrue(failure.description.contains("unknown page"))
        XCTAssertTrue(failure.description.contains("command output"))
        XCTAssertTrue(failure.description.contains("missing impact report"))
    }

    func testExitZeroWithBadReportCannotBecomeSuccess() {
        let failure = BorisAnalysisFailure(
            command: "impact", exitCode: 0, reportError: "malformed JSON", stdout: "", stderr: "decode detail"
        )
        XCTAssertEqual(SpikePolicy.exitCode(for: failure), 3)
        XCTAssertEqual(SpikePolicy.exitCode(for: CocoaError(.fileReadNoSuchFile)), 3)
    }
}
