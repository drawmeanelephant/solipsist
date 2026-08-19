import Foundation

/// The single selected source, mailbox, and the noun selected in play.
///
/// Drawer and companions **read** this. They never own it. Play writes `noun`;
/// chrome writes `sourceID` + `mailbox` when the sidebar changes.
///
/// `noun` is an open pair of strings so the play / inspector lanes can agree
/// on kinds (`page`, `target`, `edition`, …) without editing this file.
/// `mailbox` is an open string. Persist the raw value; do not canonicalize.
struct WorkspaceSelection: Hashable, Sendable, Codable {
    var sourceID: SourceID?
    /// Open string. Persist raw. Nil when no source is selected.
    var mailbox: String? = nil
    var noun: WorkspaceNoun?

    var canEditPage: Bool { noun?.kind == "page" }

    static let empty = WorkspaceSelection(sourceID: nil, mailbox: nil, noun: nil)
}

struct WorkspaceNoun: Hashable, Sendable, Codable {
    var kind: String
    var id: String
    var title: String
    /// Content-root-relative path from `GraphNode.sourcePath`. Page nouns only.
    var sourcePath: String? = nil
}

/// Sidebar `List` selection. Lives here so ContractTests can construct it
/// without importing SwiftUI.
struct MailboxRowID: Hashable, Sendable {
    var sourceID: SourceID
    var mailbox: String
}

/// M10 mailbox tokens. Open vocabulary — not a closed enum.
/// M10 UI admits only `all`; unknown values (a future trunk id)
/// stay themselves and are never rewritten to `pages` in the plist.
enum WorkspaceMailbox {
    static let pages = "pages"
    static let outputs = "outputs"
    static let publish = "publish"
    static let plan = "plan"
    static let activity = "activity"
    static let contentAudit = "content-audit"
    /// GitHub-source-only mailbox (M15): branch, ahead/behind, Sync.
    /// Deliberately not in `all` — Local sources never see a Remote row.
    static let remote = "remote"
    /// GitHub-source-only mailbox (M16-4 / #185): the repo's open
    /// issues. Same pattern as `remote` — never in `all`.
    static let issues = "issues"
    /// GitHub-source-only mailbox (M17 / #192): the repo's open pull
    /// requests, via `/pulls` (not the issues-list filter). Same
    /// pattern — never in `all`.
    static let pulls = "pulls"

    static let all: [String] = [pages, outputs, publish, plan, activity, contentAudit]
    static let defaultMailbox = pages

    static func isKnown(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return all.contains(raw)
    }

    /// Center-switch token. Known mailboxes pass through; nil (no mailbox
    /// chosen yet) is the default Pages surface; unknown (including a
    /// future trunk id) stays itself — it is **not** Pages. Does not
    /// write back, and the switch never treats unknown as Pages.
    static func display(_ raw: String?) -> String {
        guard let raw else { return defaultMailbox }
        return raw
    }

    static func displayName(_ raw: String) -> String {
        switch raw {
        case pages: return "Pages"
        case outputs: return "Outputs"
        case publish: return "Publish"
        case plan: return "Plan"
        case activity: return "Activity"
        case contentAudit: return "Content Audit"
        case remote: return "Remote"
        case issues: return "Issues"
        case pulls: return "Pull Requests"
        default: return raw
        }
    }

    static func symbolName(_ raw: String) -> String {
        switch raw {
        case pages: return "doc.text"
        case outputs: return "square.stack"
        case publish: return "paperplane"
        case plan: return "doc.plaintext"
        case activity: return "clock"
        case contentAudit: return "checkmark.shield"
        case remote: return "arrow.triangle.2.circlepath"
        case issues: return "exclamationmark.circle"
        case pulls: return "arrow.triangle.branch"
        default: return "folder"
        }
    }

    /// Sidebar row list for one source. Local sources get the M10 set;
    /// GitHub sources additionally get the Remote, Issues, and Pull
    /// Requests mailboxes (github-only rows).
    static func all(for item: SourceItem) -> [String] {
        switch item.kind {
        case .github: return all + [remote, issues, pulls]
        case .local: return all
        }
    }
}

/// Pure selection transitions. `WorkspaceStore` calls these, then
/// `persist()` if the value changed. ContractTests compile this file
/// already — do not add `WorkspaceStore.swift` to the test target.
enum WorkspaceSelectionRules {
    static func selectSource(_ current: WorkspaceSelection, id: SourceID?) -> WorkspaceSelection {
        var next = current
        let changed = current.sourceID != id
        next.sourceID = id
        if id == nil {
            next.mailbox = nil
            next.noun = nil
        } else if changed {
            next.mailbox = WorkspaceMailbox.defaultMailbox
            next.noun = nil
        }
        return next
    }

    static func selectMailbox(_ current: WorkspaceSelection, mailbox: String) -> WorkspaceSelection {
        guard current.sourceID != nil else { return current }
        // Store what chrome wrote (one of `all` in M10). Do not coerce unknown → pages.
        guard current.mailbox != mailbox else { return current }
        var next = current
        next.mailbox = mailbox
        next.noun = nil
        return next
    }

    static func select(_ current: WorkspaceSelection, id: SourceID, mailbox: String) -> WorkspaceSelection {
        var next = current
        let sourceChanged = current.sourceID != id
        let mailboxChanged = current.mailbox != mailbox
        next.sourceID = id
        next.mailbox = mailbox
        if sourceChanged || mailboxChanged {
            next.noun = nil
        }
        return next
    }

    static func restore(selected: SourceID?, mailbox: String?, available: Set<SourceID>) -> WorkspaceSelection {
        guard let selected, available.contains(selected) else {
            return .empty
        }
        // Raw mailbox. Do not run `display` here.
        return WorkspaceSelection(sourceID: selected, mailbox: mailbox, noun: nil)
    }
}
