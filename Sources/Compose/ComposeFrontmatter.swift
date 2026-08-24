import Foundation

/// The closed front-matter key set, per `boris-frontmatter-1.schema.json`
/// at the pinned kit (`6b930b7`): nine keys, `additionalProperties: false`
/// is normative. NOTE: the ROADMAP / capabilities "8-key (…role…)" line is
/// stale — the schema has no `role`; it has `published_at` and `summary`.
/// Servings is the one Cooklang-convention exception (authored string).
enum ComposeFrontmatter {
    static let scalarKeys = ["id", "title", "parent", "status", "published_at", "summary", "servings"]
    static let keys = scalarKeys + ["tags", "relations"]

    struct Relation: Equatable, Hashable, Sendable {
        var kind: String
        var target: String
    }

    struct Fields: Equatable, Sendable {
        var id = ""
        var title = ""
        var parent = ""
        var status = ""
        var publishedAt = ""
        var summary = ""
        var servings = ""
        var tags: [String] = []
        var relations: [Relation] = []

        static let empty = Fields()
    }

    /// #266: front-matter pane visibility rule — seeded from presence on
    /// page load; once the author toggles the pane, their choice wins until
    /// the next page.
    static func paneVisibility(current: Bool, present: Bool, userToggled: Bool) -> Bool {
        userToggled ? current : present
    }

    // MARK: - Parse (minimal YAML subset for the closed keys)

    /// Reads the closed keys out of a front-matter payload. Unknown keys are
    /// ignored (never guessed); both flow (`tags: [a, b]`) and block
    /// (`tags:\n  - a`) list styles are accepted, matching the corpora.
    static func parse(payload: String) -> Fields {
        var fields = Fields()
        let lines = payload.components(separatedBy: "\n")
        var lineIndex = 0
        while lineIndex < lines.count {
            let raw = lines[lineIndex]
            guard !raw.isEmpty, !raw.hasPrefix(" "), !raw.hasPrefix("\t"),
                  let colon = raw.firstIndex(of: ":")
            else {
                lineIndex += 1
                continue
            }
            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            lineIndex += consume(key: key, value: value, lines: lines, startIndex: lineIndex, fields: &fields)
        }
        return fields
    }

    /// Applies one `key: value` line to the fields, returning the number of
    /// lines consumed (1 for scalars and flow lists; the whole block for
    /// block lists).
    private static func consume(
        key: String,
        value: String,
        lines: [String],
        startIndex: Int,
        fields: inout Fields
    ) -> Int {
        switch key {
        case "tags", "relations":
            return consumeList(key: key, value: value, lines: lines, startIndex: startIndex, fields: &fields)
        case "id": fields.id = value
        case "title": fields.title = value
        case "parent": fields.parent = value
        case "status": fields.status = value
        case "published_at": fields.publishedAt = value
        case "summary": fields.summary = value
        case "servings": fields.servings = value
        default:
            break
        }
        return 1
    }

    /// Handles `tags:` / `relations:` in either flow or block style.
    private static func consumeList(
        key: String,
        value: String,
        lines: [String],
        startIndex: Int,
        fields: inout Fields
    ) -> Int {
        if isFlowList(value) {
            let body = String(value.dropFirst().dropLast())
            if key == "tags" {
                fields.tags = flowList(body)
            } else {
                fields.relations = flowRelations(body)
            }
            return 1
        }
        if key == "tags" {
            fields.tags = parseBlockList(lines, startIndex: startIndex + 1)
            return fields.tags.count + 1
        }
        let result = parseBlockRelations(lines, startIndex: startIndex + 1)
        fields.relations = result.relations
        return result.nextIndex - startIndex
    }

    // MARK: - Apply (overlay write-back)

    /// Rewrites only the closed keys in a payload, preserving every other
    /// line (unknown keys survive — the schema rejects them, but the form
    /// never destroys them). Blocks are emitted in canonical block style;
    /// empty fields omit their key entirely (absence == null per the schema).
    static func apply(_ fields: Fields, to payload: String) -> String {
        let lines = payload.isEmpty ? [] : payload.components(separatedBy: "\n")
        var seen = Set<String>()
        var out: [String] = []
        var remaining = lines[...]
        while let head = remaining.first {
            remaining = remaining.dropFirst(rewriteLine(head, remaining: remaining, fields: fields, seen: &seen, out: &out))
        }
        appendUnseen(fields, seen: seen, into: &out)
        return out.joined(separator: "\n")
    }

    /// Rewrites one source line, returning how many lines it consumed.
    private static func rewriteLine(
        _ raw: String,
        remaining: ArraySlice<String>,
        fields: Fields,
        seen: inout Set<String>,
        out: inout [String]
    ) -> Int {
        guard
            !raw.isEmpty,
            !raw.hasPrefix(" "),
            !raw.hasPrefix("\t"),
            let colon = raw.firstIndex(of: ":")
        else {
            out.append(raw)
            return 1
        }
        let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
        guard keys.contains(key) else {
            out.append(raw)
            return 1
        }
        seen.insert(key)
        if let block = block(for: key, fields: fields) {
            out.append(contentsOf: block)
        }
        if key == "tags" || key == "relations" {
            // The key line plus its old block lines.
            return skipOldBlock(remaining.dropFirst()) + 1
        }
        return 1
    }

    /// Appends blocks for closed keys absent from the source, preserving the
    /// canonical key order.
    private static func appendUnseen(_ fields: Fields, seen: Set<String>, into out: inout [String]) {
        for key in keys where !seen.contains(key) {
            if let block = block(for: key, fields: fields) {
                out.append(contentsOf: block)
            }
        }
    }

    // MARK: - Block emission

    static func block(for key: String, fields: Fields) -> [String]? {
        switch key {
        case "tags", "relations":
            return listBlock(key: key, fields: fields)
        case "id": return scalarBlock(key, fields.id)
        case "title": return scalarBlock(key, fields.title)
        case "parent": return scalarBlock(key, fields.parent)
        case "status": return scalarBlock(key, fields.status)
        case "published_at": return scalarBlock(key, fields.publishedAt)
        case "summary": return scalarBlock(key, fields.summary)
        case "servings": return scalarBlock(key, fields.servings)
        default:
            return nil
        }
    }

    /// Canonical block emission for the two list keys.
    private static func listBlock(key: String, fields: Fields) -> [String]? {
        if key == "tags" {
            guard !fields.tags.isEmpty else { return nil }
            return ["tags:"] + fields.tags.map { "  - \($0)" }
        }
        guard !fields.relations.isEmpty else { return nil }
        var lines = ["relations:"]
        for relation in fields.relations {
            lines.append("  - kind: \(relation.kind)")
            lines.append("    target: \(relation.target)")
        }
        return lines
    }

    private static func scalarBlock(_ key: String, _ value: String) -> [String]? {
        value.isEmpty ? nil : ["\(key): \(value)"]
    }

    // MARK: - Subset helpers

    /// `[a, b]`-style list value?
    private static func isFlowList(_ value: String) -> Bool {
        value.hasPrefix("[") && value.hasSuffix("]")
    }

    /// Splits a flow list body: `a, b` → `["a", "b"]`.
    private static func flowList(_ body: String) -> [String] {
        body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// `kind=target` (the corpus's relations flow pair) → Relation.
    private static func flowRelations(_ body: String) -> [Relation] {
        flowList(body).map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                return Relation(kind: pair, target: "")
            }
            return Relation(
                kind: String(parts[0]).trimmingCharacters(in: .whitespaces),
                target: String(parts[1]).trimmingCharacters(in: .whitespaces)
            )
        }
    }

    /// Consumes `- item` lines after a `tags:` key; returns the items.
    private static func parseBlockList(_ lines: [String], startIndex: Int) -> [String] {
        var items: [String] = []
        var index = startIndex
        while index < lines.count {
            let item = lines[index].trimmingCharacters(in: .whitespaces)
            guard item.hasPrefix("-") else { break }
            items.append(String(item.dropFirst()).trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return items
    }

    /// Consumes a `relations:` block (`- kind: x` / `target: y` pairs) and
    /// returns the relations plus the first unconsumed line index.
    private static func parseBlockRelations(_ lines: [String], startIndex: Int) -> (relations: [Relation], nextIndex: Int) {
        var relations: [Relation] = []
        var index = startIndex
        while index < lines.count {
            let dashLine = lines[index].trimmingCharacters(in: .whitespaces)
            guard dashLine.hasPrefix("-") else { break }
            var kind = ""
            var target = ""
            inlineKV(String(dashLine.dropFirst()), into: &kind, target: &target)
            index += 1
            while index < lines.count {
                let sub = lines[index]
                let trimmed = sub.trimmingCharacters(in: .whitespaces)
                // Sub-lines are deeper-indented `kind:` / `target:` pairs; a
                // shallower dash starts the next relation.
                guard (sub.hasPrefix(" ") || sub.hasPrefix("\t")), !trimmed.hasPrefix("-") else { break }
                if trimmed.hasPrefix("kind:") { kind = afterColon(trimmed) }
                if trimmed.hasPrefix("target:") { target = afterColon(trimmed) }
                index += 1
            }
            relations.append(Relation(kind: kind, target: target))
        }
        return (relations, index)
    }

    /// Counts the old block lines (`- item` / indented sub-lines) after a
    /// replaced `tags:` / `relations:` key.
    private static func skipOldBlock(_ remaining: ArraySlice<String>) -> Int {
        var count = 0
        for raw in remaining {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("-") || raw.hasPrefix(" ") || raw.hasPrefix("\t") || trimmed.isEmpty {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// Parses `kind: x` / `target: y` off a dash line (`- kind: x`).
    private static func inlineKV(_ text: String, into kind: inout String, target: inout String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("kind:") { kind = afterColon(trimmed) }
        if trimmed.hasPrefix("target:") { target = afterColon(trimmed) }
    }

    private static func afterColon(_ line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return "" }
        return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
    }
}
