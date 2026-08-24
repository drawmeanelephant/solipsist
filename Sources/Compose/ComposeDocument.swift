import Foundation
import Observation

/// The buffer behind the compose element: the source text, the frontend it
/// targets, and the save seam. Standalone by design — the window that hosts
/// it is a later card; this type only knows about a URL it may write to.
///
/// Boundary 4 of `AGENTS.md` applies: the buffer is never written to disk
/// except through an explicit `save()`. Nothing in the view layer calls
/// `save()` implicitly.
@MainActor
@Observable
final class ComposeDocument {
    /// The authored source text. Single source of truth.
    var text: String = "" {
        didSet {
            if text != oldValue {
                isDirty = true
                wordCount = Self.computeWordCount(for: text)
                // Auto-detect only until the language is pinned (by the
                // initial load or an explicit picker choice); never override
                // the user's selection mid-session.
                if !languageExplicit {
                    language = ComposeLanguage.detect(fileURL: fileURL, contents: text)
                }
            }
        }
    }

    /// The frontend this buffer targets. Auto-detected until pinned; the
    /// picker's binding writes through this setter, which pins it.
    var language: ComposeLanguage {
        didSet {
            languageExplicit = true
        }
    }

    /// Whether `language` has been pinned (initial load or explicit choice).
    private var languageExplicit: Bool

    /// The URL `save()` writes to. Nil until the host supplies one.
    var fileURL: URL?

    /// Whether the buffer differs from the last save/load.
    private(set) var isDirty = false

    /// Cursor position for the status bar (#228) and Go to Line (#238).
    /// Updated by `ComposeTextView.Coordinator` on every selection change.
    var cursorLine: Int = 1
    var cursorColumn: Int = 1
    /// #238: Total line count, updated alongside cursorLine for the Go to
    /// Line dialog.
    var totalLines: Int = 1
    /// Length of the current selection (0 = no selection). Used to show
    /// "42 selected" in place of the total character count.
    var selectedLength: Int = 0

    /// Word count via `NSString` `.byWords` (handles hyphens, contractions).
    /// Cached in `text.didSet` to avoid O(n) recomputation per keystroke.
    private(set) var wordCount: Int = 0

    private static func computeWordCount(for text: String) -> Int {
        let nsText = text as NSString
        var count = 0
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in count += 1 }
        return count
    }

    /// Character count (Swift grapheme clusters, matches `text.count`).
    var characterCount: Int { text.count }

    /// Formatted word count for the status bar, e.g. "1,234 words".
    var wordCountText: String {
        let formatted = formatCount(wordCount)
        return "\(formatted) \(wordCount == 1 ? "word" : "words")"
    }

    /// Formatted character count, e.g. "5,678 chars" or "42 selected".
    var characterCountText: String {
        if selectedLength > 0 {
            let formatted = formatCount(selectedLength)
            return "\(formatted) selected"
        }
        let formatted = formatCount(characterCount)
        return "\(formatted) chars"
    }

    /// Formatted cursor position, e.g. "Ln 12, Col 45".
    var cursorText: String {
        "Ln \(cursorLine), Col \(cursorColumn)"
    }

    /// Update cursor from an `NSRange` (UTF-16 offset) in the current `text`.
    func updateCursor(_ range: NSRange) {
        let nsText = text as NSString
        let length = nsText.length
        let location = min(max(range.location, 0), length)
        selectedLength = min(max(range.length, 0), length - location)
        // #238: Keep totalLines in sync for the Go to Line dialog.
        totalLines = max(1, nsText.components(separatedBy: "\n").count)

        if length == 0 {
            cursorLine = 1
            cursorColumn = 1
            return
        }
        if isTrailingNewLine(location: location, nsText: nsText) {
            cursorLine = countLines(in: nsText) + 1
            cursorColumn = 1
            return
        }
        let (line, lineStart) = lineAndColumnStart(for: location, in: nsText)
        cursorLine = max(1, line)
        cursorColumn = max(1, location - lineStart + 1)
    }

    private func isTrailingNewLine(location: Int, nsText: NSString) -> Bool {
        location == nsText.length && nsText.length > 0 && nsText.character(at: nsText.length - 1) == 10
    }

    private func countLines(in nsText: NSString) -> Int {
        var lines = 0
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, _, _ in lines += 1 }
        return lines
    }

    private func lineAndColumnStart(for location: Int, in nsText: NSString) -> (Int, Int) {
        var line = 1
        var lineStart = 0
        var found = false
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: [.byLines, .substringNotRequired]
        ) { _, subRange, _, stop in
            if NSLocationInRange(location, subRange) || location == NSMaxRange(subRange) {
                lineStart = subRange.location
                found = true
                stop.pointee = true
            } else if location < subRange.location {
                stop.pointee = true
            } else {
                line += 1
            }
        }
        if !found {
            let fallback = fallbackLineStart(for: location, in: nsText)
            return (fallback.line, fallback.start)
        }
        return (line, lineStart)
    }

    private func fallbackLineStart(for location: Int, in nsText: NSString) -> (line: Int, start: Int) {
        var fallbackLine = 1
        var fallbackStart = 0
        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: min(location, nsText.length)),
            options: [.byLines, .substringNotRequired]
        ) { _, subRange, _, _ in
            fallbackLine += 1
            fallbackStart = NSMaxRange(subRange)
        }
        var line = max(1, fallbackLine - 1)
        var start = fallbackStart
        if start > location {
            start = 0
            line = 1
        }
        return (line, start)
    }

    private func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// Human-readable state for the compose window's status line.
    var statusText: String {
        var parts: [String] = []
        if let fileURL {
            parts.append(fileURL.lastPathComponent)
        } else {
            parts.append("Untitled")
        }
        parts.append(language.displayName)
        if let frontmatter {
            parts.append("front matter: \(frontmatter.kind.rawValue)")
        }
        if isDirty {
            parts.append("edited")
        }
        return parts.joined(separator: " · ")
    }

    init(text: String = "", fileURL: URL? = nil, language: ComposeLanguage? = nil) {
        self.text = text
        self.fileURL = fileURL
        self.language = language ?? ComposeLanguage.detect(fileURL: fileURL, contents: text)
        self.languageExplicit = language != nil
        self.isDirty = false
        self.cursorLine = 1
        self.cursorColumn = 1
        self.selectedLength = 0
        self.wordCount = Self.computeWordCount(for: text)
    }

    /// The frontmatter dialect, mirroring Oliver's shared pre-pass
    /// (`src/frontmatter.zig`): YAML (`---`) / TOML (`+++`) sniffed at
    /// index 0, stripped before dispatch.
    enum FrontmatterKind: String {
        case yaml
        case toml
    }

    /// The raw frontmatter boundary. We expose it for highlighting and
    /// editing; we never fake a parsed view.
    struct Frontmatter: Equatable {
        let kind: FrontmatterKind
        /// Range of the whole `--- … ---` block, including both fences.
        let range: Range<String.Index>
        /// Raw payload between the fences (exclusive of the fence lines).
        let payload: Substring

        var payloadString: String { String(payload) }
    }

    /// Detects a `---`/`+++` frontmatter block anchored at index 0, matching
    /// Oliver's sniff-then-strip rule. An unclosed opener is *not* front
    /// matter (Oliver passes it through with an `unclosed-frontmatter`
    /// diagnostic).
    var frontmatter: Frontmatter? {
        Frontmatter.parse(in: text)
    }

    /// Explicit save. Returns false when there is nothing to save.
    @discardableResult
    func save() throws -> Bool {
        guard let fileURL, isDirty else { return false }
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        isDirty = false
        return true
    }

    /// Loads a file into the buffer (used by the future host; keeps the
    /// element testable in isolation).
    func load(from url: URL) throws {
        let loaded = try String(contentsOf: url, encoding: .utf8)
        fileURL = url
        text = loaded
        language = ComposeLanguage.detect(fileURL: url, contents: loaded)
        isDirty = false
        cursorLine = 1
        cursorColumn = 1
        selectedLength = 0
    }
}

extension ComposeDocument.Frontmatter {
    static func parse(in text: String) -> ComposeDocument.Frontmatter? {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).makeIterator()
        guard let first = lines.next() else { return nil }
        let fence = first.trimmingCharacters(in: .whitespaces)
        guard fence == "---" || fence == "+++" else { return nil }
        let kind: ComposeDocument.FrontmatterKind = fence == "---" ? .yaml : .toml

        // Reconstruct line offsets to find the closing fence.
        var index = text.startIndex
        var fenceLineStart: String.Index?
        var payloadStart: String.Index = text.startIndex
        var payloadEnd: String.Index = text.startIndex
        for (lineIndex, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if lineIndex == 0 {
                index = text.index(index, offsetBy: line.count)
                if index < text.endIndex, text[index] == "\n" {
                    index = text.index(after: index)
                }
                payloadStart = index
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == fence {
                fenceLineStart = index
                payloadEnd = index
                break
            }
            index = text.index(index, offsetBy: line.count)
            if index < text.endIndex, text[index] == "\n" {
                index = text.index(after: index)
            }
        }
        guard let fenceLineStart else { return nil }

        // `payloadEnd` is the fence line's start; back off the newline that
        // terminated the last content line so the payload excludes it.
        if payloadEnd > payloadStart, text[text.index(before: payloadEnd)] == "\n" {
            payloadEnd = text.index(before: payloadEnd)
        }

        let payload = text[payloadStart..<payloadEnd]
        // Range covers both fences: from the start of the document through
        // the closing fence line.
        let closeLineEnd = text.index(fenceLineStart, offsetBy: fence.count)
        let range = text.startIndex..<closeLineEnd
        return ComposeDocument.Frontmatter(kind: kind, range: range, payload: payload)
    }
}
