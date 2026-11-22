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
                    nounKind: store.selection.noun?.kind,
                    mailbox: store.selection.mailbox
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
                    .safeAreaPadding(.top, 6)
                    .safeAreaPadding(.bottom, 54)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sectionBody(_ section: InspectorSection) -> some View {
        switch section.id {
        case InspectorSectionID.profile:
            if let source = store.selectedSource?.folderSource {
                ProfileSection(source: source)
            } else {
                Text("Select a source to edit its profile.")
                    .foregroundStyle(.secondary)
            }
        case InspectorSectionID.page:
            if let source = store.selectedSource?.folderSource,
               let noun = store.selection.noun,
               noun.kind == InspectorNounKind.page
            {
                PageSection(
                    source: source,
                    noun: noun,
                    cachedCompletion: store.cachedCompletion(for: source.id),
                    cachedGraph: store.cachedGraph(for: source.id)
                )
            } else {
                Text("Select a page in the reading place.")
                    .foregroundStyle(.secondary)
            }
        case InspectorSectionID.target:
            if let source = store.selectedSource?.folderSource,
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
