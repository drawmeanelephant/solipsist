import Foundation

/// Mathematical and parsing helper for Cooklang recipe scaling.
public enum RecipeScaleHelper {
    /// Evaluates a scaled CookRecipe given a scale factor multiplier.
    public static func scale(recipe: CookRecipe, factor: Double) -> CookRecipe {
        guard factor > 0 else { return recipe }
        let scaledIngredients = recipe.ingredients.map { ing in
            CookIngredient(
                name: ing.name,
                quantity: scaleQuantity(ing.quantity, factor: factor),
                preparation: ing.preparation,
                recipeRef: ing.recipeRef
            )
        }
        let scaledCookware = recipe.cookware.map { cw in
            CookCookware(
                name: cw.name,
                quantity: scaleQuantity(cw.quantity, factor: factor)
            )
        }
        let scaledTimers = recipe.timers
        return CookRecipe(
            ingredients: scaledIngredients,
            cookware: scaledCookware,
            timers: scaledTimers
        )
    }

    public static func scaleQuantity(_ quantity: CookQuantity, factor: Double) -> CookQuantity {
        guard let num = parseAmount(quantity.amount) else {
            return quantity
        }
        let scaled = num * factor
        return CookQuantity(amount: formatAmount(scaled), unit: quantity.unit)
    }

    /// Parses string amounts like "2", "1.5", "1/2", "2 1/2", "0.25", "3/4" into Double.
    public static func parseAmount(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Mixed fraction: "2 1/2"
        let parts = trimmed.split(separator: " ")
        if parts.count == 2, let whole = Double(parts[0]), let frac = parseFraction(String(parts[1])) {
            return whole + frac
        }

        // Single fraction: "1/2"
        if let frac = parseFraction(trimmed) {
            return frac
        }

        // Standard decimal / integer
        return Double(trimmed)
    }

    private static func parseFraction(_ str: String) -> Double? {
        let components = str.split(separator: "/")
        guard components.count == 2,
              let num = Double(components[0]),
              let den = Double(components[1]),
              den != 0 else {
            return nil
        }
        return num / den
    }

    /// Formats Double into clean representation (integer, common fraction, or clean decimal).
    public static func formatAmount(_ value: Double) -> String {
        // Close to integer?
        let rounded = value.rounded()
        if abs(value - rounded) < 0.001 {
            return String(Int(rounded))
        }

        // Common fractions: 1/8, 1/4, 1/3, 3/8, 1/2, 5/8, 2/3, 3/4, 7/8
        let whole = Int(value)
        let frac = value - Double(whole)
        let commonFractions: [(Double, String)] = [
            (0.125, "1/8"),
            (0.25, "1/4"),
            (0.3333, "1/3"),
            (0.375, "3/8"),
            (0.5, "1/2"),
            (0.625, "5/8"),
            (0.6666, "2/3"),
            (0.75, "3/4"),
            (0.875, "7/8")
        ]

        for (target, text) in commonFractions {
            if abs(frac - target) < 0.02 {
                if whole > 0 {
                    return "\(whole) \(text)"
                } else {
                    return text
                }
            }
        }

        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
