import Foundation

/// The archived Boris pin has no verified recipe-scale machine contract
/// recorded by Solipsist. Do not substitute Swift math for that contract.
public enum RecipeScaleSupport {
    public static let isAvailable = false
    public static let unavailableMessage =
        "Recipe scaling is unavailable until its JSON contract is verified against the pinned Boris engine. "
        + "Recipe data from graph.json is shown unchanged."
}
