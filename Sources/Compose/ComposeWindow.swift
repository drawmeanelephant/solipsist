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

    @State private var buffer = ComposeBuffer()
    /// M18: a staged draft that arrived while the buffer held unsaved
    /// work — it waits behind the same discard-confirm as a page switch.
    @State private var pendingStagedDraft: StagedPostDraft?
    /// #265: typed save signal from `ComposeSaveFlow.run` — no more
    /// string-matching "Saved" in rendered text.
    @State private var saveSignal: ComposeSaveFlow.Signal?
    /// #265: Ln/Col + char counts live behind this chevron, collapsed by
    /// default; survives page switches in-session (in-memory only).
    @State private var showDetailStats = false
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
            if showsEditor {
                ComposeEditorView(
                    document: document,
                    renderService: OliverRenderService(),
                    themeCSS: themeCSS,
                    cookCompletion: cookCompletion,
                    onSave: { save() },
                    externalJump: externalJump,
                    typography: runtime.composeTypography
                )
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposeStatusBar(
                        loadError: buffer.loadError,
                        document: document,
                        coordinatorSummary: runtime.coordinator.summary,
                        saveSignal: saveSignal,
                        showDetailStats: $showDetailStats
                    )
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let page = buffer.page {
                        Text("\(page.owner.source.title) · \(page.fileURL.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.bar)
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle("Compose")
        .task(id: selectionRequest) {
            if buffer.select(selectionRequest) {
                didLoadPage()
            }
        }
        // M18: accept a staged AI draft (Siri or File menu) into the
        // untitled buffer. Memory-only until an explicit Save; a dirty
        // buffer gets the same discard-confirm as a page switch.
        .task(id: runtime.pendingComposeDraft) {
            guard let draft = runtime.pendingComposeDraft else { return }
            runtime.pendingComposeDraft = nil
            if !document.isDirty {
                stage(draft)
            } else {
                pendingStagedDraft = draft
            }
        }
        .task(id: runtime.pendingComposeJump) {
            if let jump = runtime.pendingComposeJump, jump.pageID == buffer.page?.noun.id, store.selection.sourceID == buffer.page?.owner.source.id {
                if let offset = characterOffset(for: jump.line, column: jump.column, in: document.text) {
                    externalJump = offset
                } else {
                    externalJump = 0
                }
                runtime.pendingComposeJump = nil
            }
        }
        .confirmationDialog(
            "Save changes before switching?",
            isPresented: Binding(
                get: { buffer.pendingPage != nil || pendingStagedDraft != nil },
                set: {
                    if !$0 {
                        buffer.cancelSwitch()
                        pendingStagedDraft = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            // AppKit dismisses the dialog (and clears its presentation
            // binding) before running a button's action.
            let pendingPage = buffer.pendingPage
            let pendingDraft = pendingStagedDraft
            Button("Save Changes") {
                if let draft = pendingDraft {
                    if save() {
                        stage(draft)
                    }
                } else if buffer.saveAndSwitch(to: pendingPage, save: save) {
                    didLoadPage()
                }
                pendingStagedDraft = nil
            }
            Button("Discard Changes", role: .destructive) {
                if buffer.discardAndSwitch(to: pendingPage) {
                    didLoadPage()
                }
                if let draft = pendingDraft {
                    stage(draft)
                }
                buffer.cancelSwitch()
                pendingStagedDraft = nil
            }
            Button("Cancel", role: .cancel) {
                // Snap the selection back so the compose window keeps the
                // buffer the author is mid-edit on; a discarded staged
                // draft simply drops (Siri can stage it again).
                restoreBufferSelection()
                buffer.cancelSwitch()
                pendingStagedDraft = nil
            }
        } message: {
            Text(discardMessage)
        }
    }

    /// Names what is at stake in the discard dialog: the page being left,
    /// or the staged draft that would replace the current work.
    private var discardMessage: String {
        if let draft = pendingStagedDraft {
            let title = draft.title.isEmpty ? "an untitled draft" : "“\(draft.title)”"
            return "The staged draft \(title) replaces your unsaved changes."
        }
        return buffer.page.map { "“\($0.noun.title)” in \($0.owner.source.title) has unsaved changes." }
            ?? "The current page has unsaved changes."
    }

    // MARK: - Selection

    /// The editor shows for a selected page (the M10 rule) or while an
    /// untitled AI draft is staged / already in the buffer (M18).
    private var showsEditor: Bool {
        buffer.page != nil || pageNoun != nil || runtime.pendingComposeDraft != nil || isUntitledDraft
    }

    private var document: ComposeDocument { buffer.document }

    /// An unsaved buffer with no backing file — only a staged draft gets here.
    private var isUntitledDraft: Bool {
        document.fileURL == nil && !document.text.isEmpty
    }

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

    private var selectionRequest: ComposeBuffer.Request? {
        guard let source = selectedLocalSource, pageNoun != nil else { return nil }
        return ComposeBuffer.Request(source: source, selection: store.selection)
    }

    private func didLoadPage() {
        guard let page = buffer.page else { return }
        cookCompletion = ComposeCookCompletion.load(workspaceRoot: page.owner.workspaceRoot)
        themeCSS = resolveThemeCSS(workspaceRoot: page.owner.workspaceRoot)
        saveSignal = nil
        externalJump = nil
        if let jump = runtime.pendingComposeJump, jump.pageID == page.noun.id {
            if let offset = characterOffset(for: jump.line, column: jump.column, in: document.text) {
                externalJump = offset
            }
            runtime.pendingComposeJump = nil
        }
    }

    private func restoreBufferSelection() {
        guard let page = buffer.page,
              let item = store.sources.first(where: { $0.id == page.owner.source.id }),
              case .local(let source) = item,
              (try? source.workspaceRoot().path) == page.owner.workspaceRoot.path
        else { return }
        store.select(source.id, mailbox: page.selection.mailbox ?? WorkspaceMailbox.pages)
        store.select(noun: page.noun)
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
        let profileURL = workspaceRoot.appendingPathComponent("boris.json")
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
    /// M18: an untitled draft asks for a destination first; cancelling
    /// keeps the buffer staged and writes nothing.
    @discardableResult
    private func save() -> Bool {
        saveSignal = nil
        if document.fileURL == nil {
            guard let destination = ComposeStagedDraft.runSavePanel(
                directoryURL: selectedLocalSource.map { try? $0.contentRoot() } ?? nil,
                frontmatterPayload: document.frontmatter?.payloadString ?? ""
            ) else { return false }
            document.fileURL = destination
        }
        let outcome = ComposeSaveFlow.run(
            beginTreeWrite: { runtime.coordinator.beginTreeWrite() },
            endTreeWrite: { runtime.coordinator.endTreeWrite() },
            noteSave: { runtime.coordinator.noteSave(source: buffer.page?.owner) },
            save: { try document.save() }
        )
        saveSignal = ComposeSaveFlow.Signal(
            outcome: outcome,
            savedMessage: "Saved"
        )
        if case .failed = outcome { return false }
        return true
    }

    // MARK: - Staged AI drafts (M18)

    /// Accept a staged draft into the untitled buffer. Frontmatter comes
    /// from the repo's canonical closed-key emitter; the buffer starts
    /// dirty — review is mandatory, saving is explicit.
    private func stage(_ draft: StagedPostDraft) {
        buffer.stage(draft)
        saveSignal = nil
        externalJump = nil
        cookCompletion = .empty
        if let source = selectedLocalSource, let workspaceRoot = try? source.workspaceRoot() {
            themeCSS = resolveThemeCSS(workspaceRoot: workspaceRoot)
        } else {
            themeCSS = nil
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
                + "(try Stunts/happy), then select a page in the Pages mailbox. "
                + "You can also draft from scratch: File → New Draft with Apple Intelligence…"
        }
        return intro
            + "Select a page in the Pages mailbox, then open it from "
            + "View → Compose (⌘⇧C), the letter header, or the toolbar. "
            + "Or start fresh: File → New Draft with Apple Intelligence…"
    }
}
