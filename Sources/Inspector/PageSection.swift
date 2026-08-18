import SwiftUI

/// Read-only page minutiae. Fields come from the selected noun plus
/// `.boris/completion.json` when play has produced it. Frontmatter is
/// not parsed out of markdown.
struct PageSection: View {
    let source: LocalSource
    let noun: WorkspaceNoun

    @State private var completion: Completion?
    @State private var note: String?

    var body: some View {
        Group {
            LabeledContent("Title", value: displayTitle)
            LabeledContent("ID", value: noun.id)
            LabeledContent("Role", value: display(entity?.role))
            LabeledContent("Parent", value: display(entity?.parent))
            LabeledContent("Status", value: display(entity?.status))
            LabeledContent("Tags", value: displayTags)
            if let relations = entity?.relations, !relations.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Relations")
                        .foregroundStyle(.secondary)
                    ForEach(relations, id: \.target) { rel in
                        Text("\(rel.kind): \(rel.target)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let completion {
                vocabulary("Relation kinds", completion.relation_kinds)
                vocabulary("Layout slots", completion.layout_slots)
            } else if let note {
                Text(note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .task(id: taskID) {
            load()
        }
    }

    private var entity: CompletionEntity? {
        completion?.entities.first { $0.id == noun.id }
    }

    private var displayTitle: String {
        let title = entity?.title ?? noun.title
        return title.isEmpty ? "—" : title
    }

    private var displayTags: String {
        let tags = entity?.tags ?? []
        return tags.isEmpty ? "—" : tags.joined(separator: ", ")
    }

    private var taskID: String {
        "\(source.id.raw.uuidString)|\(noun.id)"
    }

    private func display(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed
    }

    @ViewBuilder
    private func vocabulary(_ title: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(values.isEmpty ? "—" : values.joined(separator: ", "))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() {
        completion = nil
        note = nil
        guard source.isAvailable else {
            note = "This folder is no longer reachable."
            return
        }
        do {
            let root = try source.resolve().url
            if let index = InspectorCompletion.load(from: root) {
                completion = index
            } else {
                note = "Completion arrives when the IR build writes .boris/completion.json."
            }
        } catch {
            note = String(describing: error)
        }
    }
}
