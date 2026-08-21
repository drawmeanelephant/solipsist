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
    var nounID: String? = nil
    var nounTitle: String? = nil
    var nounSourcePath: String? = nil

    init(
        sourceKind: SourceKind? = nil,
        nounKind: String? = nil,
        mailbox: String? = nil,
        nounID: String? = nil,
        nounTitle: String? = nil,
        nounSourcePath: String? = nil
    ) {
        self.sourceKind = sourceKind
        self.nounKind = nounKind
        self.mailbox = mailbox
        self.nounID = nounID
        self.nounTitle = nounTitle
        self.nounSourcePath = nounSourcePath
    }

    init(
        sourceKind: SourceKind?,
        noun: WorkspaceNoun?,
        mailbox: String?
    ) {
        self.sourceKind = sourceKind
        self.nounKind = noun?.kind
        self.mailbox = mailbox
        self.nounID = noun?.id
        self.nounTitle = noun?.title
        self.nounSourcePath = noun?.sourcePath
    }

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
            if nounKind == InspectorNounKind.target || nounKind == "edition" {
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

        case WorkspaceMailbox.plan, WorkspaceMailbox.activity, WorkspaceMailbox.contentAudit:
            sections.append(InspectorSection(id: InspectorSectionID.execution, title: "Execution Controls"))
            if sourceKind == .local {
                sections.append(InspectorSection(id: InspectorSectionID.profile, title: "Site Profile"))
            }

        case WorkspaceMailbox.remote:
            sections.append(InspectorSection(id: InspectorSectionID.execution, title: "Remote Sync & Execution"))

        case WorkspaceMailbox.issues, WorkspaceMailbox.pulls:
            sections.append(InspectorSection(id: InspectorSectionID.execution, title: "GitHub & Execution"))

        default:
            // Unknown mailbox (e.g. a trunk id): if a page is selected,
            // show that page's inspector; otherwise signal the trunk filter.
            if nounKind == InspectorNounKind.page {
                sections.append(InspectorSection(id: InspectorSectionID.page, title: "Page"))
            } else if sourceKind == .local {
                sections.append(InspectorSection(id: InspectorSectionID.profile, title: "Trunk Filter & Profile"))
            }
            sections.append(InspectorSection(id: InspectorSectionID.execution, title: "Execution"))
        }

        return sections
    }
}
