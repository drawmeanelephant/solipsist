import Foundation
import XCTest

private let sampleProfileJSON = """
{
  "format": "boris-publication-profile",
  "schema_version": 1,
  "input": "content",
  "input_format": "markdown",
  "site": {
    "title": "My Great Site",
    "url": "https://example.com",
    "description": "A sample site"
  },
  "publication": {
    "target": "standard-site",
    "base_url": "https://example.standard.site",
    "origin": "https://example.standard.site",
    "base_path": "",
    "site_kind": "blog",
    "did": "did:plc:test12345",
    "pds": "https://pds.example.com",
    "name": "Site Pub",
    "description": "Publication description",
    "show_in_discover": true,
    "prune": false
  },
  "targets": [
    {
      "name": "public",
      "output": "dist/public",
      "public": true,
      "theme": "boris",
      "layout": "layouts/main.html"
    }
  ],
  "editions": {
    "ir": { "output": ".boris" },
    "rag": { "output": "rag", "scope": "docs", "split_size": 65536 },
    "context": { "output": "context", "split_size": 32768 }
  },
  "nostr": {
    "relays": ["wss://relay.damus.io"]
  }
}
"""

final class InspectorProfileTests: XCTestCase {
    func testProfile1to1Load() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-load-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Data(sampleProfileJSON.utf8).write(to: tempDir.appendingPathComponent("boris.json"))
        let loaded = try XCTUnwrap(InspectorProfile.load(from: tempDir))

        XCTAssertEqual(loaded.fields.siteTitle, "My Great Site")
        XCTAssertEqual(loaded.fields.siteURL, "https://example.com")
        XCTAssertEqual(loaded.fields.siteDescription, "A sample site")
        XCTAssertEqual(loaded.fields.input, "content")
        XCTAssertEqual(loaded.fields.inputFormat, "markdown")
        XCTAssertEqual(loaded.fields.publicationTarget, "standard-site")
        XCTAssertEqual(loaded.fields.publicationBaseURL, "https://example.standard.site")
        XCTAssertEqual(loaded.fields.publicationDid, "did:plc:test12345")
        XCTAssertEqual(loaded.fields.publicationShowInDiscover, true)
        XCTAssertEqual(loaded.fields.targets.count, 1)
        XCTAssertEqual(loaded.fields.targets[0].name, "public")
        XCTAssertEqual(loaded.fields.editions.ir?.output, ".boris")
        XCTAssertEqual(loaded.fields.editions.rag?.split_size, 65536)
    }

    func testProfile1to1SaveAndReload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let profileURL = tempDir.appendingPathComponent("boris.json")
        try Data(sampleProfileJSON.utf8).write(to: profileURL)

        let loaded = try XCTUnwrap(InspectorProfile.load(from: tempDir))
        var edited = loaded.fields
        edited.siteTitle = "Updated Site Title"
        edited.siteURL = "https://updated.example.com"
        edited.inputFormat = "cook"
        edited.publicationTarget = "github-pages"
        edited.targets.append(PublicationTarget(name: "preview", output: "dist/preview", public: false))
        edited.editions.rag?.split_size = 131_072

        try InspectorProfile.save(to: tempDir, original: loaded.data, fields: edited)
        let reloaded = try XCTUnwrap(InspectorProfile.load(from: tempDir))

        XCTAssertEqual(reloaded.fields.siteTitle, "Updated Site Title")
        XCTAssertEqual(reloaded.fields.siteURL, "https://updated.example.com")
        XCTAssertEqual(reloaded.fields.inputFormat, "cook")
        XCTAssertEqual(reloaded.fields.publicationTarget, "github-pages")
        XCTAssertEqual(reloaded.fields.targets.count, 2)
        XCTAssertEqual(reloaded.fields.targets[1].name, "preview")
        XCTAssertEqual(reloaded.fields.editions.rag?.split_size, 131_072)

        let savedData = try Data(contentsOf: profileURL)
        let json = try JSONSerialization.jsonObject(with: savedData) as? [String: Any]
        XCTAssertNotNil(json?["nostr"])
    }
}

final class InspectorExecutionAndRecipeTests: XCTestCase {
    func testExecutionKnobsDefaultsAndClamping() {
        let defaultKnobs = BorisExecutionKnobs()
        XCTAssertEqual(defaultKnobs.jobs, 1)
        XCTAssertFalse(defaultKnobs.incremental)
        XCTAssertFalse(defaultKnobs.quiet)

        let clampedLow = BorisExecutionKnobs(jobs: 0, incremental: true, quiet: true)
        XCTAssertEqual(clampedLow.jobs, 1)
        let clampedHigh = BorisExecutionKnobs(jobs: 100, incremental: false, quiet: false)
        XCTAssertEqual(clampedHigh.jobs, 64)
    }

    func testExecutionKnobsPersistenceRoundTrip() throws {
        let suiteName = "solipsist.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let knobs = BorisExecutionKnobs(jobs: 8, incremental: true, quiet: true)
        knobs.save(to: defaults)

        let loaded = BorisExecutionKnobs.load(from: defaults)
        XCTAssertEqual(loaded.jobs, 8)
        XCTAssertTrue(loaded.incremental)
        XCTAssertTrue(loaded.quiet)
    }

    func testExecutionKnobsApplyToCLIArgs() {
        let knobs = BorisExecutionKnobs(jobs: 4, incremental: true, quiet: true)
        var args = ["--input", "content"]
        knobs.apply(to: &args, defaultQuiet: false)
        XCTAssertEqual(args, ["--input", "content", "--jobs", "4", "--incremental", "--quiet"])
    }

    func testScalingIsUnavailableUntilThePinnedContractIsVerified() {
        XCTAssertFalse(RecipeScaleSupport.isAvailable)
        XCTAssertTrue(RecipeScaleSupport.unavailableMessage.contains("pinned Boris"))
    }

    func testRecipeTagsAndCookExtensionDoNotInventARecipe() {
        let node = GraphNode(
            index: 0, id: "recipe", sourcePath: "recipe.cook", role: .trunk,
            parent: nil, parentIndex: nil, title: "Recipe", status: nil, tags: ["recipe"]
        )
        XCTAssertNil(InspectorRecipe.recipe(for: node))
        XCTAssertNil(InspectorRecipe.recipe(for: nil))
        XCTAssertTrue(InspectorRecipe.unavailableMessage.contains("unavailable"))
    }

    func testEmptyRecipeFacetStaysEmpty() {
        let node = GraphNode(
            index: 0, id: "empty", sourcePath: "empty.cook", role: .trunk,
            parent: nil, parentIndex: nil, title: "Empty", status: nil, tags: [], recipe: CookRecipe()
        )
        XCTAssertEqual(InspectorRecipe.recipe(for: node), CookRecipe())
    }

    func testInspectorGraphLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recipe-test-\(UUID().uuidString)")
        let borisDir = tempDir.appendingPathComponent(".boris")
        try FileManager.default.createDirectory(at: borisDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let graphJson = """
        {
          "schemaVersion": "0.4.0",
          "frozen": true,
          "nodes": [
            {
              "index": 0,
              "id": "soup",
              "sourcePath": "soup.cook",
              "role": "trunk",
              "title": "Soup",
              "tags": ["recipe"],
              "recipe": {
                "ingredients": [
                  { "name": "water", "quantity": { "amount": "2", "unit": "cups" }, "preparation": "", "recipeRef": null }
                ],
                "cookware": [],
                "timers": []
              }
            }
          ],
          "edges": [],
          "reverseIndex": [],
          "nav": []
        }
        """
        try Data(graphJson.utf8).write(to: borisDir.appendingPathComponent("graph.json"))

        let graph = try XCTUnwrap(InspectorGraph.load(from: tempDir))
        let node = try XCTUnwrap(graph.nodes.first)
        let recipe = try XCTUnwrap(node.recipe)
        XCTAssertEqual(InspectorRecipe.recipe(for: node), recipe)
        XCTAssertEqual(recipe.ingredients[0].quantity.amount, "2", "display the authoritative graph quantity unchanged")
    }
}

final class InspectorSnapshotTests: XCTestCase {
    func testNilSourceKindProducesEmptySections() {
        let snapshot = InspectorSnapshot(sourceKind: nil, nounKind: "page", mailbox: "pages")
        XCTAssertTrue(snapshot.inspectorSections.isEmpty)
    }

    func testPagesWithPageNounShowsPageAndExecution() {
        let snapshot = InspectorSnapshot(
            sourceKind: .local,
            nounKind: "page",
            mailbox: "pages"
        )
        let ids = snapshot.inspectorSections.map(\.id)
        XCTAssertEqual(ids, [InspectorSectionID.page, InspectorSectionID.execution])
    }

    func testPagesWithoutNounShowsProfileAndExecutionForLocal() {
        let snapshot = InspectorSnapshot(
            sourceKind: .local,
            nounKind: nil,
            mailbox: "pages"
        )
        let ids = snapshot.inspectorSections.map(\.id)
        XCTAssertEqual(ids, [InspectorSectionID.profile, InspectorSectionID.execution])
    }

    func testTrunkMailboxShowsPageWhenPageSelected() {
        let snapshot = InspectorSnapshot(
            sourceKind: .local,
            nounKind: "page",
            mailbox: "trunk:guides"
        )
        let ids = snapshot.inspectorSections.map(\.id)
        XCTAssertEqual(ids, [InspectorSectionID.page, InspectorSectionID.execution])
    }

    func testTrunkMailboxShowsTrunkFilterAndProfileWithoutNoun() {
        let snapshot = InspectorSnapshot(
            sourceKind: .local,
            nounKind: nil,
            mailbox: "trunk:guides"
        )
        let sections = snapshot.inspectorSections
        XCTAssertEqual(sections.map(\.id), [InspectorSectionID.profile, InspectorSectionID.execution])
        XCTAssertEqual(sections.first?.title, "Trunk Filter & Profile")
    }

    func testOutputsWithTargetNounShowsTargetProfileExecution() {
        let snapshot = InspectorSnapshot(
            sourceKind: .local,
            nounKind: "target",
            mailbox: "outputs"
        )
        let ids = snapshot.inspectorSections.map(\.id)
        XCTAssertEqual(ids, [InspectorSectionID.target, InspectorSectionID.profile, InspectorSectionID.execution])
    }

    func testOutputsWithoutNounShowsProfileAndExecution() {
        let snapshot = InspectorSnapshot(
            sourceKind: .local,
            nounKind: nil,
            mailbox: "outputs"
        )
        let ids = snapshot.inspectorSections.map(\.id)
        XCTAssertEqual(ids, [InspectorSectionID.profile, InspectorSectionID.execution])
    }

    func testPublishMailboxShowsPublicationTargetAndExecution() {
        let snapshot = InspectorSnapshot(
            sourceKind: .local,
            nounKind: nil,
            mailbox: "publish"
        )
        let ids = snapshot.inspectorSections.map(\.id)
        XCTAssertEqual(ids, [InspectorSectionID.profile, InspectorSectionID.execution])
        XCTAssertEqual(snapshot.inspectorSections.first?.title, "Publication Target")
    }

    func testPlanActivityContentAuditShowExecutionAndProfile() {
        for box in ["plan", "activity", "content-audit"] {
            let snapshot = InspectorSnapshot(
                sourceKind: .local,
                nounKind: nil,
                mailbox: box
            )
            let ids = snapshot.inspectorSections.map(\.id)
            XCTAssertEqual(ids, [InspectorSectionID.execution, InspectorSectionID.profile])
        }
    }

    func testGithubRemoteMailboxShowsRemoteSyncExecution() {
        let snapshot = InspectorSnapshot(
            sourceKind: .github,
            nounKind: nil,
            mailbox: "remote"
        )
        let ids = snapshot.inspectorSections.map(\.id)
        XCTAssertEqual(ids, [InspectorSectionID.execution])
        XCTAssertEqual(snapshot.inspectorSections.first?.title, "Remote Sync & Execution")
    }

    func testGithubIssuesAndPullsShowGithubExecution() {
        for box in ["issues", "pulls"] {
            let snapshot = InspectorSnapshot(
                sourceKind: .github,
                nounKind: nil,
                mailbox: box
            )
            let ids = snapshot.inspectorSections.map(\.id)
            XCTAssertEqual(ids, [InspectorSectionID.execution])
            XCTAssertEqual(snapshot.inspectorSections.first?.title, "GitHub & Execution")
        }
    }
}
