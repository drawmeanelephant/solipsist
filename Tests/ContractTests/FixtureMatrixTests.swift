import XCTest

/// #214 fix(contracts): pinned fixture matrix completeness.
/// Harvested from bf464a0 via scripts/harvest-stunt-fixtures.sh — never hand-edited.
/// Covers TimingsReport, buildTarget/timings shape, Profile editions
/// scope/split_size, html-build-report failure dual, ValidateWatch NDJSON
/// mode:validate, dogfood 45 pages/7 trunks gate, and D8 safe-decode.
final class FixtureMatrixTests: XCTestCase {
    // MARK: - Timings (IR + HTML)

    func testHappyIRTimingsDecodes() throws {
        let report = try decode(TimingsReport.self, "timings", "happy-ir-timings.json")
        XCTAssertEqual(report.format, "boris-timings")
        XCTAssertEqual(report.schemaVersion, "1")
        XCTAssertEqual(report.mode, "ir")
        XCTAssertNotNil(report.phases?["scan"])
        XCTAssertNotNil(report.phases?["parse"])
        XCTAssertEqual(report.counters?.page_reads, 3)
        XCTAssertNotNil(report.totalNs)
        XCTAssertGreaterThan(report.totalNs ?? 0, 0)
    }

    func testDogfoodIRTimingsDecodes() throws {
        let report = try decode(TimingsReport.self, "timings", "dogfood-ir-timings.json")
        XCTAssertEqual(report.mode, "ir")
        XCTAssertEqual(report.counters?.page_reads, 45)
        XCTAssertGreaterThan(report.phases?.count ?? 0, 2)
    }

    func testHappyHTMLTimingsDecodes() throws {
        let report = try decode(TimingsReport.self, "timings", "happy-html-timings.json")
        XCTAssertEqual(report.mode, "html")
        // HTML mode has additional phases beyond IR: render, search, link_audit, etc.
        XCTAssertNotNil(report.phases?["render"])
        XCTAssertNotNil(report.phases?["search"])
        XCTAssertEqual(report.counters?.page_reads, 9)
    }

    // MARK: - HTML build report failure (dual diagnostics, nullable location)

    func testValidateFailureHTMLReportDualDiagnostics() throws {
        let report = try decode(HTMLBuildReport.self, "validate-failure", "html-build-report.json")
        XCTAssertFalse(report.ok)
        XCTAssertEqual(report.schemaVersion, "html-build-report-0.1.0")
        XCTAssertEqual(report.errorCount, 2)
        XCTAssertEqual(report.diagnostics.count, 2)
        // First diagnostic is graph-level with null location
        XCTAssertNil(report.diagnostics[0].sourcePath)
        XCTAssertNil(report.diagnostics[0].line)
        XCTAssertEqual(report.diagnostics[0].code, "EIO")
        // Second is located
        XCTAssertEqual(report.diagnostics[1].sourcePath, "page.md")
        XCTAssertEqual(report.diagnostics[1].line, 6)
        XCTAssertEqual(report.diagnostics[1].code, "EREFERENCEMISSING")
    }

    // MARK: - Plan with editions scope/split_size

    func testPlanEditionsScopeAndSplitSize() throws {
        let plan = try decode(PublicationPlan.self, "plan-editions", "plan.json")
        XCTAssertEqual(plan.format, "boris-publication-plan")
        let editions = try XCTUnwrap(plan.editions)
        XCTAssertEqual(editions.ir?.output, ".boris")
        XCTAssertEqual(editions.rag?.output, "rag")
        XCTAssertEqual(editions.rag?.scope, "guides")
        XCTAssertEqual(editions.rag?.split_size, 262_144)
        XCTAssertEqual(editions.context?.output, "context")
        XCTAssertEqual(editions.context?.scope, "reference")
        XCTAssertEqual(editions.context?.split_size, 131_072)
        // PublicationProfile round-trips the same shape
        let profileJSON = """
        {
          "format": "boris-publication-profile",
          "schema_version": 1,
          "input": "content",
          "targets": [{ "name": "public", "output": "dist", "public": true }],
          "editions": {
            "ir": { "output": ".boris" },
            "rag": { "output": "rag", "scope": "guides", "split_size": 262144, "bundles_only": true },
            "context": { "output": "context", "scope": "ref", "split_size": 65536 }
          }
        }
        """
        let profile = try JSONDecoder().decode(PublicationProfile.self, from: Data(profileJSON.utf8))
        XCTAssertEqual(profile.editions?.rag?.bundles_only, true)
        XCTAssertEqual(profile.editions?.context?.split_size, 65536)
    }

    // MARK: - ValidateWatch NDJSON mode:validate

    func testValidateWatchNDJSONModeValidate() throws {
        let url = try fixture("validate-watch", "validate-watch.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertGreaterThan(lines.count, 2)
        // First line must be hello with schema 1
        let hello = try XCTUnwrap(WatchEvent.decode(line: lines[0]))
        guard case .hello(let schema, _) = hello else { return XCTFail("first event not hello") }
        XCTAssertEqual(schema, 1)
        // Subsequent lines include build-started/succeeded with mode validate
        let joined = lines.joined(separator: "\n")
        XCTAssertTrue(joined.contains("\"mode\":\"validate\""))
        XCTAssertTrue(joined.contains("build-started") || joined.contains("build-succeeded"))
        // Parser should consume the stream without crash and surface a hello-gated outcome
        var parser = WatchStreamParser()
        for line in lines {
            parser.consume(line: line)
        }
        XCTAssertNotNil(parser.buildOutcome)
    }

    // MARK: - D8 safe-decode (unknown schemaVersion never crashes)

    func testD8UnknownIRVersionDecodesButIsUnknown() throws {
        let graph = try decode(Graph.self, "happy-ir", "graph.json")
        XCTAssertEqual(ContractSchema.status(ofIR: graph.schemaVersion), .supported)
        // Synthetic unknown version
        let unknownJSON = """
        {
          "schemaVersion": "9.9.9",
          "frozen": true,
          "nodes": [],
          "edges": [],
          "reverseIndex": [],
          "nav": []
        }
        """
        let unknown = try JSONDecoder().decode(Graph.self, from: Data(unknownJSON.utf8))
        XCTAssertEqual(ContractSchema.status(ofIR: unknown.schemaVersion), .unknown("9.9.9"))
    }

    func testD8UnknownTimingsVersionDegrades() throws {
        let json = """
        {
          "format": "boris-timings",
          "schemaVersion": "99",
          "mode": "ir",
          "phases": {},
          "counters": {},
          "totalNs": 1
        }
        """
        let report = try JSONDecoder().decode(TimingsReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.schemaVersion, "99") // decodes, but caller must check ContractSchema
    }

    func testDogfoodGate45Pages7TrunksStillHolds() throws {
        let graph = try decode(Graph.self, "dogfood-ir", "graph.json")
        XCTAssertEqual(graph.nodes.count, 45)
        let trunks = graph.nodes.filter { $0.role == .trunk && $0.parent == nil }
        // LocalPlayGraph depth 0 trunks are the mailboxes; graph.trunk nodes may include nested trunks,
        // but the expected 7 root trunks lives in the relation parent == nil check.
        // The stricter gate is in DogfoodContractTests; here we assert the fixture was not truncated.
        XCTAssertEqual(graph.nodes.count, 45)
        XCTAssertGreaterThanOrEqual(trunks.count, 7)
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, _ folder: String, _ name: String) throws -> T {
        let url = try fixture(folder, name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func fixture(_ folder: String, _ name: String) throws -> URL {
        let bundle = Bundle(for: FixtureMatrixTests.self)
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
        if let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return url
        }
        XCTFail("missing fixture \(folder)/\(name) in \(bundle.resourceURL?.path ?? "?")")
        throw NSError(domain: "fixtures", code: 1)
    }
}
