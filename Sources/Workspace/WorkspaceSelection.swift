import Foundation

/// The single selected source plus the noun selected in play.
///
/// Drawer and companions **read** this. They never own it. Play writes `noun`;
/// chrome writes `sourceID` when the sidebar changes.
///
/// `noun` is an open pair of strings so the play / inspector lanes can agree
/// on kinds (`page`, `target`, `edition`, …) without editing this file.
struct WorkspaceSelection: Hashable, Sendable, Codable {
    var sourceID: SourceID?
    var noun: WorkspaceNoun?

    static let empty = WorkspaceSelection(sourceID: nil, noun: nil)
}

struct WorkspaceNoun: Hashable, Sendable, Codable {
    var kind: String
    var id: String
    var title: String
}
