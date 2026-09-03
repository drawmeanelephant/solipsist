import XCTest

/// #296 — Recipes mailbox: the conditional sidebar row (≥1 graph node
/// with a `recipe` facet), the list derivation, and the M13-0
/// persistence rule for the new token.
final class RecipesMailboxTests: XCTestCase {
    private func node(
        index: Int,
        id: String,
        role: PageRole,
        parent: String?,
        title: String,
        recipe: CookRecipe? = nil
    ) -> GraphNode {
        GraphNode(
            index: index,
            id: id,
            sourcePath: id + ".md",
            role: role,
            parent: parent,
            parentIndex: nil,
            title: title,
            status: "published",
            tags: [],
            recipe: recipe
        )
    }

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

    private let soup = CookRecipe(
        ingredients: [
            CookIngredient(name: "water", quantity: CookQuantity(amount: "2", unit: "cups")),
            CookIngredient(name: "salt", quantity: CookQuantity(amount: "1", unit: "pinch")),
        ],
        cookware: [],
        timers: []
    )

    private var localItem: SourceItem {
        SourceItem.local(LocalSource(
            id: SourceID(),
            title: "Kitchen",
            bookmarkData: Data([1, 2, 3]),
            displayPath: "/tmp/kitchen",
            isAvailable: true
        ))
    }

    // MARK: - Conditional sidebar row

    func testRecipesMailboxOnlyWhenGraphHasRecipeFacet() {
        let cookGraph = graph(nodes: [
            node(index: 0, id: "soup", role: .trunk, parent: nil, title: "Soup", recipe: soup),
        ])
        XCTAssertTrue(
            WorkspaceMailbox.all(for: localItem, graph: cookGraph)
                .contains(WorkspaceMailbox.recipes),
            "≥1 node with recipe != nil admits the row"
        )

        // An empty-ingredient recipe still counts (the row shows "0 ingredients").
        let emptyRecipeGraph = graph(nodes: [
            node(index: 0, id: "soup", role: .trunk, parent: nil, title: "Soup", recipe: CookRecipe()),
        ])
        XCTAssertTrue(
            WorkspaceMailbox.all(for: localItem, graph: emptyRecipeGraph)
                .contains(WorkspaceMailbox.recipes)
        )
    }

    func testRecipesMailboxAbsentForMarkdownOnlySource() {
        // The happy fixture shape: three markdown nodes, no recipe facet.
        let markdownGraph = graph(nodes: [
            node(index: 0, id: "index", role: .trunk, parent: nil, title: "Home"),
            node(index: 1, id: "guides", role: .trunk, parent: nil, title: "Guides"),
            node(index: 2, id: "guides/intro", role: .satellite, parent: "guides", title: "Intro"),
        ])
        XCTAssertFalse(
            WorkspaceMailbox.all(for: localItem, graph: markdownGraph)
                .contains(WorkspaceMailbox.recipes)
        )

        // No graph yet (unbuilt source): no Recipes row, never synthesized.
        XCTAssertFalse(
            WorkspaceMailbox.all(for: localItem, graph: nil)
                .contains(WorkspaceMailbox.recipes)
        )
    }

    func testRecipesRowAppendedAfterCanonicalRows() {
        let cookGraph = graph(nodes: [
            node(index: 0, id: "soup", role: .trunk, parent: nil, title: "Soup", recipe: soup),
        ])
        let rows = WorkspaceMailbox.all(for: localItem, graph: cookGraph)
        XCTAssertEqual(rows.dropLast(), WorkspaceMailbox.all)
        XCTAssertEqual(rows.last, WorkspaceMailbox.recipes)
    }

    func testRecipesRowNeverInBaseAllSet() {
        // `all` stays the M10 set — recipes is conditional, like the
        // github-only rows, not unconditional.
        XCTAssertFalse(WorkspaceMailbox.all.contains(WorkspaceMailbox.recipes))
    }

    // MARK: - List derivation

    func testRecipesListFiltersGraphNodesByRecipeFacet() {
        let mixed = graph(nodes: [
            node(index: 0, id: "index", role: .trunk, parent: nil, title: "Home"),
            node(index: 1, id: "soup", role: .trunk, parent: nil, title: "Soup", recipe: soup),
            node(index: 2, id: "bread", role: .satellite, parent: "soup", title: "Bread", recipe: CookRecipe()),
        ])
        let pages = LocalPlayGraph.pages(from: mixed)
        let recipes = LocalPlayGraph.recipes(from: pages, graph: mixed)
        XCTAssertEqual(recipes.map(\.id), ["soup", "bread"], "graph order, markdown pages excluded")
        XCTAssertEqual(recipes.count, 2)
        // #296: the row carries the ingredient count; an empty recipe
        // still lists as 0, never dropped.
        XCTAssertEqual(recipes[0].ingredientCount, 2)
        XCTAssertEqual(recipes[1].ingredientCount, 0)
        // Pages rows on other surfaces never carry it.
        XCTAssertNil(pages.first { $0.id == "index" }?.ingredientCount)
    }

    func testRecipesListEmptyWithoutGraphOrFacet() {
        let markdown = graph(nodes: [
            node(index: 0, id: "index", role: .trunk, parent: nil, title: "Home"),
        ])
        XCTAssertEqual(LocalPlayGraph.recipes(from: LocalPlayGraph.pages(from: markdown), graph: markdown), [])
        XCTAssertEqual(LocalPlayGraph.recipes(from: [], graph: nil), [], "no graph yet → no synthesized rows")
    }

    // MARK: - Display + persistence (M13-0 parity)

    func testRecipesMailboxDisplayNameAndSymbol() {
        XCTAssertEqual(WorkspaceMailbox.displayName(WorkspaceMailbox.recipes), "Recipes")
        XCTAssertEqual(WorkspaceMailbox.symbolName(WorkspaceMailbox.recipes), "fork.knife")
    }

    func testUnknownRecipesMailboxSurvivesRelaunch() {
        // A persisted `mailbox = "recipes"` round-trips through
        // WorkspaceSelection untouched — never coerced to "pages".
        let stored = WorkspaceSelection(
            sourceID: SourceID(),
            mailbox: WorkspaceMailbox.recipes,
            noun: nil
        )
        let data = try! JSONEncoder().encode(stored)
        let decoded = try! JSONDecoder().decode(WorkspaceSelection.self, from: data)
        XCTAssertEqual(decoded.mailbox, WorkspaceMailbox.recipes)
        XCTAssertEqual(WorkspaceMailbox.display(decoded.mailbox), WorkspaceMailbox.recipes)
    }
}
