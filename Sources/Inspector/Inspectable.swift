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
    static let target = "target"
    static let execution = "execution"
}

enum InspectorNounKind {
    static let page = "page"
    static let profile = "profile"
    static let target = "target"
}

/// Sections implied by the current selection. The drawer reads this;
/// it does not write `WorkspaceStore.selection`.
struct InspectorSnapshot: Inspectable {
    var sourceKind: SourceKind?
    var nounKind: String?
    var mailbox: String?

    var inspectorSections: [InspectorSection] {
        guard let sourceKind else { return [] }
        var sections: [InspectorSection] = []

        let box = WorkspaceMailbox.display(mailbox)

        switch box {
        case WorkspaceMailbox.pages:
            if nounKind == InspectorNounKind.page {
                sections.append(InspectorSection(id: InspectorSectionID.page, title: "Page"))
            } else if sourceKind == .local {
                sections.append(InspectorSection(id: InspectorSectionID.profile, title: "Site Profile"))
            }
            sections.append(InspectorSection(id: InspectorSectionID.execution, title: "Execution"))

        case WorkspaceMailbox.outputs:
            if nounKind == InspectorNounKind.target {
                sections.append(InspectorSection(id: InspectorSectionID.target, title: "Target"))
            }
            if sourceKind == .local {
                sections.append(InspectorSection(id: InspectorSectionID.profile, title: "Targets & Profile"))
            }
            sections.append(InspectorSection(id: InspectorSectionID.execution, title: "Execution"))

        case WorkspaceMailbox.publish:
            if sourceKind == .local {
                sections.append(InspectorSection(id: InspectorSectionID.profile, title: "Publication Target"))
            }
            sections.append(InspectorSection(id: InspectorSectionID.execution, title: "Execution"))

        case WorkspaceMailbox.plan, WorkspaceMailbox.activity:
            sections.append(InspectorSection(id: InspectorSectionID.execution, title: "Execution Controls"))
            if sourceKind == .local {
                sections.append(InspectorSection(id: InspectorSectionID.profile, title: "Site Profile"))
            }

        default:
            // Unknown mailbox (e.g. a future trunk id): not the Pages
            // surface. Execution controls only, until M13-2 lands the
            // trunk folder filter.
            sections.append(InspectorSection(id: InspectorSectionID.execution, title: "Execution"))
        }

        return sections
    }
}
