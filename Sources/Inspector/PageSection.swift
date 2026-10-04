import SwiftUI

/// Read-only page minutiae with editor launch and engine-owned recipe data.
/// Fields come from the selected noun plus `.boris/completion.json` / `.boris/graph.json`.
/// Frontmatter is not parsed out of markdown.
struct PageSection: View {
    let source: LocalSource
    let noun: WorkspaceNoun

    @Environment(\.openWindow) private var openWindow

    @State private var completion: Completion?
    @State private var graph: Graph?
    @State private var note: String?

    var body: some View {
        Group {
            Button {
                openEditor()
            } label: {
                Label("Edit in Boris Editor", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            LabeledContent("Title", value: displayTitle)
            LabeledContent("ID", value: noun.id)
            if let path = noun.sourcePath, !path.isEmpty {
                LabeledContent("Source Path", value: path)
            }
            LabeledContent("Role", value: display(entity?.role))
            LabeledContent("Parent", value: display(entity?.parent))
            LabeledContent("Status", value: display(entity?.status))
            LabeledContent("Tags", value: displayTags)

            if let recipe = currentRecipe {
                recipeSection(recipe)
            } else if showsRecipeSection {
                Section("Recipe") {
                    Text(InspectorRecipe.unavailableMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

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

    private var graphNode: GraphNode? {
        graph?.nodes.first { $0.id == noun.id }
    }

    private var showsRecipeSection: Bool {
        if graphNode?.recipe != nil { return true }
        if graphNode?.tags?.contains("recipe") == true { return true }
        if entity?.tags.contains("recipe") == true { return true }
        if noun.sourcePath?.hasSuffix(".cook") == true { return true }
        return false
    }

    private var currentRecipe: CookRecipe? {
        InspectorRecipe.recipe(for: graphNode)
    }

    @ViewBuilder
    private func recipeSection(_ recipe: CookRecipe) -> some View {
        Section("Recipe") {
            VStack(alignment: .leading, spacing: 6) {
                Text(RecipeScaleSupport.unavailableMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !recipe.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ingredients (\(recipe.ingredients.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(recipe.ingredients, id: \.name) { ing in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(displayIngredient(ing))
                                    .font(.callout)
                            }
                        }
                    }
                }

                if !recipe.cookware.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cookware")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(recipe.cookware, id: \.name) { cw in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(displayCookware(cw))
                                    .font(.callout)
                            }
                        }
                    }
                }

                if !recipe.timers.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Timers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(recipe.timers, id: \.name) { tm in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(displayTimer(tm))
                                    .font(.callout)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func displayIngredient(_ ing: CookIngredient) -> String {
        var str = ""
        if !ing.quantity.amount.isEmpty {
            str += ing.quantity.amount
            if !ing.quantity.unit.isEmpty {
                str += " " + ing.quantity.unit
            }
            str += " "
        }
        str += ing.name
        if !ing.preparation.isEmpty {
            str += " (\(ing.preparation))"
        }
        return str
    }

    private func displayCookware(_ cw: CookCookware) -> String {
        if !cw.quantity.amount.isEmpty && cw.quantity.amount != "1" {
            return "\(cw.name) (\(cw.quantity.amount))"
        }
        return cw.name
    }

    private func displayTimer(_ tm: CookTimer) -> String {
        let name = tm.name.isEmpty ? "Timer" : tm.name
        let amt = tm.quantity.amount
        let unit = tm.quantity.unit
        let timeStr = unit.isEmpty ? amt : "\(amt) \(unit)"
        return "\(name): \(timeStr)"
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

    private func openEditor() {
        openWindow(id: CompanionID.editor)
    }

    private func load() {
        completion = nil
        graph = nil
        note = nil
        guard source.isAvailable else {
            note = "This folder is no longer reachable."
            return
        }
        do {
            let root = try source.resolve().url
            if let index = InspectorCompletion.load(from: root) {
                completion = index
            }
            if let gr = InspectorGraph.load(from: root) {
                graph = gr
            }
            if completion == nil && graph == nil {
                note = "Completion arrives when the IR build writes .boris/completion.json."
            }
        } catch {
            note = String(describing: error)
        }
    }
}
