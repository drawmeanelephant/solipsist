import AppKit
import SwiftUI

/// The compose element: a full-featured Markdown / Textile / Cooklang
/// editing surface that will be hooked into the app by a later card.
///
/// Standalone contract:
/// - The buffer is the source of truth (`ComposeDocument`).
/// - Highlighting is heuristic paint derived from Oliver's language surface;
///   it never claims to be a parse.
/// - Nothing writes to disk except the explicit Save button / ⌘S.
/// - Preview renders through the injected `MarkupRenderService`.
struct ComposeEditorView: View {
    @Bindable var document: ComposeDocument

    var renderService: any MarkupRenderService = PlaceholderRenderService()
    /// Cooklang completion vocabulary (LATER-3.4); `.empty` (default) keeps
    /// the popup off for hosts without a `.boris/` index.
    var cookCompletion: ComposeCookCompletion = .empty
    /// Called after an explicit save actually wrote the buffer. The host
    /// (ComposeWindow) uses this to flow the save into the coordinator's
    /// save→validate gate.
    var onSave: (() -> Void)?
    /// External line-jump from ProblemsPane (M11 #207): when set, the editor
    /// jumps to this absolute character offset.
    var externalJump: Int?

    /// Problems from the live preview render (LATER-3.1). Computed from the
    /// render, not injected by the host.
    @State private var diagnostics: [ComposeDiagnostic] = []
    /// Character offset to jump the editor selection to (click-to-line).
    @State private var jumpToCharacter: Int?
    @State private var showPreview = true
    /// LATER-3.3: leading pane editing the closed front-matter key set.
    @State private var showFrontmatter = false
    @State private var previewOptions = MarkupRenderOptions()
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                if showFrontmatter {
                    ComposeFrontmatterForm(document: document)
                        .frame(minWidth: 230, idealWidth: 270, maxWidth: 360, maxHeight: .infinity)
                }
                ComposeTextView(
                    document: document,
                    jumpToCharacter: jumpToCharacter,
                    completion: cookCompletion
                )
                .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                if showPreview {
                    ComposePreviewView(
                        source: document.text,
                        language: document.language,
                        options: previewOptions,
                        renderService: renderService,
                        onDiagnostics: { diagnostics = $0 }
                    )
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if !diagnostics.isEmpty {
                Divider()
                ComposeDiagnosticsPane(diagnostics: diagnostics) { selected in
                    if let index = characterIndex(for: selected, in: document.text) {
                        jumpToCharacter = index
                    }
                }
                .frame(minHeight: 72, idealHeight: 110, maxHeight: 180)
            }
        }
        .navigationTitle(document.statusText)
        .onChange(of: externalJump) { _, newValue in
            if let newValue { jumpToCharacter = newValue }
        }
        .task(id: externalJump) {
            if let externalJump { jumpToCharacter = externalJump }
        }
    }

    /// Resolve a diagnostic to a character offset: Oliver's `span.start`
    /// when present, else the start of the reported line. UTF-16 offsets
    /// (NSRange units) — a best-effort jump like the highlighter, clamped
    /// so it can never exceed the buffer.
    private func characterIndex(for diagnostic: ComposeDiagnostic, in text: String) -> Int? {
        if let index = diagnostic.characterIndex {
            return min(max(index, 0), text.utf16.count)
        }
        guard let line = diagnostic.line, line >= 1 else { return nil }
        let nsString = text as NSString
        var found: Int?
        var currentLine = 1
        nsString.enumerateSubstrings(
            in: NSRange(location: 0, length: nsString.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, stop in
            if currentLine == line {
                found = range.location
                stop.pointee = true
            }
            currentLine += 1
        }
        return found
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Language", selection: $document.language) {
                ForEach(ComposeLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Authoring frontend (Oliver's \(document.language.oliverFrontend))")
            .accessibilityLabel("Language, currently \(document.language.displayName)")
            .accessibilityHint("Select the authoring frontend")

            Text(document.language.conformanceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Toggle(isOn: $showPreview) {
                Label("Preview", systemImage: "eye")
            }
            .toggleStyle(.button)
            .help("Toggle preview (⌘⇧P)")
            .accessibilityLabel("Preview")
            .accessibilityHint("Toggle the Oliver preview pane")
            .accessibilityAddTraits(showPreview ? .isSelected : [])

            Toggle(isOn: $showFrontmatter) {
                Label("Front Matter", systemImage: "doc.text.magnifyingglass")
            }
            .toggleStyle(.button)
            .help("Edit the front-matter block (closed key set)")
            .accessibilityLabel("Front Matter")
            .accessibilityHint("Show or hide the front matter editor.")
            .accessibilityAddTraits(showFrontmatter ? .isSelected : [])

            Menu {
                previewOptionsContent
            } label: {
                Label("Render Options", systemImage: "slider.horizontal.3")
            }
            .help("Oliver ParseOptions — every extension is off by default.")
            .accessibilityLabel("Render Options")
            .accessibilityHint("Configure Oliver's parse extensions.")

            Button {
                do {
                    saveError = nil
                    if try document.save() {
                        onSave?()
                    }
                } catch {
                    saveError = error.localizedDescription
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .help("Save (⌘S)")
            .accessibilityLabel("Save")
            .accessibilityHint("Write the buffer to disk (⌘S).")
            .disabled(!document.isDirty)

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// Author-facing extension surface, mirroring Oliver's `ParseOptions`:
    /// all extensions off by default; profile / frontmatter / raw-HTML
    /// policies map 1:1 to Oliver's CLI flags.
    @ViewBuilder
    private var previewOptionsContent: some View {
        Menu("Markdown Extensions") {
            Toggle("Wikilinks", isOn: $previewOptions.wikilinks)
            Toggle("Callouts", isOn: $previewOptions.callouts)
            Toggle("Smart Typography", isOn: $previewOptions.smartypants)
            Toggle("Footnotes", isOn: $previewOptions.footnotes)
            Toggle("Definition Lists", isOn: $previewOptions.definitionLists)
            Toggle("Heading Attributes", isOn: $previewOptions.headingAttributes)
            Toggle("Strikethrough", isOn: $previewOptions.strikethrough)
            Toggle("Heading IDs", isOn: $previewOptions.headingIDs)
            Toggle("Task Lists", isOn: $previewOptions.taskLists)
        }
        Picker("Front Matter", selection: $previewOptions.frontmatter) {
            Text("None").tag(MarkupRenderOptions.FrontmatterPolicy.none)
            Text("YAML").tag(MarkupRenderOptions.FrontmatterPolicy.yaml)
            Text("TOML").tag(MarkupRenderOptions.FrontmatterPolicy.toml)
        }
        Picker("Raw HTML", selection: $previewOptions.rawHTML) {
            Text("Allowed").tag(MarkupRenderOptions.RawHTMLPolicy.allowed)
            Text("Escaped").tag(MarkupRenderOptions.RawHTMLPolicy.escaped)
            Text("Rejected").tag(MarkupRenderOptions.RawHTMLPolicy.rejected)
        }
        Picker("Profile", selection: $previewOptions.profile) {
            Text("HTML").tag(MarkupRenderOptions.Profile.html)
            Text("XHTML").tag(MarkupRenderOptions.Profile.xhtml)
        }
    }
}

/// The problems seam: renders the diagnostics the editor computed from the
/// live render (LATER-3.1). Clicking a row jumps the editor to the span.
private struct ComposeDiagnosticsPane: View {
    let diagnostics: [ComposeDiagnostic]
    var onSelect: (ComposeDiagnostic) -> Void = { _ in }

    var body: some View {
        List(diagnostics) { diagnostic in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: diagnostic.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                    .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                if let line = diagnostic.line {
                    Text("\(line)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(diagnostic.message)
                    .textSelection(.enabled)
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect(diagnostic) }
            .help("Jump to this diagnostic")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(diagnostic.accessibilityLabel)
        }
    }
}
