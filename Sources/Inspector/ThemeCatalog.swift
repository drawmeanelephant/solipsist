import Foundation

/// Theme catalog (M7): 20 first-class Boris themes plus any local custom
/// themes discovered in the project workspace `themes/` directory. Selection only,
/// never authoring.
public enum ThemeCatalog {
    /// 20 first-class themes bundled or recognized by Boris compiler.
    public static let firstClassThemes: [String] = [
        "archive",
        "boris",
        "cards",
        "civic",
        "columns",
        "compact",
        "corporate",
        "cozy",
        "engineering",
        "field-notes",
        "journal",
        "ledger",
        "minimal",
        "press",
        "reading",
        "reference",
        "semantic",
        "service",
        "showcase",
        "tokens",
    ]

    /// Discovers local themes in `<projectRoot>/themes/`.
    public static func discoverLocalThemes(in projectRoot: URL) -> [String] {
        let themesDir = projectRoot.appendingPathComponent("themes", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: themesDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var themes: [String] = []
        for entry in entries {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                themes.append(entry.lastPathComponent)
            }
        }
        return themes.sorted()
    }

    /// Combined theme list: project local themes followed by first-class themes.
    public static func allThemes(for projectRoot: URL?) -> [String] {
        var set = Set<String>()
        var result: [String] = []

        if let projectRoot {
            let local = discoverLocalThemes(in: projectRoot)
            for theme in local {
                if set.insert(theme).inserted {
                    result.append(theme)
                }
            }
        }

        for theme in firstClassThemes {
            if set.insert(theme).inserted {
                result.append(theme)
            }
        }

        return result
    }
}
