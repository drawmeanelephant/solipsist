import Foundation

/// The `boris-recipe-scale` 0.2.0 contract was verified live against the
/// pinned engine (`boris/0.8.2`, pin `3ab19ad` — see
/// `docs/ENGINE-CONTRACTS.md` §10). Do not substitute Swift math for the
/// engine's scale view.
public enum RecipeScaleSupport {
    public static let isAvailable = true
    public static let unavailableMessage =
        "Recipe scaling is unavailable until its JSON contract is verified against the pinned Boris engine. "
        + "Recipe data from graph.json is shown unchanged."
}
