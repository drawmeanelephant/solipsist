import XCTest

/// M11-2: Help vs `Commands.swift` never drifts again.
///
/// Reads the two files from the repo root (found by walking up from this
/// test's source path), then fails loud if any menu verb or keyboard
/// shortcut in `Sources/App/Commands.swift` is undocumented in
/// `docs/help.md`. No SwiftUI import: this is pure text parsing.
final class HelpAuditTests: XCTestCase {
    /// Buttons that are UI placeholders, not menu verbs. They do not need
    /// a Help row.
    private static let nonVerbs: Set<String> = [
        "No Recent Folders",
    ]

    func testEveryMenuVerbAppearsInHelp() throws {
        let commands = try HelpAudit.source()
        let help = try HelpAudit.help()

        for title in HelpAudit.buttonTitles(in: commands) {
            guard !Self.nonVerbs.contains(title) else { continue }
            XCTAssertTrue(
                help.contains(title),
                "Menu verb “\(title)” is missing from docs/help.md"
            )
        }
    }

    func testEveryKeyboardShortcutAppearsInHelp() throws {
        let commands = try HelpAudit.source()
        let help = try HelpAudit.help()

        for (key, glyph) in HelpAudit.shortcuts(in: commands) {
            XCTAssertTrue(
                help.contains(glyph),
                "Shortcut \(glyph) (key “\(key)”) is missing from docs/help.md"
            )
        }
    }

    /// The Inspector toggle renders one of two titles from a ternary, so
    /// the literal-button scan cannot see it. Pin both names explicitly.
    func testInspectorToggleNamesAppearInHelp() throws {
        let help = try HelpAudit.help()
        XCTAssertTrue(help.contains("Show Inspector"))
        XCTAssertTrue(help.contains("Hide Inspector"))
    }

    func testHelpListsEveryMailbox() throws {
        let help = try HelpAudit.help()
        let allMailboxes = WorkspaceMailbox.all + [
            WorkspaceMailbox.remote,
            WorkspaceMailbox.issues,
            WorkspaceMailbox.pulls,
        ]
        for mailbox in allMailboxes {
            XCTAssertTrue(
                help.contains(WorkspaceMailbox.displayName(mailbox)),
                "Mailbox \(mailbox) is missing from docs/help.md"
            )
        }
    }
}

/// Text helpers for the audit. Foundation only — the ContractTests target
/// does not import SwiftUI.
enum HelpAudit {
    static func source() throws -> String {
        try read(
            from: root(),
            relative: "Sources/App/Commands.swift",
            what: "Commands.swift"
        )
    }

    static func help() throws -> String {
        try read(from: root(), relative: "docs/help.md", what: "docs/help.md")
    }

    /// Literal `Button("Title")` titles in menu-building code.
    static func buttonTitles(in source: String) -> [String] {
        matches(pattern: #"Button\("((?:[^"\\]|\\.)*)"\)"#, in: source)
    }

    /// `keyboardShortcut("key", modifiers: …)` pairs, rendered as the
    /// Help-doc glyph string (option → command → shift order, matching
    /// the doc's `⌥⌘0` / `⌘⇧L` convention).
    static func shortcuts(in source: String) -> [(key: String, glyph: String)] {
        let pattern = #"\.keyboardShortcut\("([^"]+)"(?:, modifiers: ([^)]+))?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let sourceNSString = source as NSString
        let range = NSRange(location: 0, length: sourceNSString.length)
        var result: [(key: String, glyph: String)] = []
        regex.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            let key = sourceNSString.substring(with: match.range(at: 1))
            let modifiers = match.range(at: 2).location == NSNotFound
                ? ""
                : sourceNSString.substring(with: match.range(at: 2))
            result.append((key, glyph(key: key, modifiers: modifiers)))
        }
        return result
    }

    // MARK: - Private

    private static func glyph(key: String, modifiers: String) -> String {
        var glyph = ""
        if modifiers.contains(".option") { glyph += "⌥" }
        if modifiers.contains(".command") { glyph += "⌘" }
        if modifiers.contains(".shift") { glyph += "⇧" }
        if modifiers.contains(".control") { glyph += "⌃" }
        let displayKey: String
        if key.count == 1, key.first?.isLetter == true {
            displayKey = key.uppercased()
        } else {
            displayKey = key
        }
        return glyph + displayKey
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let textNSString = text as NSString
        let range = NSRange(location: 0, length: textNSString.length)
        return regex.matches(in: text, range: range).map {
            textNSString.substring(with: $0.range(at: 1))
        }
    }

    /// Walk up from this test's source path to the checkout root.
    private static func root(from file: String = #filePath) -> URL {
        var dir = URL(fileURLWithPath: file).deletingLastPathComponent()
        for _ in 0..<8 {
            let commands = dir.appendingPathComponent("Sources/App/Commands.swift")
            let help = dir.appendingPathComponent("docs/help.md")
            let isRoot = FileManager.default.fileExists(atPath: commands.path)
                && FileManager.default.fileExists(atPath: help.path)
            if isRoot { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: ".")
    }

    private static func read(from root: URL, relative path: String, what: String) throws -> String {
        let url = root.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
