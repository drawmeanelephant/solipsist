import AppKit
import Foundation

/// A paint style for one highlight rule.
struct ComposeHighlightStyle {
    var color: NSColor
    var bold = false
    var italic = false

    static let plain = ComposeHighlightStyle(color: .labelColor)
}

/// One ordered highlight rule: a regex plus the style applied to every match.
/// Rules apply in array order; later rules repaint over earlier ones, so
/// region rules (fenced code, front matter) must come last.
struct ComposeHighlightRule {
    let pattern: String
    let style: ComposeHighlightStyle
    let options: NSRegularExpression.Options
}

/// Token highlighting for the compose element.
///
/// This is **not** a parser and never will be. The grammar for all three
/// frontends lives in Oliver (the clean-room library behind Boris); these
/// rules are a heuristic paint layer derived from Oliver's documented
/// language surface (`docs/FEATURE-MATRIX.md`, `docs/TEXTILE-PARITY.md`,
/// `docs/COOKLANG.md`). Where Oliver pins a behavior, we match its shape;
/// where the shape is ambiguous, we prefer the most common reading and
/// record it in the rule comment.
enum ComposeHighlighter {
    // MARK: - Public API

    /// `fontSize` (#264): the reading-comfort ladder resizes the whole
    /// paint; defaults keep every existing caller compiling.
    static func highlight(
        _ text: String,
        language: ComposeLanguage,
        fontSize: CGFloat = 13
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font(ofSize: fontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        for rule in rules(for: language) {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }
            let full = NSRange(location: 0, length: (text as NSString).length)
            regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                paint(rule.style, over: match.range, in: result, fontSize: fontSize)
            }
        }

        // #235: Autolink post-processing — paint the angle brackets of
        // autolinks back to plain text so the URL is easier to read.
        if language == .markdown {
            paintAutolinkBrackets(text, in: result, fontSize: fontSize)
        }

        // Front matter is data, not content: paint it last so no inner rule
        // (a `#` in YAML, an `@` in a cooklang ingredient list) bleeds in.
        if let frontmatter = ComposeDocument.Frontmatter.parse(in: text) {
            let lower = text.utf16.distance(from: text.utf16.startIndex, to: frontmatter.range.lowerBound)
            let upper = text.utf16.distance(from: text.utf16.startIndex, to: frontmatter.range.upperBound)
            paint(
                ComposeHighlightStyle(color: .systemGray, italic: true),
                over: NSRange(location: lower, length: upper - lower),
                in: result,
                fontSize: fontSize
            )
        }

        return result
    }

    static func rules(for language: ComposeLanguage) -> [ComposeHighlightRule] {
        switch language {
        case .markdown: return markdownRules
        case .textile: return textileRules
        case .cooklang: return cooklangRules
        }
    }

    // MARK: - Incremental repaint (LATER-3.2)

    /// The minimal changed range between two buffer versions (common prefix
    /// + common suffix diff). `location`/`length` are UTF-16 offsets in
    /// `new`. Pure and deterministic for tests.
    static func changedRange(old: String, new: String) -> NSRange {
        let nsOld = old as NSString
        let nsNew = new as NSString
        let maxPrefix = min(nsOld.length, nsNew.length)
        var prefix = 0
        while prefix < maxPrefix, nsOld.character(at: prefix) == nsNew.character(at: prefix) {
            prefix += 1
        }
        let maxSuffix = min(nsOld.length - prefix, nsNew.length - prefix)
        var suffix = 0
        while suffix < maxSuffix {
            let oldIndex = nsOld.length - 1 - suffix
            let newIndex = nsNew.length - 1 - suffix
            guard nsOld.character(at: oldIndex) == nsNew.character(at: newIndex) else { break }
            suffix += 1
        }
        return NSRange(location: prefix, length: nsNew.length - prefix - suffix)
    }

    /// Restyles only `range` against the existing full-buffer paint. Rules
    /// are matched over the **whole** buffer (anchors and multi-line regions
    /// need context) but only the intersection with `range` is painted, so a
    /// keystroke in a large buffer no longer restyles (and re-lays-out) text
    /// off-screen. Callers wrap the storage edits in begin/endEditing and
    /// pass the buffer the storage currently holds.
    static func repaint(
        _ text: String,
        language: ComposeLanguage,
        in range: NSRange,
        storage: NSMutableAttributedString,
        fontSize: CGFloat = 13
    ) {
        guard range.location != NSNotFound, range.length > 0,
              range.upperBound <= (text as NSString).length
        else { return }

        storage.addAttributes(
            [.font: font(ofSize: fontSize), .foregroundColor: NSColor.labelColor],
            range: range
        )

        let full = NSRange(location: 0, length: (text as NSString).length)
        for rule in rules(for: language) {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else {
                continue
            }
            regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                let hit = NSIntersectionRange(match.range, range)
                guard hit.length > 0 else { return }
                paint(rule.style, over: hit, in: storage, fontSize: fontSize)
            }
        }

        // Front matter is data, not content: paint it last (same rule as
        // the full paint) when the repaint range touches it.
        if let frontmatter = ComposeDocument.Frontmatter.parse(in: text) {
            let lower = text.utf16.distance(from: text.utf16.startIndex, to: frontmatter.range.lowerBound)
            let upper = text.utf16.distance(from: text.utf16.startIndex, to: frontmatter.range.upperBound)
            let fmRange = NSRange(location: lower, length: upper - lower)
            let hit = NSIntersectionRange(fmRange, range)
            if hit.length > 0 {
                paint(
                    ComposeHighlightStyle(color: .systemGray, italic: true),
                    over: hit,
                    in: storage,
                    fontSize: fontSize
                )
            }
        }

        // #235: Autolink bracket post-processing for the repainted range.
        if language == .markdown {
            repaintAutolinkBrackets(text, in: range, storage: storage, fontSize: fontSize)
        }
    }

    /// #235: Repaints the angle brackets of autolink matches within `range`
    /// back to plain text. Extracted from `repaint` to keep cyclomatic
    /// complexity under the lint threshold.
    private static func repaintAutolinkBrackets(
        _ text: String,
        in range: NSRange,
        storage: NSMutableAttributedString,
        fontSize: CGFloat
    ) {
        let nsText = text as NSString
        guard let regex = try? NSRegularExpression(pattern: "<[^<>\\s]+>", options: []) else { return }
        let full = NSRange(location: 0, length: nsText.length)
        let plain = ComposeHighlightStyle.plain
        regex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, match.range.length > 2 else { return }
            let leadingBracket = NSRange(location: match.range.location, length: 1)
            let trailingBracket = NSRange(
                location: match.range.location + match.range.length - 1,
                length: 1
            )
            let hitLead = NSIntersectionRange(leadingBracket, range)
            if hitLead.length > 0 {
                paint(plain, over: hitLead, in: storage, fontSize: fontSize)
            }
            let hitTrail = NSIntersectionRange(trailingBracket, range)
            if hitTrail.length > 0 {
                paint(plain, over: hitTrail, in: storage, fontSize: fontSize)
            }
        }
    }

    // MARK: - Palette

    private static let heading = ComposeHighlightStyle(color: .systemPurple, bold: true)
    private static let strong = ComposeHighlightStyle(color: .systemRed, bold: true)
    private static let emphasis = ComposeHighlightStyle(color: .systemOrange)
    private static let code = ComposeHighlightStyle(color: .systemGreen)
    private static let link = ComposeHighlightStyle(color: .systemBlue)
    private static let image = ComposeHighlightStyle(color: .systemTeal)
    private static let table = ComposeHighlightStyle(color: .systemTeal)
    private static let marker = ComposeHighlightStyle(color: .systemPurple)
    private static let quote = ComposeHighlightStyle(color: .systemGray)
    private static let footnote = ComposeHighlightStyle(color: .systemBrown)
    private static let callout = ComposeHighlightStyle(color: .systemYellow, bold: true)
    private static let ingredient = ComposeHighlightStyle(color: .systemGreen)
    private static let cookware = ComposeHighlightStyle(color: .systemBlue)
    private static let timer = ComposeHighlightStyle(color: .systemOrange)
    private static let note = ComposeHighlightStyle(color: .systemTeal)
    private static let comment = ComposeHighlightStyle(color: .secondaryLabelColor, italic: true)

    private static func font(ofSize fontSize: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    // MARK: - Markdown (CommonMark 0.31.2 + Oliver's opt-in extensions)

    private static let markdownRules: [ComposeHighlightRule] = [
        // #235: HTML comments — paint first so inline rules paint over them
        // inside non-comment regions.
        rule(#"<!--[\s\S]*?-->"#, comment, dotMatches: true),
        // Inline: emphasis family first, widest delimiter runs first.
        rule(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)\1"#, strong),
        rule(#"(?<![*_])(\*\*|__)(?=\S)(.+?)(?<=\S)\1(?!\1)(?![*_])"#, strong),
        rule(#"(?<![*_])(\*|_)(?!\1)(?=\S)(.+?)(?<=\S)\1(?!\1)(?![*_])"#, emphasis),
        rule(#"~~[^~\n]+~~"#, emphasis),
        // #235: Code spans — match across newlines so **bold** inside
        // multi-line backtick spans stays green (code wins by paint order).
        rule(#"`[^`]+`"#, code),
        rule(#"\[([^\]\n]+)\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)"#, link),
        rule(#"\[([^\]\n]+)\](?:\[([^\]\n]*)\])?"#, link),
        rule(#"!\[([^\]\n]*)\]\(([^)\s]+)(?:\s+["'][^"']*["'])?\)"#, image),
        rule(#"!\[([^\]\n]*)\](?:\[([^\]\n]*)\])?"#, image),
        // Oliver extension: Obsidian [[wikilinks]] (docs/WIKILINKS.md).
        rule(#"\[\[([^\]\n|]+)(?:\|([^\]\n]+))?\]\]"#, image),
        rule(#"<[^<>\s]+>"#, link),
        rule(#"\[\^[^\]]+\]"#, footnote),
        rule(#"^[ \t]*[-*+] \[[ xX]\]"#, ingredient),
        // Blocks.
        // Oliver extension: > [!note] callouts (docs/CALLOUTS.md).
        rule(#"^>[ \t]*\[![A-Za-z0-9-]+\][^\n]*"#, callout),
        // #235: ATX headings require at least one space after the hashes
        // so YAML comments (# inside front-matter block scalars) are not
        // painted as headings.
        rule(#"^(#{1,6})[ \t]+[^\n]*"#, heading, anchors: true),
        rule(#"^[ \t]*=+[ \t]*$"#, heading, anchors: true),
        rule(#"^[ \t]*(-{3,}|\*{3,}|_{3,})[ \t]*$"#, quote, anchors: true),
        rule(#"^>[ \t]?"#, quote, anchors: true),
        rule(#"^[ \t]*([-*+]|\d+[.)])[ \t]+"#, marker, anchors: true),
        rule(#"^[ \t]*\|.*\|[ \t]*$"#, table, anchors: true),
        rule(#"^\[\^[^\]]+\]:"#, footnote, anchors: true),
        // Regions last: fenced code (```` and `~~~`), indented code.
        rule(#"(?:^|\n)([`~]{3,})[^\n]*\n[\s\S]*?(?:\n|\z)\1[ \t]*(?:\n|\z)"#, code, dotMatches: true),
        rule(#"(?:^|\n)([ \t]{4,}[^\n]*(?:\n[ \t]{4,}[^\n]*)*)"#, code, dotMatches: true),
    ]

    // MARK: - Textile (Textile 2 surface, docs/TEXTILE-PARITY.md)

    private static let textileRules: [ComposeHighlightRule] = [
        // == escaping and @code@ first (they suspend all other formatting).
        rule(#"==[^\n]*=="#, quote),
        rule(#"@[^@\n]+@"#, code),
        // Phrase family: doubled/long runs before single runs.
        rule(#"(?<![*_])(\*\*|__)(?=\S)(.+?)(?<=\S)\1(?!\1)(?![*_])"#, strong),
        rule(#"(?<![*_])(\*|_)(?!\1)(?=\S)(.+?)(?<=\S)\1(?!\1)(?![*_])"#, emphasis),
        rule(#"(\+\+[^+]{2,}\+\+|--[^-]{2,}--)"#, quote),
        rule(#"(-[^-]+-|\+[^+]+)"#, emphasis),
        rule(#"\^[^^\n]{1,}\^"#, footnote),
        rule(#"~[^~\n]{1,}~"#, footnote),
        rule(#"%[^%\n]{1,}%"#, quote),
        rule(#"\?\?[^?\n]{1,}\?\?"#, footnote),
        rule(#"[A-Z]{2,}\([^)\n]+\)"#, footnote),
        // Textile 2 {...} character macros.
        rule(#"\{[^}\n]{1,4}\}"#, quote),
        // "text":url links and !url! images.
        rule(#""([^"\n]+)":([^\s)]+)"#, link),
        rule(#"!([^!\n]+)!(?::([^\s]+))?"#, image),
        rule(#"\[\d+\]"#, footnote),
        // Blocks: signatures, list markers, tables.
        rule(#"^bq\.:[^\s]+"#, link, anchors: true),
        rule(#"^(h[1-6]\.|p\.{1,2}|bq\.{1,2}|bc\.{1,2}|pre\.{1,2}|dl\.|notextile\.{1,2}|clear[<>]?\.|fn\d+\.)"#, marker, anchors: true),
        rule(#"^[ \t]*[*#]+"#, marker, anchors: true),
        rule(#"^[ \t]*\|.*\|[ \t]*$"#, table, anchors: true),
        rule(#"^fn\d+\."#, footnote, anchors: true),
    ]

    // MARK: - Cooklang (typed Recipe surface, docs/COOKLANG.md)

    private static let cooklangRules: [ComposeHighlightRule] = [
        // Token family first so line-level paints (notes/comments) win over
        // tokens that happen to sit inside them.
        // Ingredients: @name, @multi word{quantity%unit}, recipe refs @./path.
        rule(#"@[^\s@#~{]+(?:[ \t]+[^\s@#~{]+)*[ \t]*\{[^}\n]*\}"#, ingredient),
        rule(#"@[^\s@#~{]+"#, ingredient),
        // Cookware: #name / #multi word{quantity}.
        rule(#"#[^\s@#~{]+(?:[ \t]+[^\s@#~{]+)*[ \t]*\{[^}\n]*\}"#, cookware),
        rule(#"#[^\s@#~{]+"#, cookware),
        // Timers: ~name{3%minutes} / ~{25%minutes} / ~rest.
        rule(#"~\{[^}\n]*\}"#, timer),
        rule(#"~[^\s@#~{]+(?:\{[^}\n]*\})?"#, timer),
        // #235: Notes — match consecutive > lines as a single block so the
        // note paint covers the entire note, not individual lines.
        rule(#"(?:^>[^\n]*\n?)+"#, note, anchors: true, dotMatches: true),
        rule(#"^=+[ \t]*[^\n]*"#, heading, anchors: true),
        rule(#"^--[^\n]*"#, comment, anchors: true),
        rule(#"\[-[^]*?-\]"#, comment, dotMatches: true),
    ]

    // MARK: - Rule helpers

    private static func rule(
        _ pattern: String,
        _ style: ComposeHighlightStyle,
        anchors: Bool = false,
        dotMatches: Bool = false
    ) -> ComposeHighlightRule {
        var options: NSRegularExpression.Options = []
        if anchors { options.insert(.anchorsMatchLines) }
        if dotMatches { options.insert(.dotMatchesLineSeparators) }
        return ComposeHighlightRule(pattern: pattern, style: style, options: options)
    }

    private static func paint(
        _ style: ComposeHighlightStyle,
        over range: NSRange,
        in attributed: NSMutableAttributedString,
        fontSize: CGFloat
    ) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        attributed.addAttribute(.foregroundColor, value: style.color, range: range)
        if style.bold {
            attributed.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
                range: range
            )
        } else if style.italic {
            let italic = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
                .withTraits(.italic)
            attributed.addAttribute(.font, value: italic, range: range)
        }
    }
}

extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

// MARK: - #235 Autolink bracket post-processing

private extension ComposeHighlighter {
    /// #235: Paints the angle brackets of autolinks (`<url>`) back to plain
    /// text so the URL itself is easier to read. Runs after all rules have
    /// been applied. Only fires for Markdown (autolinks are a CommonMark
    /// feature; Cooklang and Textile use different link syntax).
    static func paintAutolinkBrackets(
        _ text: String,
        in attributed: NSMutableAttributedString,
        fontSize: CGFloat
    ) {
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        // Match autolinks: <scheme:path> or <user@host>
        guard let regex = try? NSRegularExpression(
            pattern: "<[^<>\\s]+>",
            options: []
        ) else { return }
        let plain = ComposeHighlightStyle.plain
        regex.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match, match.range.length > 2 else { return }
            let leadingBracket = NSRange(location: match.range.location, length: 1)
            let trailingBracket = NSRange(
                location: match.range.location + match.range.length - 1,
                length: 1
            )
            paint(plain, over: leadingBracket, in: attributed, fontSize: fontSize)
            paint(plain, over: trailingBracket, in: attributed, fontSize: fontSize)
        }
    }
}
