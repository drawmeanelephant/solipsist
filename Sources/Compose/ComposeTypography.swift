import AppKit
import Observation

/// #264: single source of truth for the compose buffer's reading type —
/// one ladder of sizes (11…21 pt, default 13), a gutter toggle, and their
/// UserDefaults persistence (machine state → plist; D2-safe). Both old
/// hardcode sites (`ComposeTextView.baseFont` and its Coordinator duplicate)
/// consume this.
@MainActor
@Observable
final class ComposeTypography {
    static let defaultSize: CGFloat = 13
    static let minSize: CGFloat = 11
    static let maxSize: CGFloat = 21
    /// Breathing-room paragraph line spacing (#264), buffer-only cosmetic.
    static let lineSpacing: CGFloat = 4

    static let sizeStorageKey = "composeBufferFontSize"
    static let gutterStorageKey = "composeShowLineNumbers"

    private(set) var size: CGFloat
    private(set) var showsLineNumbers: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Self.sizeStorageKey)
        size = stored == 0
            ? Self.defaultSize
            : min(max(CGFloat(stored), Self.minSize), Self.maxSize)
        // Checked by default: the gutter ships on until the author turns it off.
        showsLineNumbers =
            defaults.object(forKey: Self.gutterStorageKey) == nil
                || defaults.bool(forKey: Self.gutterStorageKey)
    }

    var font: NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var boldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
    }

    var italicFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular).withTraits(.italic)
    }

    /// Paragraph style carrying the reading line spacing.
    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = Self.lineSpacing
        return style
    }

    func zoomIn() {
        store(size: size + 1)
    }

    func zoomOut() {
        store(size: size - 1)
    }

    func resetToActualSize() {
        store(size: Self.defaultSize)
    }

    func setLineNumbers(_ visible: Bool) {
        showsLineNumbers = visible
        defaults.set(visible, forKey: Self.gutterStorageKey)
    }

    private func store(size newValue: CGFloat) {
        let clamped = min(max(newValue, Self.minSize), Self.maxSize)
        guard clamped != size else { return }
        size = clamped
        defaults.set(Double(size), forKey: Self.sizeStorageKey)
    }
}
