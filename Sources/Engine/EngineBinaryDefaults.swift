import Foundation

/// Removes the legacy `custom*BinaryPath` preference keys (#292).
///
/// Settings → Engine no longer offers binary pickers: App Sandbox denies
/// exec outside our own bundle, so a saved custom path could never work
/// in a signed build and would only shadow the embedded engine. The
/// locators stopped reading these keys; this clears any stale values
/// written by older builds.
public enum EngineBinaryDefaults {
    public static let legacyKeys = [
        "customBorisBinaryPath",
        "customOliverBinaryPath",
        "customBorisEditorBinaryPath",
    ]

    public static func removeLegacyCustomPaths(defaults: UserDefaults = .standard) {
        for key in legacyKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
    }
}
