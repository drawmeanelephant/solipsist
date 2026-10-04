import XCTest

final class BorisRecipeScaleTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let binary: URL
        let engine: BorisEngine

        var contentRoot: URL { root.appendingPathComponent("content") }
        var graphURL: URL { root.appendingPathComponent(".boris/graph.json") }
    }

    private let recipe = CookRecipe(
        ingredients: [CookIngredient(name: "water", quantity: CookQuantity(amount: "2", unit: "cups"))],
        cookware: [CookCookware(name: "pot", quantity: CookQuantity(amount: "1"))],
        timers: [CookTimer(name: "simmer", quantity: CookQuantity(amount: "10", unit: "minutes"))]
    )

    /// A valid graph facet must not rescue a failed or undecodable command.
    private func makeFixture(stdout: String, exit: Int, stderr: String = "recipe diagnostic") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recipe-failure-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("content"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".boris"), withIntermediateDirectories: true)
        let node = GraphNode(
            index: 0, id: "soup", sourcePath: "soup.cook", role: .trunk,
            parent: nil, parentIndex: nil, title: "Soup", status: nil, tags: ["recipe"], recipe: recipe
        )
        let graph = Graph(schemaVersion: "0.4.0", frozen: true, nodes: [node], edges: [], reverseIndex: [], nav: [])
        try JSONEncoder().encode(graph).write(to: root.appendingPathComponent(".boris/graph.json"))
        try "Mix @water{2%cups}.".write(to: root.appendingPathComponent("content/soup.cook"), atomically: true, encoding: .utf8)
        let binary = root.appendingPathComponent("boris")
        let script = """
        #!/bin/sh
        cat <<'RECIPE_STDOUT'
        \(stdout)
        RECIPE_STDOUT
        cat >&2 <<'RECIPE_STDERR'
        \(stderr)
        RECIPE_STDERR
        exit \(exit)
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        return try Fixture(root: root, binary: binary, engine: BorisEngine(binaryURL: binary))
    }

    func testNonzeroExitAndDiagnosticsCannotBecomeGraphFallbackSuccess() async throws {
        for exit in [1, 2, 3, 71] {
            let fixture = try makeFixture(stdout: "failed command output", exit: exit)
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let originalGraph = try Data(contentsOf: fixture.graphURL)
            let result = try await fixture.engine.recipeScale(
                contentRoot: fixture.contentRoot, pageID: "soup", factor: 2, workingDirectory: fixture.root
            )
            XCTAssertEqual(result.exitCode, Int32(exit))
            XCTAssertNil(result.recipe)
            XCTAssertEqual(result.stdout, "failed command output\n")
            XCTAssertEqual(result.stderr, "recipe diagnostic\n")
            XCTAssertEqual(try Data(contentsOf: fixture.graphURL), originalGraph)
            XCTAssertEqual(try String(contentsOf: fixture.contentRoot.appendingPathComponent("soup.cook"), encoding: .utf8), "Mix @water{2%cups}.")
        }
    }

    func testNonzeroExitDoesNotAcceptEvenValidRecipeJSON() async throws {
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(recipe), encoding: .utf8))
        let fixture = try makeFixture(stdout: json, exit: 1)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let result = try await fixture.engine.recipeScale(contentRoot: fixture.contentRoot, pageID: "soup", workingDirectory: fixture.root)
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertNil(result.recipe)
        XCTAssertEqual(result.stderr, "recipe diagnostic\n")
    }

    func testLaunchFailurePropagatesDespiteValidGraphRecipe() async throws {
        let fixture = try makeFixture(stdout: "", exit: 0)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.binary)
        do {
            _ = try await fixture.engine.recipeScale(contentRoot: fixture.contentRoot, pageID: "soup", workingDirectory: fixture.root)
            XCTFail("a launch failure must not fall back to local recipe math")
        } catch {
            XCTAssertFalse(String(describing: error).isEmpty)
        }
    }

    func testMalformedAndMissingRecipeJSONAreExplicitFailuresWithDiagnostics() async throws {
        for stdout in ["not JSON", "", "{}", #"{"ingredients":[],"cookware":[]}"#] {
            let fixture = try makeFixture(stdout: stdout, exit: 0, stderr: "useful decode diagnostic")
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            do {
                _ = try await fixture.engine.recipeScale(contentRoot: fixture.contentRoot, pageID: "soup", workingDirectory: fixture.root)
                XCTFail("undecodable engine output must not appear successful: \(stdout)")
            } catch BorisEngineError.decodeFailed(let artifact, let reason) {
                XCTAssertEqual(artifact, "recipe-scale stdout")
                XCTAssertTrue(reason.contains("useful decode diagnostic"))
            }
        }
    }

    func testValidSubprocessRecipeIsReturnedUnchangedNotRescaledInSwift() async throws {
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(recipe), encoding: .utf8))
        let fixture = try makeFixture(stdout: json, exit: 0)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let result = try await fixture.engine.recipeScale(contentRoot: fixture.contentRoot, pageID: "soup", factor: 4, workingDirectory: fixture.root)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.recipe, recipe, "the response belongs to Boris, even if it differs from Swift's expected factor")
        XCTAssertEqual(result.recipe?.ingredients.first?.quantity.amount, "2")
    }

    func testCancelledCallCannotBecomeRecipeFallbackSuccess() async throws {
        let fixture = try makeFixture(stdout: "", exit: 0)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let engine = fixture.engine
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await engine.recipeScale(contentRoot: fixture.contentRoot, pageID: "soup", workingDirectory: fixture.root)
        }
        do {
            _ = try await task.value
            XCTFail("cancellation must propagate, not evaluate the local graph")
        } catch is CancellationError {}
    }
}
