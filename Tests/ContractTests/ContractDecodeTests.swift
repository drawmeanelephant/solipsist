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

    func testHappyTextileBuildReport() throws {
        let report = try decode(BuildReport.self, "happy-textile", "build-report.json")
        XCTAssertTrue(report.ok)
        XCTAssertEqual(report.pageCount, 2)
        XCTAssertEqual(report.errorCount, 0)
        XCTAssertTrue(report.diagnostics.isEmpty)
    }

    func testHappyTextileManifest() throws {
        let manifest = try decode(Manifest.self, "happy-textile", "manifest.json")
        XCTAssertEqual(manifest.pages.count, 2)
        XCTAssertEqual(manifest.pages.filter(\.isTrunk).count, 1)
        XCTAssertTrue(manifest.pages.allSatisfy { $0.sourcePath.hasSuffix(".textile") })
    }

    func testHappyTextileGraph() throws {
        let graph = try decode(Graph.self, "happy-textile", "graph.json")
        XCTAssertTrue(graph.frozen)
        XCTAssertEqual(graph.nodes.count, 2)
        XCTAssertTrue(graph.nodes.allSatisfy { $0.sourcePath.hasSuffix(".textile") })
        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(graph.edges.first?.kind, "parent")
    }

    func testHappyTextileCompletion() throws {
        let completion = try decode(Completion.self, "happy-textile", "completion.json")
        XCTAssertEqual(completion.format, "boris-completion-index")
        XCTAssertEqual(completion.entities.count, 2)
    }

    func testBrokenTextileReport() throws {
        let report = try decode(BuildReport.self, "broken-textile", "build-report.json")
        XCTAssertFalse(report.ok)
        XCTAssertTrue(report.diagnostics.contains { $0.code == "ETEXTILE" })
    }

    func testBrokenNullLocationsReport() throws {
        let report = try decode(BuildReport.self, "broken-null-locations", "build-report.json")
        XCTAssertFalse(report.ok)
        XCTAssertEqual(report.errorCount, 4)
        XCTAssertEqual(report.diagnostics.count, 5)

        // Diagnostic 0: ECONFIG with all null location fields
        let diag0 = report.diagnostics[0]
        XCTAssertEqual(diag0.code, "ECONFIG")
        XCTAssertNil(diag0.sourcePath)
        XCTAssertNil(diag0.line)
        XCTAssertNil(diag0.column)
        XCTAssertNil(diag0.id)

        // Diagnostic 1: EFILEACCESS with sourcePath present, null line and column
        let diag1 = report.diagnostics[1]
        XCTAssertEqual(diag1.code, "EFILEACCESS")
        XCTAssertEqual(diag1.sourcePath, "unreadable.md")
        XCTAssertNil(diag1.line)
        XCTAssertNil(diag1.column)
        XCTAssertEqual(diag1.id, "unreadable")

        // Diagnostic 2: ELINEFORMAT with sourcePath and line present, null column
        let diag2 = report.diagnostics[2]
        XCTAssertEqual(diag2.code, "ELINEFORMAT")
        XCTAssertEqual(diag2.sourcePath, "pages/overview.md")
        XCTAssertEqual(diag2.line, 12)
        XCTAssertNil(diag2.column)
        XCTAssertEqual(diag2.id, "overview")

        // Diagnostic 3: EDUPLICATEID with id present, null sourcePath/line/column
        let diag3 = report.diagnostics[3]
        XCTAssertEqual(diag3.code, "EDUPLICATEID")
        XCTAssertNil(diag3.sourcePath)
        XCTAssertNil(diag3.line)
        XCTAssertNil(diag3.column)
        XCTAssertEqual(diag3.id, "intro")

        // Diagnostic 4: WUNREFERENCED with full location
        let diag4 = report.diagnostics[4]
        XCTAssertEqual(diag4.code, "WUNREFERENCED")
        XCTAssertEqual(diag4.sourcePath, "orphan.md")
        XCTAssertEqual(diag4.line, 1)
        XCTAssertEqual(diag4.column, 1)
        XCTAssertEqual(diag4.id, "orphan")
    }

    func testHappyCheck() throws {
        let report = try decode(AnalysisReport.self, "check-happy", "analysis-report.json")
        XCTAssertEqual(report.format, "boris-analysis-report")
        XCTAssertEqual(report.schemaVersion, "0.2.0")
        XCTAssertEqual(report.summary.pages, 5)
        XCTAssertEqual(report.summary.unreferencedPages, 1)
        XCTAssertTrue(report.findings.contains { $0.code == "WUNREFERENCED" })
    }

    func testGraphDecodesRelations() throws {
        let graph = try decode(Graph.self, "happy-ir", "graph.json")
        XCTAssertEqual(graph.schemaVersion, "0.3.0")
        XCTAssertEqual(graph.relations?.count, 1)
        XCTAssertEqual(graph.relations?.first?.kind, "relates_to")
        XCTAssertEqual(graph.relations?.first?.to.value, "guides/getting-started")
    }

    func testGraphNodeDecodesRecipe() throws {
        // Synthetic IR 0.4.0 node carrying a Cooklang recipe (recipe facet).
        let json = """
        {
          "index": 0,
          "id": "soup",
          "sourcePath": "soup.cook",
          "role": "trunk",
          "parent": null,
          "parentIndex": null,
          "title": "Soup",
          "status": "published",
          "tags": ["recipe"],
          "bodyOffset": 60,
          "recipe": {
            "ingredients": [
              { "name": "water", "quantity": { "amount": "2", "unit": "cups" }, "preparation": "", "recipeRef": null }
            ],
            "cookware": [
              { "name": "skillet", "quantity": { "amount": "1", "unit": "" } }
            ],
            "timers": [
              { "name": "", "quantity": { "amount": "10", "unit": "minutes" } }
            ]
          }
        }
        """
        let node = try JSONDecoder().decode(GraphNode.self, from: Data(json.utf8))
        let recipe = try XCTUnwrap(node.recipe)
        XCTAssertEqual(recipe.ingredients.first?.name, "water")
        XCTAssertEqual(recipe.ingredients.first?.quantity.amount, "2")
        XCTAssertEqual(recipe.cookware.first?.name, "skillet")
        XCTAssertEqual(recipe.timers.first?.quantity.amount, "10")
    }

    func testAnalysisReport02FullShape() throws {
        let report = try decode(AnalysisReport.self, "check-happy", "analysis-report.json")
        XCTAssertEqual(report.schemaVersion, "0.2.0")
        XCTAssertEqual(report.summary.pages, 5)
        XCTAssertEqual(report.nodes?.count, 5)
        XCTAssertEqual(report.edges?.count, 5)
        XCTAssertEqual(report.sourceLocations?.first?.value, "orphan")
        XCTAssertEqual(report.sourceLocations?.first?.sourcePath, "orphan.md")
        XCTAssertEqual(report.diagnostics?.isEmpty, true)
    }

    func testSchemaPolicyUnknownVersion() throws {
        // D8: known IR versions classify as supported; unknown/newer degrade.
        XCTAssertEqual(ContractSchema.status(ofIR: "0.2.0"), .supported)
        XCTAssertEqual(ContractSchema.status(ofIR: "0.3.0"), .supported)
        XCTAssertEqual(ContractSchema.status(ofIR: "0.4.0"), .supported)
        XCTAssertEqual(ContractSchema.status(ofIR: "0.9.9"), .unknown("0.9.9"))
        XCTAssertEqual(ContractSchema.status(ofIR: nil), .unknown("missing"))

        // A synthetic unknown-version graph still decodes (fields optional)
        // but classifies as unknown so consumers refuse to render it.
        let json = """
        {
          "schemaVersion": "0.9.9",
          "frozen": true,
          "nodes": [],
          "edges": [],
          "reverseIndex": [],
          "nav": []
        }
        """
        let graph = try JSONDecoder().decode(Graph.self, from: Data(json.utf8))
        XCTAssertEqual(ContractSchema.status(ofIR: graph.schemaVersion), .unknown("0.9.9"))
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
                .appendingPathComponent(name)
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
