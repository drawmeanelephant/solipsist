import Foundation

/// #263: formatting verbs for the compose toolbar. Each verb compiles to a
/// pure buffer transform derived from Oliver's documented Markdown / Textile
/// syntax — no grammar invention, no parse. Boris/Oliver own semantics; this
/// only types markers faster than the author would.
enum ComposeFormat {
    case bold
    case italic
    case strikethrough
    /// Level 1–3: ATX `#` runs in Markdown, `hN.` labels in Textile.
    case heading(level: Int)
    case link
    case codeSpan
    case bulletList
    case numberedList
    case quote

    /// Heading levels offered in the toolbar menu.
    static let headingLevels = [1, 2, 3]

    /// Undo-stack action name for one toolbar press.
    var actionName: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .strikethrough: return "Strikethrough"
        case .heading(let level): return "Heading \(level)"
        case .link: return "Link"
        case .codeSpan: return "Code"
        case .bulletList: return "Bulleted List"
        case .numberedList: return "Numbered List"
        case .quote: return "Block Quote"
        }
    }

    /// Applies the format to a buffer at a UTF-16 selection. Returns nil
    /// when the language has no marker table for the verb (Cooklang).
    static func apply(
        _ format: ComposeFormat,
        to text: String,
        selectedRange rawSelection: NSRange,
        language: ComposeLanguage
    ) -> ComposeFormatEdit? {
        guard language.supportsFormatting else { return nil }
        let nsString = text as NSString
        let selection = clamp(rawSelection, length: nsString.length)
        switch format {
        case .bold, .italic, .strikethrough, .codeSpan:
            return wrapped(format, selection: selection, nsString: nsString, language: language)
        case .link:
            return linked(selection: selection, nsString: nsString, language: language)
        case .heading, .bulletList, .numberedList, .quote:
            return prefixed(format, selection: selection, nsString: nsString, language: language)
        }
    }
}

extension ComposeLanguage {
    /// Cooklang recipes are not prose; the formatting row hides itself.
    var supportsFormatting: Bool {
        self != .cooklang
    }
}

/// The outcome of a formatting transform (#263): which span of the original
/// buffer changes, what replaces it, and where the selection lands in the
/// resulting buffer. All offsets are UTF-16 (NSRange units).
struct ComposeFormatEdit {
    let replacedRange: NSRange
    let replacement: String
    let selection: NSRange
}

// MARK: - Transforms

private extension ComposeFormat {
    static func clamp(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        let end = min(max(range.location + range.length, location), length)
        return NSRange(location: location, length: end - location)
    }

    // MARK: Inline wraps

    /// Marker pairs per (verb, language), mirroring Oliver's documented
    /// surface. Nil = the pair does not exist for that frontend.
    static func inlinePair(
        _ format: ComposeFormat,
        language: ComposeLanguage
    ) -> (open: String, close: String)? {
        switch (format, language) {
        case (.bold, .markdown): return ("**", "**")
        case (.italic, .markdown): return ("*", "*")
        case (.strikethrough, .markdown): return ("~~", "~~")
        case (.codeSpan, .markdown): return ("`", "`")
        case (.bold, .textile): return ("*", "*")
        case (.italic, .textile): return ("_", "_")
        case (.strikethrough, .textile): return ("-", "-")
        case (.codeSpan, .textile): return ("@", "@")
        default: return nil
        }
    }

    /// Wrap: with a selection, enclose it and keep the enclosed text selected;
    /// with an empty selection, insert the marker pair and place the cursor
    /// inside.
    static func wrapped(
        _ format: ComposeFormat,
        selection: NSRange,
        nsString: NSString,
        language: ComposeLanguage
    ) -> ComposeFormatEdit? {
        guard let pair = inlinePair(format, language: language) else { return nil }
        let selected = nsString.substring(with: selection)
        let replacement = pair.open + selected + pair.close
        let openLength = (pair.open as NSString).length
        return ComposeFormatEdit(
            replacedRange: selection,
            replacement: replacement,
            selection: NSRange(location: selection.location + openLength, length: selected.count)
        )
    }

    /// Link: `[text](url)` (Markdown) or `"text":url` (Textile) with the
    /// text kept selected for typing over; an empty selection inserts the
    /// placeholder word selected.
    static func linked(
        selection: NSRange,
        nsString: NSString,
        language: ComposeLanguage
    ) -> ComposeFormatEdit? {
        let selected = nsString.substring(with: selection)
        let placeholder = selected.isEmpty ? "text" : selected
        let replacement: String
        switch language {
        case .markdown: replacement = "[\(placeholder)](url)"
        case .textile: replacement = "\"\(placeholder)\":url"
        case .cooklang: return nil
        }
        let lead = ((language == .markdown) ? "[" : "\"") as NSString
        return ComposeFormatEdit(
            replacedRange: selection,
            replacement: replacement,
            selection: NSRange(
                location: selection.location + lead.length,
                length: (placeholder as NSString).length
            )
        )
    }

    // MARK: Line prefixes

    /// One per-line prefix application: replace `range` (usually an empty
    /// span at the line start) with `text`.
    struct LineEdit {
        let range: NSRange
        let text: String
    }

    /// Expand the selection to whole lines and prefix each one.
    static func prefixed(
        _ format: ComposeFormat,
        selection: NSRange,
        nsString: NSString,
        language: ComposeLanguage
    ) -> ComposeFormatEdit? {
        let expanded = nsString.lineRange(for: selection)
        var edits: [LineEdit] = []

        if expanded.length == 0 {
            // Empty buffer (or clamped-to-end zero selection): insert the
            // prefix and leave the cursor after it.
            if let edit = lineEdit(
                format, line: expanded, counter: 1, nsString: nsString, language: language
            ) {
                edits.append(edit)
            }
        } else {
            appendEdits(
                format, into: &edits, span: expanded, nsString: nsString, language: language
            )
        }

        guard !edits.isEmpty, let replacement = assemble(edits, over: expanded, in: nsString)
        else { return nil }
        return ComposeFormatEdit(
            replacedRange: expanded,
            replacement: replacement,
            selection: mappedSelection(selection, edits: edits)
        )
    }

    /// Walks the lines of `span`, appending one edit per affected line.
    static func appendEdits(
        _ format: ComposeFormat,
        into edits: inout [LineEdit],
        span: NSRange,
        nsString: NSString,
        language: ComposeLanguage
    ) {
        let end = span.location + span.length
        var position = span.location
        var counter = 1
        while position < end {
            let newline = nsString.range(
                of: "\n",
                options: [],
                range: NSRange(location: position, length: end - position)
            )
            let lineContentEnd = newline.location == NSNotFound ? end : newline.location
            if let edit = lineEdit(
                format, line: NSRange(location: position, length: lineContentEnd - position),
                counter: counter, nsString: nsString, language: language
            ) {
                edits.append(edit)
            }
            counter += 1
            if newline.location == NSNotFound { break }
            position = newline.location + 1
        }
    }

    /// Prefix for a line: lists and quotes prepend; headings replace an
    /// existing same-family heading label so levels do not stack.
    static func lineEdit(
        _ format: ComposeFormat,
        line: NSRange,
        counter: Int,
        nsString: NSString,
        language: ComposeLanguage
    ) -> LineEdit? {
        let lineStart = line.location
        let prefix: String
        switch format {
        case .heading(let level):
            prefix = language == .markdown
                ? String(repeating: "#", count: level) + " "
                : "h\(level). "
        case .bulletList:
            prefix = language == .markdown ? "- " : "* "
        case .numberedList:
            prefix = language == .markdown ? "\(counter). " : "# "
        case .quote:
            prefix = language == .markdown ? "> " : "bq. "
        default:
            return nil
        }

        // Headings replace an existing heading label instead of stacking.
        if case .heading = format {
            let existingEnd = existingHeadingLabelEnd(line, nsString: nsString, language: language)
            if let existingEnd {
                return LineEdit(
                    range: NSRange(location: lineStart, length: existingEnd - lineStart),
                    text: prefix
                )
            }
        }

        return LineEdit(
            range: NSRange(location: lineStart, length: 0),
            text: prefix
        )
    }

    /// End offset of a heading label at the line start (`#…␣` in Markdown,
    /// `hN.`/`hN.␣` in Textile), or nil when the line does not open with one.
    static func existingHeadingLabelEnd(
        _ line: NSRange,
        nsString: NSString,
        language: ComposeLanguage
    ) -> Int? {
        func character(_ index: Int) -> unichar {
            index < NSMaxRange(line) ? nsString.character(at: index) : 0
        }
        if language == .markdown {
            var index = line.location
            var hashes = 0
            while character(index) == 35 { // "#"
                hashes += 1
                index += 1
            }
            guard hashes >= 1, hashes <= 6, character(index) == 32 else { return nil } // "␣"
            return index + 1
        }
        guard line.length >= 3,
              character(line.location) == 104, // "h"
              character(line.location + 1) >= 49, // "1"
              character(line.location + 1) <= 54, // "6"
              character(line.location + 2) == 46 // "."
        else { return nil }
        return character(line.location + 3) == 32 ? line.location + 4 : line.location + 3 // "␣"
    }

    /// Rebuild the expanded span: original content with each prefix spliced
    /// in at its line start.
    static func assemble(
        _ edits: [LineEdit],
        over expanded: NSRange,
        in nsString: NSString
    ) -> String? {
        let end = NSMaxRange(expanded)
        var pieces: [String] = []
        var cursor = expanded.location
        for edit in edits {
            if edit.range.location > cursor {
                pieces.append(
                    nsString.substring(
                        with: NSRange(location: cursor, length: edit.range.location - cursor)
                    )
                )
            }
            pieces.append(edit.text)
            cursor = max(cursor, NSMaxRange(edit.range))
        }
        if cursor < end {
            pieces.append(nsString.substring(with: NSRange(location: cursor, length: end - cursor)))
        }
        return pieces.joined()
    }

    /// Carets land after the inserted prefix; ranges stay mapped onto the
    /// same text, so a prefix inserted at the range's own line start does
    /// not push the range forward.
    static func mappedSelection(_ selection: NSRange, edits: [LineEdit]) -> NSRange {
        let caretsIncludeAtOffset = selection.length == 0

        func shifted(_ offset: Int) -> Int {
            var delta = 0
            for edit in edits {
                let counts = caretsIncludeAtOffset
                    ? edit.range.location <= offset
                    : edit.range.location < offset
                if counts {
                    delta += (edit.text as NSString).length - edit.range.length
                }
            }
            return offset + delta
        }

        let newStart = shifted(selection.location)
        let newEnd = shifted(selection.location + selection.length)
        return NSRange(location: newStart, length: newEnd - newStart)
    }
}
