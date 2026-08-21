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
    @State private var externalJump: Int?
    /// Cooklang completion vocabulary (LATER-3.4): re-decoded from the
    /// source's `.boris/` artifacts whenever a page is loaded, so a fresh
    /// build reaches the popup without restarting the window.
    @State private var cookCompletion = ComposeCookCompletion.empty
    /// Preview theme CSS (#230): the canonical HTML target's stylesheet,
    /// read from the source's `themes/` directory. Resolved per page switch;
    /// nil → the preview's fallback stylesheet.
    @State private var themeCSS: String?

    var body: some View {
        Group {
            if let source = selectedLocalSource, pageNoun != nil {
                ComposeEditorView(
                    document: document,
                    renderService: OliverRenderService(),
                    themeCSS: themeCSS,
                    cookCompletion: cookCompletion,
                    onSave: save,
                    externalJump: externalJump
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
        .task(id: runtime.pendingComposeJump) {
            if let jump = runtime.pendingComposeJump, jump.pageID == pageNoun?.id {
                if let offset = characterOffset(for: jump.line, column: jump.column, in: document.text) {
                    externalJump = offset
                } else {
                    externalJump = 0
                }
                runtime.pendingComposeJump = nil
            }
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
            cookCompletion = ComposeCookCompletion.load(workspaceRoot: workspaceRoot)
            themeCSS = resolveThemeCSS(workspaceRoot: workspaceRoot)
            loadError = nil
            saveStatus = nil
            if let jump = runtime.pendingComposeJump, jump.pageID == noun.id {
                if let offset = characterOffset(for: jump.line, column: jump.column, in: document.text) {
                    externalJump = offset
                }
                runtime.pendingComposeJump = nil
            } else {
                externalJump = nil
            }
        } catch {
            loadError = String(describing: error)
        }
    }

    private func characterOffset(for line: Int, column: Int?, in text: String) -> Int? {
        guard line >= 1 else { return nil }
        let textNSString = text as NSString
        var found: Int?
        var current = 1
        textNSString.enumerateSubstrings(in: NSRange(location: 0, length: textNSString.length), options: [.byLines, .substringNotRequired]) { _, range, _, stop in
            if current == line {
                found = range.location + min(max((column ?? 1) - 1, 0), range.length)
                stop.pointee = true
            }
            current += 1
        }
        return found.map { min(max($0, 0), textNSString.length) }
    }

    /// Theme CSS for the preview (#230): decode the source profile, pick the
    /// canonical target's theme, collect its stylesheets from `themes/`.
    /// Anything missing (no profile, no target theme, unreadable folder)
    /// degrades to nil — the preview falls back to its readable stylesheet.
    private func resolveThemeCSS(workspaceRoot: URL) -> String? {
        guard let profileURL = selectedLocalSource?.profileURL() else { return nil }
        do {
            let data = try Data(contentsOf: profileURL)
            let profile = try JSONDecoder().decode(PublicationProfile.self, from: data)
            return ComposeThemeCSS.collect(workspaceRoot: workspaceRoot, targets: profile.targets)
        } catch {
            return nil
        }
    }

    // MARK: - Save → coordinator gate

    /// The single save entry point — toolbar Save, ⌘S, every host verb.
    /// #231: the write happens inside `ComposeSaveFlow`'s tree-write window,
    /// so the preview watch can never observe a partially-written file.
    private func save() {
        saveStatus = nil
        let outcome = ComposeSaveFlow.run(
            beginTreeWrite: { runtime.coordinator.beginTreeWrite() },
            endTreeWrite: { runtime.coordinator.endTreeWrite() },
            noteSave: { runtime.coordinator.noteSave() },
            save: { try document.save() }
        )
        switch outcome {
        case .saved:
            saveStatus = "Saved · queued validate"
        case .notDirty:
            break
        case .failed(let message):
            saveStatus = message
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
                // #228 Cursor + word/char counts — right-aligned, Xcode-style
                Text(document.cursorText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Cursor position")
                    .accessibilityLabel("Cursor \(document.cursorText)")
                Text(document.wordCountText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Word count")
                    .accessibilityLabel(document.wordCountText)
                Text(document.characterCountText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(document.selectedLength > 0 ? "Selected characters" : "Character count")
                    .accessibilityLabel(document.characterCountText)
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
