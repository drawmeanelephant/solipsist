import SwiftUI

/// The compose window: hosts the `ComposeEditorView` element for the page
/// selected in the play list.
///
/// Hook-in contract (COMPOSE-EDITOR card, hook-in phase):
/// - The buffer is sourced from the selected `page` noun; the file is
///   resolved through the published graph contract (`graph.json`) so the
///   selection store stays a pair of strings.
/// - Files are read/written under the local source's security-scoped access
///   (the same bookmark the play surface uses). Nothing writes except an
///   explicit Save / ⌘S.
/// - A successful save flows into the coordinator's save→validate gate
///   (`noteSave()`) and suspends the preview watch for the write, exactly
///   like play's own tree-writing invocations.
struct ComposeWindow: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime

    @State private var document = ComposeDocument()
    @State private var currentNoun: WorkspaceNoun?
    @State private var pendingSwitch: WorkspaceNoun?
    @State private var loadError: String?
    @State private var saveStatus: String?

    var body: some View {
        Group {
            if let source = selectedLocalSource, pageNoun != nil {
                ComposeEditorView(
                    document: document,
                    renderService: OliverRenderService(),
                    onSave: save
                )
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    statusBar
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle("Compose")
        .task(id: store.selection.noun) {
            handleSelection()
        }
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: Binding(
                get: { pendingSwitch != nil },
                set: { if !$0 { pendingSwitch = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                if let source = selectedLocalSource, let noun = pendingSwitch {
                    switchTo(noun, source: source)
                }
                pendingSwitch = nil
            }
            Button("Cancel", role: .cancel) {
                // Snap the selection back so the compose window keeps the
                // buffer the author is mid-edit on.
                if let noun = currentNoun {
                    store.select(noun: noun)
                }
                pendingSwitch = nil
            }
        } message: {
            Text(currentNoun.map { "“\($0.title)” has unsaved changes." }
                ?? "The current page has unsaved changes.")
        }
    }

    // MARK: - Selection

    private var pageNoun: WorkspaceNoun? {
        guard let noun = store.selection.noun, noun.kind == "page" else { return nil }
        return noun
    }

    private var selectedLocalSource: LocalSource? {
        if case .local(let source) = store.selectedSource {
            return source
        }
        return nil
    }

    private func handleSelection() {
        guard let source = selectedLocalSource, let noun = pageNoun else { return }
        guard noun != currentNoun else { return }
        if document.isDirty {
            pendingSwitch = noun
        } else {
            switchTo(noun, source: source)
        }
    }

    private func switchTo(_ noun: WorkspaceNoun, source: LocalSource) {
        defer { currentNoun = noun }
        do {
            let workspaceRoot = try source.workspaceRoot()
            let contentRoot = try source.contentRoot()
            guard let node = try ComposePageResolver.page(id: noun.id, workspaceRoot: workspaceRoot) else {
                loadError = "No graph node for “\(noun.title)”."
                return
            }
            let url = ComposePageResolver.fileURL(contentRoot: contentRoot, sourcePath: node.sourcePath)
            try document.load(from: url)
            loadError = nil
            saveStatus = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    // MARK: - Save → coordinator gate

    private func save() {
        saveStatus = nil
        do {
            // Tree write: suspend the preview watch for the write, like
            // play's IR build does; resume on the way out.
            runtime.coordinator.beginTreeWrite()
            defer { runtime.coordinator.endTreeWrite() }
            guard try document.save() else { return }
            runtime.coordinator.noteSave()
            saveStatus = "Saved · queued validate"
        } catch {
            saveStatus = error.localizedDescription
        }
    }

    // MARK: - Chrome

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Compose", systemImage: "square.and.pencil")
        } description: {
            Text(emptyStateMessage)
        }
    }

    /// Compose is the native buffer for the selected page's source file.
    /// Say so here instead of a blank window that looks like the feature
    /// is missing; name the missing selection so the gate reads clearly.
    private var emptyStateMessage: String {
        let intro = "Compose is the native editor for a page's source file. "
        if store.selectedSource == nil {
            return intro
                + "Add a source first: File → Open… or Settings → Sources "
                + "(try Stunts/happy), then select a page in the Pages mailbox."
        }
        return intro
            + "Select a page in the Pages mailbox, then open it from "
            + "View → Compose (⌘⇧C), the letter header, or the toolbar."
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else {
                    Text(document.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if let saveStatus {
                    Text(saveStatus)
                        .font(.caption)
                        .foregroundStyle(saveStatus.contains("Saved") ? Color.secondary : Color.red)
                }
                Text(runtime.coordinator.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }
}
