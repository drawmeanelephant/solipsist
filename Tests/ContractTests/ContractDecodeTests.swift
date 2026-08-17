import XCTest

final class ContractDecodeTests: XCTestCase {
    func testHappyIRBuildReport() throws {
        let report = try decode(BuildReport.self, "happy-ir", "build-report.json")
        XCTAssertTrue(report.schemaVersion.hasPrefix("0."))
        XCTAssertTrue(report.ok)
        XCTAssertEqual(report.pageCount, 3)
        XCTAssertEqual(report.errorCount, 0)
        XCTAssertTrue(report.diagnostics.isEmpty)
    }

    func testHappyManifest() throws {
        let manifest = try decode(Manifest.self, "happy-ir", "manifest.json")
        XCTAssertEqual(manifest.pages.count, 3)
        XCTAssertEqual(manifest.pages.filter(\.isTrunk).count, 1)
    }

    func testHappyGraph() throws {
        let graph = try decode(Graph.self, "happy-ir", "graph.json")
        XCTAssertTrue(graph.frozen)
        XCTAssertEqual(graph.nodes.count, 3)
        XCTAssertFalse(graph.edges.isEmpty)
    }

    func testHappyCompletion() throws {
        let completion = try decode(Completion.self, "happy-ir", "completion.json")
        XCTAssertEqual(completion.format, "boris-completion-index")
        XCTAssertEqual(completion.schema_version, 1)
        XCTAssertEqual(completion.entities.count, 3)
    }

    func testHappyValidateReport() throws {
        let report = try decode(HTMLBuildReport.self, "validate-happy", "html-build-report.json")
        XCTAssertTrue(report.ok)
        XCTAssertEqual(report.schemaVersion, "html-build-report-0.1.0")
    }

    func testHappyPlan() throws {
        let plan = try decode(PublicationPlan.self, "plan-happy", "plan.json")
        XCTAssertEqual(plan.format, "boris-publication-plan")
        XCTAssertEqual(plan.targets?.count, 1)
    }

    func testBrokenFrontmatterReport() throws {
        let report = try decode(BuildReport.self, "broken-frontmatter", "build-report.json")
        XCTAssertFalse(report.ok)
        XCTAssertTrue(report.diagnostics.contains { $0.code == "EFRONTMATTER" })
    }

    func testBrokenParentReport() throws {
        let report = try decode(BuildReport.self, "broken-parent", "build-report.json")
        XCTAssertFalse(report.ok)
        XCTAssertTrue(report.diagnostics.contains { $0.code == "EPARENTMISSING" })
    }

    func testBrokenDuplicateIDReport() throws {
        let report = try decode(BuildReport.self, "broken-duplicate-id", "build-report.json")
        XCTAssertFalse(report.ok)
        XCTAssertTrue(report.diagnostics.contains { $0.code == "EDUPLICATEID" })
    }

    func testBrokenWikilinkReport() throws {
        let report = try decode(BuildReport.self, "broken-wikilink", "build-report.json")
        XCTAssertFalse(report.ok)
        XCTAssertTrue(report.diagnostics.contains { $0.code == "EREFERENCEMISSING" })
    }

    func testHappyCheck() throws {
        let report = try decode(AnalysisReport.self, "check-happy", "analysis-report.json")
        XCTAssertEqual(report.format, "boris-analysis-report")
        XCTAssertEqual(report.summary.pages, 45)
        XCTAssertEqual(report.summary.roots, 7)
        XCTAssertTrue(report.findings.contains { $0.code == "WUNREFERENCED" })
    }

    private func decode<T: Decodable>(_ type: T.Type, _ folder: String, _ name: String) throws -> T {
        let url = try fixture(folder, name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func fixture(_ folder: String, _ name: String) throws -> URL {
        let bundle = Bundle(for: ContractDecodeTests.self)
        let candidates = [
            bundle.url(forResource: name, withExtension: nil, subdirectory: folder),
            bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/\(folder)"),
            bundle.resourceURL?
                .appendingPathComponent("Fixtures", isDirectory: true)
                .appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent(name),
            bundle.resourceURL?
                .appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent(name),
        ]
        if let url = candidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) {
            return url
        }
        XCTFail("missing fixture \(folder)/\(name) in \(bundle.resourceURL?.path ?? "?")")
        throw NSError(domain: "fixtures", code: 1)
    }
}
