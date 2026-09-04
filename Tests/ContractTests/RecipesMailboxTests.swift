import XCTest

/// #296 — Cooklang recipe-scale as a first-class mailbox.
///
/// The Recipes row is a view over `graph.json`: `all(for:graph:)`
/// appends it iff ≥1 node carries a `recipe` facet (never keyed off
/// `profile.input_format`), the list filters to those nodes, and a
/// persisted `mailbox = "recipes"` round-trips raw (M13-0 rule).
final class RecipesMailboxTests: XCTestCase {
    private func graph(nodes: [GraphNode]) -> Graph {
        Graph(
            schemaVersion: "0.4.0",
            frozen: true,
            nodes: nodes,
            edges: [],
            reverseIndex: [],
            nav: []
        )
    }

    private func node(
        index: Int,
        id: String,
        title: String,
        recipe: CookRecipe? = nil
    ) -> GraphNode {
        GraphNode(
            index: index,
            id: id,
            sourcePath: id + ".cook",
            role: .trunk,
            parent: nil,
            parentIndex: nil,
            title: title,
            status: nil,
            tags: [],
            recipe: recipe
        )
    }

    private func sampleRecipe(ingredients: Int = 2) -> CookRecipe {
        CookRecipe(
            ingredients: (0..<ingredients).map {
                CookIngredient(
                    name: "item\($0)",
                    quantity: CookQuantity(amount: "1", unit: "cup")
                )
            }
        )
    }

    private func localItem() -> SourceItem {
        SourceItem.local(LocalSource(
            id: SourceID(),
            title: "Cookbook",
            bookmarkData: Data([1, 2, 3]),
            displayPath: "/tmp/cookbook",
            isAvailable: true
        ))
    }

    private func githubItem() -> SourceItem {
        SourceItem.github(GithubSource(
            id: SourceID(),
            title: "acme/cookbook",
            owner: "acme",
            repository: "cookbook",
            defaultBranch: "main",
            bookmarkData: Data([1, 2, 3]),
            displayPath: "/tmp/cookbook",
            grantedScopes: ["repo"]
        ))
    }

    func testRecipesMailboxOnlyWhenGraphHasRecipeFacet() {
        let mixed = graph(nodes: [
            node(index: 0, id: "index", title: "Home"),
            node(index: 1, id: "soup", title: "Soup", recipe: sampleRecipe()),
        ])
        XCTAssertTrue(LocalPlayGraph.hasRecipes(in: mixed))

        // Local: appended after the M10 set, in canonical position.
        let localRows = WorkspaceMailbox.all(for: localItem(), graph: mixed)
        XCTAssertTrue(localRows.contains(WorkspaceMailbox.recipes))
        XCTAssertEqual(
            localRows,
            WorkspaceMailbox.all + [WorkspaceMailbox.recipes]
        )

        // GitHub: recipes sits with the local set, ahead of the
        // github-only rows (their suffix is stable).
        let githubRows = WorkspaceMailbox.all(for: githubItem(), graph: mixed)
        XCTAssertTrue(githubRows.contains(WorkspaceMailbox.recipes))
        XCTAssertEqual(
            githubRows.suffix(3),
            [WorkspaceMailbox.remote, WorkspaceMailbox.issues, WorkspaceMailbox.pulls]
        )

        // No facet anywhere → no row, for either kind.
        let plain = graph(nodes: [node(index: 0, id: "index", title: "Home")])
        XCTAssertFalse(LocalPlayGraph.hasRecipes(in: plain))
        XCTAssertFalse(WorkspaceMailbox.all(for: localItem(), graph: plain)
            .contains(WorkspaceMailbox.recipes))
        XCTAssertFalse(WorkspaceMailbox.all(for: githubItem(), graph: plain)
            .contains(WorkspaceMailbox.recipes))

        // No graph yet (no build) → no row until the first build.
        XCTAssertEqual(WorkspaceMailbox.all(for: localItem()), WorkspaceMailbox.all)
        XCTAssertEqual(
            WorkspaceMailbox.all(for: localItem(), graph: nil),
            WorkspaceMailbox.all
        )
    }

    func testRecipesMailboxAbsentForMarkdownOnlySource() throws {
        // The `happy` stunt is `input_format: "markdown"` — its graph
        // carries no `recipe` facet, so the row must stay hidden.
        let happy = try decode(Graph.self, "happy-ir", "graph.json")
        XCTAssertFalse(happy.nodes.isEmpty)
        XCTAssertFalse(happy.nodes.contains { $0.recipe != nil })
        XCTAssertFalse(LocalPlayGraph.hasRecipes(in: happy))
        XCTAssertFalse(WorkspaceMailbox.all(for: localItem(), graph: happy)
            .contains(WorkspaceMailbox.recipes))
        XCTAssertTrue(LocalPlayGraph.recipes(
            in: LocalPlayGraph.pages(from: happy)
        ).isEmpty)
    }

    func testRecipesMailboxDisplayNameAndSymbol() {
        XCTAssertEqual(WorkspaceMailbox.displayName(WorkspaceMailbox.recipes), "Recipes")
        XCTAssertEqual(WorkspaceMailbox.symbolName(WorkspaceMailbox.recipes), "fork.knife")
        // Passes through the center switch untouched (M13-0 rule).
        XCTAssertEqual(
            WorkspaceMailbox.display(WorkspaceMailbox.recipes),
            WorkspaceMailbox.recipes
        )
    }

    func testUnknownRecipesMailboxSurvivesRelaunch() throws {
        // Persisted raw; decode keeps it verbatim — never coerced to Pages.
        let payload = PersistedWorkspace(
            sources: [],
            selected: nil,
            mailbox: WorkspaceMailbox.recipes
        )
        let decoded = try WorkspacePersistence.decode(
            WorkspacePersistence.encode(payload)
        )
        XCTAssertEqual(decoded.mailbox, WorkspaceMailbox.recipes)
        XCTAssertNotEqual(decoded.mailbox, WorkspaceMailbox.pages)
        XCTAssertEqual(
            WorkspaceMailbox.display(decoded.mailbox),
            WorkspaceMailbox.recipes
        )

        // Selection restore keeps the raw token too.
        let id = SourceID()
        let restored = WorkspaceSelectionRules.restore(
            selected: id,
            mailbox: WorkspaceMailbox.recipes,
            available: [id]
        )
        XCTAssertEqual(restored.mailbox, WorkspaceMailbox.recipes)
    }

    func testEmptyRecipeFacetStillLists() {
        // A present-but-empty recipe (zero ingredients) is still a row —
        // facet presence, not the count, is the membership test.
        let empty = graph(nodes: [
            node(index: 0, id: "empty", title: "Empty", recipe: CookRecipe()),
        ])
        XCTAssertTrue(WorkspaceMailbox.all(for: localItem(), graph: empty)
            .contains(WorkspaceMailbox.recipes))
        let pages = LocalPlayGraph.recipes(
            in: LocalPlayGraph.pages(from: empty)
        )
        XCTAssertEqual(pages.map(\.id), ["empty"])
        XCTAssertEqual(pages.first?.ingredientCount, 0)
    }

    func testRecipePagesCarryIngredientCounts() {
        let mixed = graph(nodes: [
            node(index: 0, id: "index", title: "Home"),
            node(index: 1, id: "soup", title: "Soup", recipe: sampleRecipe(ingredients: 2)),
        ])
        let pages = LocalPlayGraph.pages(from: mixed)
        XCTAssertNil(pages.first { $0.id == "index" }?.ingredientCount)
        XCTAssertEqual(pages.first { $0.id == "soup" }?.ingredientCount, 2)
        XCTAssertEqual(
            LocalPlayGraph.recipes(in: pages).map(\.id),
            ["soup"]
        )
    }

    // MARK: - Fixtures

    private func decode<T: Decodable>(_ type: T.Type, _ folder: String, _ name: String) throws -> T {
        let url = try fixture(folder, name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func fixture(_ folder: String, _ name: String) throws -> URL {
        let bundle = Bundle(for: RecipesMailboxTests.self)
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
