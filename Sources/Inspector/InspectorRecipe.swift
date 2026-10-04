import Foundation

/// Only the engine-owned graph facet is recipe data. Tags, names, and
/// source extensions must never supply replacement ingredients.
enum InspectorRecipe {
    static let unavailableMessage = "Recipe data is unavailable in graph.json. Build IR to refresh the graph."

    static func recipe(for node: GraphNode?) -> CookRecipe? {
        node?.recipe
    }
}
