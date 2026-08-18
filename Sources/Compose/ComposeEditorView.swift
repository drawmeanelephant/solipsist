import AppKit
import SwiftUI

/// One diagnostic for the compose element's problems seam. The hook-in card
/// maps Oliver's structured diagnostics (exact source spans) into this
/// shape; the element itself only renders what it is given.
struct ComposeDiagnostic: Identifiable, Equatable {
    enum Severity: Equatable {
        case warning
        case error
    }

    let id = UUID()
    let severity: Severity
    let message: String
    let line: Int?

    init(severity: Severity, message: String, line: Int? = nil) {
        self.severity = severity
        self.message = message
        self.line = line
    }
}

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
    var diagnostics: [ComposeDiagnostic] = []
    /// Called after an explicit save actually wrote the buffer. The host
    /// (ComposeWindow) uses this to flow the save into the coordinator's
    /// save→validate gate.
    var onSave: (() -> Void)?

    @State private var showPreview = true
    @State private var previewOptions = MarkupRenderOptions()
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                ComposeTextView(document: document)
                    .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                if showPreview {
                    ComposePreviewView(
                        source: document.text,
                        language: document.language,
                        options: previewOptions,
                        renderService: renderService
                    )
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if !diagnostics.isEmpty {
                Divider()
                ComposeDiagnosticsPane(diagnostics: diagnostics)
                    .frame(minHeight: 72, idealHeight: 110, maxHeight: 180)
            }
        }
        .navigationTitle(document.statusText)
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

            Text(document.language.conformanceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Toggle(isOn: $showPreview) {
                Label("Preview", systemImage: "eye")
            }
            .toggleStyle(.button)

            Menu {
                previewOptionsContent
            } label: {
                Label("Render Options", systemImage: "slider.horizontal.3")
            }
            .help("Oliver ParseOptions — every extension is off by default.")

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

/// The problems seam: renders diagnostics the host injects. Empty by design
/// until the hook-in card wires Oliver's structured diagnostics through.
private struct ComposeDiagnosticsPane: View {
    let diagnostics: [ComposeDiagnostic]

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
        }
    }
}

/// NSTextView host with live heuristic highlighting. The text storage is
/// re-painted after every edit; the buffer in `ComposeDocument` stays the
/// single source of truth.
private struct ComposeTextView: NSViewRepresentable {
    @Bindable var document: ComposeDocument

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = baseFont
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        context.coordinator.applyHighlight(
            textView,
            text: document.text,
            language: document.language,
            force: true
        )
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.document = document
        if textView.string != document.text {
            textView.string = document.text
            context.coordinator.applyHighlight(textView, text: document.text, language: document.language, force: true)
        } else {
            context.coordinator.applyHighlight(textView, text: document.text, language: document.language)
        }
    }

    private var baseFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: ComposeDocument
        private var isApplying = false

        /// Last state we painted, so programmatic syncs (which fire on every
        /// `document` change) do not re-paint an unchanged buffer.
        private var lastHighlightedText: String?
        private var lastHighlightedLanguage: ComposeLanguage?

        init(document: ComposeDocument) {
            self.document = document
        }

        func textDidChange(_ notification: Notification) {
            guard
                !isApplying,
                let textView = notification.object as? NSTextView
            else { return }
            isApplying = true
            defer { isApplying = false }

            document.text = textView.string
            applyHighlight(textView, text: textView.string, language: document.language)
        }

        func applyHighlight(_ textView: NSTextView, text: String, language: ComposeLanguage, force: Bool = false) {
            guard force || text != lastHighlightedText || language != lastHighlightedLanguage else { return }
            lastHighlightedText = text
            lastHighlightedLanguage = language

            let highlighted = ComposeHighlighter.highlight(text, language: language)
            textView.textStorage?.beginEditing()
            textView.textStorage?.setAttributedString(highlighted)
            textView.textStorage?.endEditing()
            textView.typingAttributes = [.font: baseFont, .foregroundColor: NSColor.labelColor]
        }

        private var baseFont: NSFont {
            NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        }
    }
}
