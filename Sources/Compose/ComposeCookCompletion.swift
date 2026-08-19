import Foundation

/// Boris-owned Cooklang completion vocabulary (LATER-3.4). Sourced
/// exclusively from the selected source's `.boris/` artifacts — never
/// hand-rolled:
/// - `graph.json` recipe IR facets: `ingredients[].name`, `cookware[].name`,
///   `timers[].name` across every node in the corpus (verified: cooklang
///   mode publishes a `recipe` facet per node; `@./path` refs surface as an
///   ingredient with a `recipeRef`).
/// - `completion.json` entities: page ids, offered as `./<id>` recipe refs
///   so `@./soup` completes from the corpus's own pages.
///
/// Read-only: never mutates, never spawns a process. Decode failures
/// degrade to `.empty` (D8) — completion is best-effort, never a crash.
struct ComposeCookCompletion: Equatable, Sendable {
    var ingredients: [String] = []
    var cookware: [String] = []
    var timers: [String] = []
    var entityIDs: [String] = []

    static let empty = ComposeCookCompletion()

    var isEmpty: Bool {
        ingredients.isEmpty && cookware.isEmpty && timers.isEmpty && entityIDs.isEmpty
    }

    /// Decodes both artifacts from `<workspaceRoot>/.boris/`. Any missing or
    /// malformed artifact contributes nothing (D8); `graph.json` needs the
    /// recipe facet (IR 0.4) to contribute vocabulary.
    static func load(workspaceRoot: URL) -> ComposeCookCompletion {
        let boris = workspaceRoot.appendingPathComponent(".boris", isDirectory: true)
        var result = ComposeCookCompletion()

        let graphURL = boris.appendingPathComponent("graph.json")
        if let graph = Self.decode(Graph.self, from: graphURL) {
            for node in graph.nodes {
                guard let recipe = node.recipe else { continue }
                result.ingredients.append(contentsOf: recipe.ingredients.map(\.name))
                result.cookware.append(contentsOf: recipe.cookware.map(\.name))
                result.timers.append(contentsOf: recipe.timers.map(\.name))
            }
        }

        let completionURL = boris.appendingPathComponent("completion.json")
        if let completion = Self.decode(Completion.self, from: completionURL) {
            result.entityIDs = completion.entities.map(\.id)
        }
        result.normalize()
        return result
    }

    /// Best-effort decode (D8): missing or malformed artifacts contribute
    /// nothing rather than failing the whole load.
    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Sorts and dedupes every vocabulary list so consumers see a stable,
    /// deterministic popup (recipes repeat ingredients across the corpus).
    private mutating func normalize() {
        ingredients = Self.uniqueSorted(ingredients)
        cookware = Self.uniqueSorted(cookware)
        timers = Self.uniqueSorted(timers)
        entityIDs = Self.uniqueSorted(entityIDs)
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.sorted().filter { seen.insert($0).inserted }
    }

    /// Suggestions for the token the author is mid-type on, filtered by the
    /// partial word (case-insensitive, capped so the popup stays sane):
    /// - `@` → ingredient names plus entity ids (recipe refs — the author
    ///   types the `./` themselves; insertion stays a plain name so the
    ///   popup's replace range never duplicates a path prefix)
    /// - `#` → cookware names
    /// - `~` → timer names
    /// Unknown markers return nothing.
    func suggestions(marker: Character, prefix: String) -> [String] {
        let pool: [String]
        switch marker {
        case "@":
            pool = ingredients + entityIDs
        case "#":
            pool = cookware
        case "~":
            pool = timers
        default:
            return []
        }
        let lowered = prefix.lowercased()
        var seen = Set<String>()
        var matches: [String] = []
        for candidate in pool.sorted() where seen.insert(candidate).inserted {
            guard candidate.lowercased().hasPrefix(lowered) else { continue }
            matches.append(candidate)
            if matches.count == 25 { break }
        }
        return matches
    }
}

/// Tiny scanner helpers for the NSTextView completion trigger. Foundation-
/// only so ContractTests can pin the marker logic without AppKit.
enum CookMarkerScanner {
    /// The Cooklang token markers that open the completion popup.
    static let markers: Set<Character> = ["@", "#", "~"]

    /// The marker character the author just inserted, if the edit inserted
    /// exactly one marker and nothing else (e.g. typing `@` after a word).
    static func insertedMarker(from oldText: String, to newText: String) -> Character? {
        let old = oldText as NSString
        let new = newText as NSString
        guard new.length == old.length + 1 else { return nil }
        var index = 0
        while index < old.length, old.character(at: index) == new.character(at: index) {
            index += 1
        }
        guard let scalar = Unicode.Scalar(new.character(at: index)) else { return nil }
        let inserted = Character(scalar)
        return markers.contains(inserted) ? inserted : nil
    }

    /// The marker anchoring a partial word: scan back from the position
    /// before the completion range over any token characters (so `@./soup`
    /// still resolves to `@`), stopping at whitespace or the buffer start.
    static func marker(before position: Int, in text: NSString) -> Character? {
        var index = position - 1
        while index >= 0 {
            guard let scalar = Unicode.Scalar(text.character(at: index)) else { return nil }
            let char = Character(scalar)
            if markers.contains(char) { return char }
            if char.isWhitespace { return nil }
            index -= 1
        }
        return nil
    }
}
