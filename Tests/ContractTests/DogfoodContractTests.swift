import XCTest

final class DogfoodContractTests: XCTestCase {
    func testDogfoodGraph45Pages7Trunks() throws {
        let graph = try decode(Graph.self, "dogfood-ir", "graph.json")
        XCTAssertTrue(graph.frozen)
        XCTAssertEqual(graph.nodes.count, 45)

        let pages = LocalPlayGraph.pages(from: graph)
        XCTAssertEqual(pages.count, 45)

        let trunkPages = pages.filter { $0.role == .trunk && $0.depth == 0 }
        XCTAssertEqual(trunkPages.count, 7)
        let trunkIDs = Set(trunkPages.map(\.id))
        XCTAssertEqual(trunkIDs, [
            "agents",
            "contest",
            "getting-started",
            "guides/apex-markdown",
            "guides/overview",
            "index",
            "reference/frontmatter",
        ])

        let satellites = pages.filter { $0.role == .satellite }
        XCTAssertEqual(satellites.count, 38)
        XCTAssertTrue(satellites.allSatisfy { $0.depth >= 1 })
    }

    func testDogfoodManifest() throws {
        let manifest = try decode(Manifest.self, "dogfood-ir", "manifest.json")
        XCTAssertEqual(manifest.pages.count, 45)
        XCTAssertEqual(manifest.pages.filter(\.isTrunk).count, 7)
    }

    func testDogfoodCompletion() throws {
        let completion = try decode(Completion.self, "dogfood-ir", "completion.json")
        XCTAssertEqual(completion.format, "boris-completion-index")
        XCTAssertEqual(completion.entities.count, 45)
        XCTAssertFalse(completion.relation_kinds.isEmpty)
        XCTAssertFalse(completion.parent_targets.isEmpty)
        XCTAssertFalse(completion.layout_slots.isEmpty)
    }

    func testDogfoodBuildReport() throws {
        let report = try decode(BuildReport.self, "dogfood-ir", "build-report.json")
        XCTAssertTrue(report.ok)
        XCTAssertEqual(report.pageCount, 45)
        XCTAssertEqual(report.errorCount, 0)
        XCTAssertTrue(report.diagnostics.isEmpty)
    }

    func testInspectorProfileLoadAndSave() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let originalProfile = """
        {
          "format": "boris-publication-profile",
          "schema_version": 1,
          "input": "content",
          "input_format": "markdown",
          "site": {
            "title": "Initial Title",
            "url": "https://example.com"
          },
          "publication": {
            "target": "github-pages"
          },
          "targets": [
            { "name": "public", "output": "dist", "public": true }
          ]
        }
        """
        let profileURL = tempDir.appendingPathComponent("boris.json")
        try Data(originalProfile.utf8).write(to: profileURL)

        guard let loaded = try InspectorProfile.load(from: tempDir) else {
            XCTFail("Failed to load profile")
            return
        }
        XCTAssertEqual(loaded.fields.siteTitle, "Initial Title")
        XCTAssertEqual(loaded.fields.siteURL, "https://example.com")
        XCTAssertEqual(loaded.fields.input, "content")
        XCTAssertEqual(loaded.fields.inputFormat, "markdown")
        XCTAssertEqual(loaded.fields.publicationTarget, "github-pages")

        var edited = loaded.fields
        edited.siteTitle = "Updated Site Title"
        edited.siteURL = "https://updated.example.com"
        edited.inputFormat = "textile"

        try InspectorProfile.save(to: tempDir, original: loaded.data, fields: edited)

        guard let reloaded = try InspectorProfile.load(from: tempDir) else {
            XCTFail("Failed to reload profile")
            return
        }
        XCTAssertEqual(reloaded.fields.siteTitle, "Updated Site Title")
        XCTAssertEqual(reloaded.fields.siteURL, "https://updated.example.com")
        XCTAssertEqual(reloaded.fields.inputFormat, "textile")
        XCTAssertEqual(reloaded.fields.publicationTarget, "github-pages")

        // Ensure untyped / unedited fields like targets array survived
        let savedData = try Data(contentsOf: profileURL)
        let json = try JSONSerialization.jsonObject(with: savedData) as? [String: Any]
        XCTAssertNotNil(json?["targets"])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ folder: String, _ name: String) throws -> T {
        let url = try fixture(folder, name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func fixture(_ folder: String, _ name: String) throws -> URL {
        let bundle = Bundle(for: DogfoodContractTests.self)
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
