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

    func testRecipeScaleHelperAmountMath() {
        XCTAssertEqual(RecipeScaleHelper.parseAmount("2"), 2.0)
        XCTAssertEqual(RecipeScaleHelper.parseAmount("1/2"), 0.5)
        XCTAssertEqual(RecipeScaleHelper.parseAmount("2 1/2"), 2.5)
        XCTAssertNil(RecipeScaleHelper.parseAmount("pinch"))

        XCTAssertEqual(RecipeScaleHelper.formatAmount(4.0), "4")
        XCTAssertEqual(RecipeScaleHelper.formatAmount(0.5), "1/2")
        XCTAssertEqual(RecipeScaleHelper.formatAmount(1.5), "1 1/2")
    }

    func testRecipeScaleHelperScaling() {
        let recipe = CookRecipe(
            ingredients: [
                CookIngredient(name: "water", quantity: CookQuantity(amount: "2", unit: "cups")),
                CookIngredient(name: "salt", quantity: CookQuantity(amount: "1/2", unit: "tsp"))
            ],
            cookware: [CookCookware(name: "pot", quantity: CookQuantity(amount: "1", unit: ""))],
            timers: [CookTimer(name: "boil", quantity: CookQuantity(amount: "5", unit: "min"))]
        )

        let scaled = RecipeScaleHelper.scale(recipe: recipe, factor: 2.0)
        XCTAssertEqual(scaled.ingredients[0].quantity.amount, "4")
        XCTAssertEqual(scaled.ingredients[1].quantity.amount, "1")
        XCTAssertEqual(scaled.cookware[0].name, "pot")
        XCTAssertEqual(scaled.timers[0].quantity.amount, "5")
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
        let scaled = RecipeScaleHelper.scale(recipe: recipe, factor: 3.0)
        XCTAssertEqual(scaled.ingredients[0].quantity.amount, "6")
    }
}
