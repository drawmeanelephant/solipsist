import Foundation
import XCTest

/// Contract for LATER-3.4's Cooklang completion: vocabulary sourced only
/// from `.boris/graph.json` recipe IR facets + `.boris/completion.json`
/// entities, and the marker scanner that opens the popup.
final class ComposeCookCompletionTests: XCTestCase {
    // MARK: - Load

    func testLoadCollectsRecipeFacetsAndEntities() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let completion = ComposeCookCompletion.load(workspaceRoot: root)
        XCTAssertEqual(completion.ingredients, ["salt", "soup", "water"])
        XCTAssertEqual(completion.cookware, ["pot"])
        XCTAssertEqual(completion.timers, ["5"])
        XCTAssertEqual(completion.entityIDs, ["broth", "soup"])
    }

    func testLoadMissingArtifactsDegradesToEmpty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let completion = ComposeCookCompletion.load(workspaceRoot: root)
        XCTAssertTrue(completion.isEmpty)
    }

    func testLoadMalformedGraphContributesOnlyCompletion() throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let boris = root.appendingPathComponent(".boris", isDirectory: true)
        try "not json".write(
            to: boris.appendingPathComponent("graph.json"),
            atomically: true,
            encoding: .utf8
        )
        let completion = ComposeCookCompletion.load(workspaceRoot: root)
        XCTAssertTrue(completion.ingredients.isEmpty)
        XCTAssertEqual(completion.entityIDs, ["broth", "soup"])
    }

    // MARK: - Suggestions

    func testIngredientSuggestions() {
        let vocab = ComposeCookCompletion(ingredients: ["salt", "water", "water"], cookware: ["pot"], timers: ["5"], entityIDs: ["soup"])
        XCTAssertEqual(vocab.suggestions(marker: "@", prefix: "wa"), ["water"])
        XCTAssertEqual(vocab.suggestions(marker: "@", prefix: "WA"), ["water"])
        // Sorted + deduped, and entity ids join the `@` pool (recipe refs).
        XCTAssertEqual(vocab.suggestions(marker: "@", prefix: ""), ["salt", "soup", "water"])
    }

    func testCookwareAndTimerSuggestions() {
        let vocab = ComposeCookCompletion(ingredients: ["water"], cookware: ["pot", "pan"], timers: ["5", "step"], entityIDs: [])
        XCTAssertEqual(vocab.suggestions(marker: "#", prefix: "p"), ["pan", "pot"])
        XCTAssertEqual(vocab.suggestions(marker: "~", prefix: "s"), ["step"])
    }

    func testUnknownMarkerAndEmptyPrefixReturnNothing() {
        let vocab = ComposeCookCompletion(ingredients: ["water"], cookware: [], timers: [], entityIDs: [])
        XCTAssertTrue(vocab.suggestions(marker: "$", prefix: "").isEmpty)
        XCTAssertTrue(ComposeCookCompletion.empty.suggestions(marker: "@", prefix: "").isEmpty)
        XCTAssertTrue(vocab.suggestions(marker: "@", prefix: "zz").isEmpty)
    }

    func testSuggestionsCapped() {
        let many = (0..<60).map { index in "item\(index)" }
        let vocab = ComposeCookCompletion(ingredients: many, cookware: [], timers: [], entityIDs: [])
        XCTAssertEqual(vocab.suggestions(marker: "@", prefix: "item").count, 25)
    }

    // MARK: - Marker scanner

    func testInsertedMarkerDetectsSingleTypedMarker() {
        XCTAssertEqual(CookMarkerScanner.insertedMarker(from: "Mix @wa", to: "Mix @wat"), nil)
        XCTAssertEqual(CookMarkerScanner.insertedMarker(from: "Mix wa", to: "Mix wa@"), "@")
        XCTAssertEqual(CookMarkerScanner.insertedMarker(from: "Mix wa", to: "Mix wa#"), "#")
        XCTAssertEqual(CookMarkerScanner.insertedMarker(from: "Mix wa", to: "Mix wa~"), "~")
    }

    func testInsertedMarkerIgnoresMultiCharEdits() {
        // A single marker inserted mid-word is still a single-character
        // insert — the scanner reports it (the popup opens; harmless).
        XCTAssertEqual(CookMarkerScanner.insertedMarker(from: "ab", to: "a@b"), "@")
        // Two-character inserts and no-op edits are not marker strokes.
        XCTAssertNil(CookMarkerScanner.insertedMarker(from: "ab", to: "ab@c"))
        XCTAssertNil(CookMarkerScanner.insertedMarker(from: "ab", to: "ab"))
    }

    func testMarkerBeforeFindsAnchorAcrossTokenChars() {
        let text = "Mix @water and #pot for ~5" as NSString
        // `@` at 4, `#` at 15, `~` at 24; `marker(before:)` inspects the
        // position immediately preceding the given offset.
        XCTAssertEqual(CookMarkerScanner.marker(before: 5, in: text), "@")
        XCTAssertEqual(CookMarkerScanner.marker(before: 16, in: text), "#")
        XCTAssertEqual(CookMarkerScanner.marker(before: 25, in: text), "~")
        // `@./soup` — the partial word starts after `./`; scan back finds `@`.
        let ref = "@./soup" as NSString
        XCTAssertEqual(CookMarkerScanner.marker(before: 6, in: ref), "@")
    }

    func testMarkerBeforeStopsAtWhitespace() {
        let text = "plain @token" as NSString
        // Position 0 (buffer start) — nothing before it.
        XCTAssertNil(CookMarkerScanner.marker(before: 0, in: text))
        // Scanning back from `t` of `token` finds `@`; from `plain` finds nothing.
        XCTAssertEqual(CookMarkerScanner.marker(before: 10, in: text), "@")
        let spaced = "plain  spaced" as NSString
        XCTAssertNil(CookMarkerScanner.marker(before: 12, in: spaced))
    }

    // MARK: - Fixture helpers

    /// Writes a `.boris/` mirroring the probed cooklang run: two nodes with
    /// recipe facets (broth + soup) and a completion index with two entities.
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let boris = root.appendingPathComponent(".boris", isDirectory: true)
        try FileManager.default.createDirectory(at: boris, withIntermediateDirectories: true)
        // NOTE: cleanup is the caller's job (defer in the test) — the
        // fixture must outlive this helper.

        let graph = """
        {
          "schemaVersion": "0.4.0",
          "frozen": true,
          "nodes": [
            {
              "index": 0, "id": "broth", "sourcePath": "broth.cook", "role": "trunk",
              "parent": null, "title": "Broth",
              "recipe": {
                "ingredients": [
                  {"name": "water", "quantity": {"amount": "2", "unit": "cups"}, "preparation": "", "recipeRef": null},
                  {"name": "soup", "quantity": {"amount": "1", "unit": "serving"}, "preparation": "", "recipeRef": "soup"}
                ],
                "cookware": [{"name": "pot", "quantity": {"amount": "1", "unit": ""}}],
                "timers": [{"name": "5", "quantity": {"amount": "5", "unit": "minutes"}}]
              }
            },
            {
              "index": 1, "id": "soup", "sourcePath": "soup.cook", "role": "trunk",
              "parent": null, "title": "Soup",
              "recipe": {
                "ingredients": [
                  {"name": "water", "quantity": {"amount": "2", "unit": "cups"}, "preparation": "", "recipeRef": null},
                  {"name": "salt", "quantity": {"amount": "1", "unit": "pinch"}, "preparation": "", "recipeRef": null}
                ],
                "cookware": [], "timers": []
              }
            }
          ],
          "edges": [], "reverseIndex": [], "nav": []
        }
        """
        try graph.write(to: boris.appendingPathComponent("graph.json"), atomically: true, encoding: .utf8)

        let completion = """
        {
          "format": "boris-completion-index",
          "schema_version": 1,
          "entities": [
            {"id": "broth", "title": "Broth", "parent": null, "role": "trunk", "status": "published", "tags": [], "relations": []},
            {"id": "soup", "title": "Soup", "parent": null, "role": "trunk", "status": "published", "tags": [], "relations": []}
          ],
          "relation_kinds": [], "parent_targets": [], "layout_slots": []
        }
        """
        try completion.write(to: boris.appendingPathComponent("completion.json"), atomically: true, encoding: .utf8)
        return root
    }
}
