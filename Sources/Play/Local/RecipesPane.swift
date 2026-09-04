import AppKit
import SwiftUI

/// Recipes mailbox (#296): every graph node with a Cooklang `recipe`
/// facet as a row, plus the shared reading pane for the selected page.
///
/// The list reads the same `.boris/graph.json` artifact the inspector
/// reads (via the store's cached mirror) — never a second `Process`,
/// never `recipe-scale` for the list. Selecting a row writes the same
/// page noun Pages writes, so the drawer Recipe Scale section and the
/// Coordinator verbs keep working unchanged.
struct RecipesMailbox: View {
    let source: any PlayFolderSource
    let loadGeneration: Int

    @Environment(WorkspaceStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    /// Recipe pages from the cached graph mirror. Seeded via
    /// `requestGraph` (same as the Pages trunk rows) — never decoded in
    /// body, never built here. No Recipes row exists before the first
    /// build, so an empty cache here means "build first", not an error.
    private var recipePages: [PlayPage] {
        guard let graph = store.cachedGraph(for: source.id) else { return [] }
        return LocalPlayGraph.recipes(in: LocalPlayGraph.pages(from: graph))
    }

    private var selectedPage: PlayPage? {
        guard
            let noun = store.selection.noun,
            noun.kind == "page"
        else { return nil }
        return recipePages.first(where: { $0.id == noun.id })
    }

    var body: some View {
        Group {
            if recipePages.isEmpty {
                ContentUnavailableView {
                    Label(
                        "No Recipes",
                        systemImage: WorkspaceMailbox.symbolName(WorkspaceMailbox.recipes)
                    )
                } description: {
                    Text("This source has no Cooklang recipes yet. Build the source, then add a .cook file to see it here.")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No Recipes")
                .accessibilityHint("Build the source, then add a .cook file to see it here.")
            } else {
                recipesSplit(recipePages)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Seed the graph mirror off-main when this mailbox first appears
        // (coalesced with the sidebar seed; never a second Process).
        .task(id: source.id) {
            store.requestGraph(for: source.id)
        }
    }

    @State private var topHeight: CGFloat = 200

    @ViewBuilder
    private func recipesSplit(_ pages: [PlayPage]) -> some View {
        GeometryReader { proxy in
            let totalHeight = proxy.size.height
            let availableHeight = max(totalHeight - 10, 100)
            let clampedTop = min(max(topHeight, 90), availableHeight - 120)

            VStack(spacing: 0) {
                recipeList(pages)
                    .frame(height: clampedTop)

                ZStack {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)

                    Capsule()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 36, height: 4)
                }
                .frame(height: 9)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            topHeight = min(max(clampedTop + value.translation.height, 90), availableHeight - 120)
                        }
                )

                ReadingPane(
                    page: selectedPage,
                    source: source,
                    loadGeneration: loadGeneration
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func recipeList(_ pages: [PlayPage]) -> some View {
        List(pages, selection: selectedPageID) { page in
            RecipeRow(
                page: page,
                isSelected: store.selection.noun?.id == page.id
            )
            .tag(page.id)
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                selectPage(page)
                openWindow(id: CompanionID.compose)
            })
            .contextMenu {
                Button("Compose (Native)") {
                    selectPage(page)
                    openWindow(id: CompanionID.compose)
                }
                Button("Edit Page in Boris Editor") {
                    selectPage(page)
                    openWindow(id: CompanionID.editor)
                }
            }
        }
        .listStyle(.inset)
        .onKeyPress(.return) {
            guard store.selection.canEditPage else { return .ignored }
            openWindow(id: CompanionID.compose)
            return .handled
        }
        .onKeyPress(.escape) {
            if store.selection.noun != nil {
                store.select(noun: nil)
                return .handled
            }
            return .ignored
        }
    }

    private var selectedPageID: Binding<String?> {
        Binding(
            get: {
                if store.selection.noun?.kind == "page" {
                    return store.selection.noun?.id
                }
                return nil
            },
            set: { newID in
                guard let newID else {
                    store.select(noun: nil)
                    return
                }
                if let page = recipePages.first(where: { $0.id == newID }) {
                    selectPage(page)
                }
            }
        )
    }

    private func selectPage(_ page: PlayPage) {
        store.select(
            noun: WorkspaceNoun(
                kind: "page",
                id: page.id,
                title: page.title,
                sourcePath: page.sourcePath
            )
        )
    }
}

private struct RecipeRow: View {
    let page: PlayPage
    var isSelected = false

    private var count: Int { page.ingredientCount ?? 0 }

    private var countLabel: String {
        count == 1 ? "1 ingredient" : "\(count) ingredients"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: WorkspaceMailbox.symbolName(WorkspaceMailbox.recipes))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title)
                    .lineLimit(1)
                Text(page.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !page.status.isEmpty {
                Text(page.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help("\(page.title) · \(countLabel) · \(page.id)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title), \(countLabel), \(page.id)")
        .accessibilityValue(isSelected ? "selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Recipe")
    }
}
