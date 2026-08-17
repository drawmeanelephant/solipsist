import Foundation

/// A section the drawer can render. The Inspector lane owns the views;
/// chrome only asks the current selection for its sections.
struct InspectorSection: Identifiable, Sendable {
    let id: String
    let title: String
}

protocol Inspectable {
    var inspectorSections: [InspectorSection] { get }
}

enum InspectorSectionID {
    static let profile = "profile"
    static let page = "page"
    static let execution = "execution"
}

enum InspectorNounKind {
    static let page = "page"
    static let profile = "profile"
}

/// Sections implied by the current selection. The drawer reads this;
/// it does not write `WorkspaceStore.selection`.
struct InspectorSnapshot: Inspectable {
    var sourceKind: SourceKind?
    var nounKind: String?

    var inspectorSections: [InspectorSection] {
        guard let sourceKind else { return [] }
        var sections: [InspectorSection] = []
        if sourceKind == .local {
            sections.append(InspectorSection(id: InspectorSectionID.profile, title: "Profile"))
        }
        if nounKind == InspectorNounKind.page {
            sections.append(InspectorSection(id: InspectorSectionID.page, title: "Page"))
        }
        sections.append(InspectorSection(id: InspectorSectionID.execution, title: "Execution"))
        return sections
    }
}
