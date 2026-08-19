import XCTest

/// Contract for LATER-3.3's front-matter core: the closed 9-key grammar
/// (`boris-frontmatter-1.schema.json` at pin `6b930b7`), minimal-YAML
/// parse, and overlay write-back. Pure Foundation — no SwiftUI.
final class ComposeFrontmatterTests: XCTestCase {
    // MARK: - Parse

    func testParseClosedKeys() {
        let payload = """
        id: pancakes
        title: Perfect Pancakes
        parent: breakfast
        status: published
        published_at: 2026-08-19
        summary: Fluffy and fast
        servings: 4
        tags: [breakfast, quick]
        relations: [kind=child, kind=variant]
        """
        let fields = ComposeFrontmatter.parse(payload: payload)
        XCTAssertEqual(fields.id, "pancakes")
        XCTAssertEqual(fields.title, "Perfect Pancakes")
        XCTAssertEqual(fields.parent, "breakfast")
        XCTAssertEqual(fields.status, "published")
        XCTAssertEqual(fields.publishedAt, "2026-08-19")
        XCTAssertEqual(fields.summary, "Fluffy and fast")
        XCTAssertEqual(fields.servings, "4")
        XCTAssertEqual(fields.tags, ["breakfast", "quick"])
        XCTAssertEqual(fields.relations.count, 2)
        XCTAssertEqual(fields.relations[0], ComposeFrontmatter.Relation(kind: "kind", target: "child"))
        XCTAssertEqual(fields.relations[1], ComposeFrontmatter.Relation(kind: "kind", target: "variant"))
    }

    func testParseBlockLists() {
        let payload = """
        tags:
          - breakfast
          - quick
        relations:
          - kind: child
            target: crepes
          - kind: variant
            target: american
        """
        let fields = ComposeFrontmatter.parse(payload: payload)
        XCTAssertEqual(fields.tags, ["breakfast", "quick"])
        XCTAssertEqual(fields.relations.count, 2)
        XCTAssertEqual(fields.relations[1], ComposeFrontmatter.Relation(kind: "variant", target: "american"))
    }

    func testParseIgnoresUnknownKeys() {
        let payload = """
        id: x
        custom_thing: keep me
        nested:
          a: 1
        """
        let fields = ComposeFrontmatter.parse(payload: payload)
        XCTAssertEqual(fields.id, "x")
        XCTAssertEqual(fields.title, "")
        XCTAssertEqual(fields.tags, [])
    }

    func testParseEmptyPayload() {
        let fields = ComposeFrontmatter.parse(payload: "")
        XCTAssertEqual(fields, .empty)
    }

    // MARK: - Apply

    func testApplyOverlaysOnlyClosedKeysAndPreservesUnknown() {
        let payload = """
        id: old
        custom_thing: untouched
        status: draft
        """
        let fields = ComposeFrontmatter.Fields(id: "new", title: "A Title", status: "published")
        let result = ComposeFrontmatter.apply(fields, to: payload)
        XCTAssertTrue(result.contains("id: new"))
        XCTAssertTrue(result.contains("title: A Title"))
        XCTAssertTrue(result.contains("status: published"))
        XCTAssertTrue(result.contains("custom_thing: untouched"))
        XCTAssertFalse(result.contains("id: old"))
    }

    func testApplyEmitsBlockLists() {
        let fields = ComposeFrontmatter.Fields(
            tags: ["a", "b"],
            relations: [ComposeFrontmatter.Relation(kind: "child", target: "x")]
        )
        let result = ComposeFrontmatter.apply(fields, to: "id: x")
        XCTAssertTrue(result.contains("tags:"))
        XCTAssertTrue(result.contains("  - a"))
        XCTAssertTrue(result.contains("  - b"))
        XCTAssertTrue(result.contains("relations:"))
        XCTAssertTrue(result.contains("  - kind: child"))
        XCTAssertTrue(result.contains("    target: x"))
    }

    func testApplyOmitsEmptyKeys() {
        // The form overlays the whole closed set, so a field the user clears
        // drops its key (absence == null per the schema). `id` survives only
        // because the form still carries it.
        let fields = ComposeFrontmatter.Fields(id: "x")
        let result = ComposeFrontmatter.apply(fields, to: "id: x\nsummary: keep")
        XCTAssertEqual(result, "id: x")
        XCTAssertFalse(result.contains("title:"))
        XCTAssertFalse(result.contains("published_at:"))
        XCTAssertFalse(result.contains("summary:")) // owned key, emptied
    }

    func testApplyCreatesBlockFromScratch() {
        let fields = ComposeFrontmatter.Fields(id: "fresh", tags: ["new"])
        let result = ComposeFrontmatter.apply(fields, to: "")
        XCTAssertEqual(
            result,
            "id: fresh\ntags:\n  - new"
        )
    }

    func testApplyRoundTripsParse() {
        let payload = """
        id: pancakes
        title: Perfect Pancakes
        tags: [breakfast, quick]
        relations: [kind=child target=crepes]
        """
        let fields = ComposeFrontmatter.parse(payload: payload)
        let rewritten = ComposeFrontmatter.apply(fields, to: payload)
        let reparsed = ComposeFrontmatter.parse(payload: rewritten)
        XCTAssertEqual(fields, reparsed)
    }
}
