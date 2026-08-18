import SwiftUI

/// Right drawer. Renders inspector sections for the current selection; it
/// does not own that selection. The Inspector lane fills the sections.
struct InspectorDrawer: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        Group {
            if store.selection.sourceID == nil {
                drawerNote("Select a source to inspect its options.")
            } else {
                let snapshot = InspectorSnapshot(
                    sourceKind: store.selectedSource?.kind,
                    nounKind: store.selection.noun?.kind
                )
                if snapshot.inspectorSections.isEmpty {
                    drawerNote("Select a source to inspect its options.")
                } else {
                    Form {
                        ForEach(snapshot.inspectorSections) { section in
                            Section(section.title) {
                                sectionBody(section)
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sectionBody(_ section: InspectorSection) -> some View {
        switch section.id {
        case InspectorSectionID.profile:
            if let item = store.selectedSource, case .local(let source) = item {
                ProfileSection(source: source)
            } else {
                Text("Profile is available for local sources.")
                    .foregroundStyle(.secondary)
            }
        case InspectorSectionID.page:
            if let item = store.selectedSource,
               case .local(let source) = item,
               let noun = store.selection.noun,
               noun.kind == InspectorNounKind.page
            {
                PageSection(source: source, noun: noun)
            } else {
                Text("Select a page in the play place.")
                    .foregroundStyle(.secondary)
            }
        case InspectorSectionID.target:
            if let item = store.selectedSource,
               case .local(let source) = item,
               let noun = store.selection.noun,
               noun.kind == InspectorNounKind.target
            {
                TargetSection(source: source, targetName: noun.id)
            } else {
                Text("Select a target in the outputs view.")
                    .foregroundStyle(.secondary)
            }
        case InspectorSectionID.execution:
            ExecutionSection()
        default:
            EmptyView()
        }
    }

    private func drawerNote(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
