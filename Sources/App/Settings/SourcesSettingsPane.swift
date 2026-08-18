import SwiftUI

/// Account book for local sources. Writes bookmarks and the workspace plist
/// through `WorkspaceStore` only — never `boris.json`.
struct SourcesSettingsPane: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.sources.isEmpty {
                emptyState
            } else {
                sourceList
                actionBar
                Text(
                    "A source is a place content lives. Local folders now. GitHub — and other remotes — later, in this same list."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            removePrompt,
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let id = store.selection.sourceID {
                    store.remove(id)
                }
            }
        } message: {
            Text("The folder on disk is not deleted.")
        }
    }

    private var sourceList: some View {
        List(selection: selectedSource) {
            ForEach(store.sources) { item in
                SourceAccountRow(item: item)
                    .tag(item.id)
            }
        }
        .listStyle(.inset)
        .frame(maxHeight: max(72, CGFloat(store.sources.count) * 56 + 12))
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("Add Local…") {
                store.presentOpenPanel()
            }
            Button("Relocate…") {
                if let id = store.selection.sourceID {
                    store.presentRelocatePanel(for: id)
                }
            }
            .disabled(store.selectedSource?.isAvailable != false)
            Button("Remove", role: .destructive) {
                confirmRemove = true
            }
            .disabled(store.selection.sourceID == nil)
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No Sources")
                .font(.headline)
            Text("A source is a place content lives — an account, not a file tree. Local folders now (a folder with `boris.json`, for example `Stunts/happy`). GitHub and other remotes later, in this same list.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Add Local…") {
                store.presentOpenPanel()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedSource: Binding<SourceID?> {
        Binding(
            get: { store.selection.sourceID },
            set: { store.select($0) }
        )
    }

    private var removePrompt: String {
        let name = store.selectedSource?.title ?? "this source"
        return "Remove “\(name)” from Solipsist?"
    }
}

private struct SourceAccountRow: View {
    let item: SourceItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.kind.displayName)
                        .foregroundStyle(.secondary)
                }
                if let path = item.detailLine {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !item.isAvailable {
                    Text("Unreachable — Relocate / Remove")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: item.symbolName)
                .symbolVariant(item.isAvailable ? .none : .slash)
                .foregroundStyle(item.isAvailable ? Color.primary : Color.orange)
        }
        .help(
            item.isAvailable
                ? (item.detailLine ?? item.title)
                : "Unreachable — Relocate / Remove"
        )
    }
}
