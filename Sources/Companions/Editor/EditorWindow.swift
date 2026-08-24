import AppKit
import Observation
import SwiftUI
import WebKit

// swiftlint:disable file_length

/// Companion host for `boris-editor` (Svelte). Chassis registers the window
/// and leaves it closed; the editor opens against the selected page.
///
/// The window starts an `EditorSession` for the selected source's project
/// root, then loads the tokenized `BORIS_EDITOR_URL=` into the web view
/// with `open=` set from the page `sourcePath` (A15 / boris#649; ignored
/// by today's shell). The header names the selected page and its
/// `sourcePath`. Manual URL paste and "Open in Browser" stay as the
/// loopback fallback.
struct EditorWindow: View { // swiftlint:disable:this type_body_length
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime

    @State private var model = EditorWebModel()
    @State private var urlText = ""
    @State private var session = EditorSession()
    /// #237: When true, the manual URL field and Connect button are visible.
    /// Shown by default when idle/failed; hidden when connected.
    @State private var showManualConnect = false

    var body: some View {
        Group {
            if let source = store.selectedSource {
                VStack(spacing: 0) {
                    header(for: source)
                    Divider()
                    toolbar
                    Divider()
                    if model.currentURL != nil {
                        EditorWebView(model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        idleState(for: source)
                    }
                }
                .task(id: source.id) {
                    startEditor(for: source)
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle(headerNavigationTitle)
        .onChange(of: session.editorURL) { _, newURL in
            if let newURL {
                let targeted = EditorURL.opening(newURL, sourcePath: pageSourcePath)
                urlText = EditorURL.maskedDisplayString(for: targeted)
                model.load(url: targeted)
            }
        }
        .onDisappear {
            session.stop()
        }
    }

    private func startEditor(for source: SourceItem) {
        let folder: (any PlayFolderSource)?
        switch source {
        case .local(let local): folder = local
        case .github(let github): folder = github
        }
        guard let folder,
              let projectRoot = try? folder.workspaceRoot(),
              let contentRoot = try? folder.contentRoot()
        else {
            session.fail("Could not resolve project folder for '\(source.title)'")
            return
        }
        session.start(
            contentRoot: contentRoot,
            projectRoot: projectRoot,
            engine: runtime.engine
        )
    }

    /// Single entry point for pointing the web view at an editor URL.
    func loadEditor(url: URL) {
        model.load(url: url)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Editor", systemImage: "square.and.pencil")
        } description: {
            Text("Select a page in the main window, then choose File → Edit Page (⌘⇧E) to open the editor.")
        }
    }

    /// #237: The editor window's navigation title shows the page name
    /// when one is selected, falling back to "Editor".
    private var headerNavigationTitle: String {
        if let noun = store.selection.noun, noun.kind == "page", !noun.title.isEmpty {
            return "Editor — \(noun.title)"
        }
        return "Editor"
    }

    private func idleState(for source: SourceItem) -> some View {
        ContentUnavailableView {
            Label("Editor Host Not Running", systemImage: "square.and.pencil")
        } description: {
            VStack(alignment: .leading, spacing: 8) {
                if let guidance = errorGuidance {
                    Text(guidance.headline)
                        .font(.body)
                    Text(guidance.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("The Boris editor connects when the host process is running.")
                    // #267: lead with the action; manual connect is the
                    // last-resort sentence, matching #237's collapsed field.
                    Text(EditorIdleCopy.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } actions: {
            Button("Restart Host") {
                session.restart()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!session.canRestart)

            Button("Open in Browser") {
                if let url = session.editorURL ?? model.currentURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(session.editorURL == nil && model.currentURL == nil)
        }
    }

    /// #237: Maps raw error messages from the session to actionable guidance.
    private var errorGuidance: (headline: String, detail: String)? {
        guard case .failed(let message) = session.phase else { return nil }
        if message.contains("binary not found") {
            return (
                "boris-editor binary not found",
                "Install boris-editor or set SOLIPSIST_BORIS_EDITOR_BIN in your environment."
            )
        }
        if message.contains("did not report a token URL") {
            return (
                "Editor host did not report a token URL within 15s",
                "The editor host may be slow to start. Try again or check the boris-editor logs."
            )
        }
        if message.contains("exited (") {
            return (
                message,
                "The editor host crashed. Check the boris-editor logs for details."
            )
        }
        if message.contains("not available") {
            return (
                message,
                "Ensure Boris is built and the engine binary is accessible."
            )
        }
        return nil
    }

    private func header(for source: SourceItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle(for: source))
                    .font(.headline)
                    .lineLimit(1)
                if let path = headerSubtitle(for: source) {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .glassEffect()
    }

    /// Mail-compose chrome: when the editor was opened from a page, name that
    /// page; otherwise fall back to the source itself.
    private func headerTitle(for source: SourceItem) -> String {
        if let noun = store.selection.noun, noun.kind == "page", !noun.title.isEmpty {
            return noun.title
        }
        return source.title
    }

    private func headerSubtitle(for source: SourceItem) -> String? {
        if let path = pageSourcePath {
            return path
        }
        return source.detailLine
    }

    /// Graph `sourcePath` when the editor was opened from a page.
    private var pageSourcePath: String? {
        guard let noun = store.selection.noun, noun.kind == "page",
              let path = noun.sourcePath, !path.isEmpty
        else { return nil }
        return path
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: phase indicator + actions (always visible). #267:
            // Back/Forward removed — the shell loads one tokenized SPA URL
            // per session and never navigates cross-page by design.
            HStack(spacing: 8) {
                ReloadButton(model: model)

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                EditorPhaseIndicator(phase: session.phase, isFailure: session.isFailure)

                Spacer()

                Button {
                    session.restart()
                } label: {
                    Label("Restart Host", systemImage: "arrow.counterclockwise")
                }
                .accessibilityLabel("Restart")
                .accessibilityAddTraits(.isButton)
                .help("Restart boris-editor")
                .disabled(!session.canRestart)

                Button {
                    model.openInBrowser()
                } label: {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("Open in Browser")
                .accessibilityAddTraits(.isButton)
                .help("Open in Browser")
                .disabled(!model.canOpenInBrowser)
            }

            // #237: Row 2 — redacted URL (connected) or manual connect
            // (idle/failed or toggled open)
            if session.isConnected {
                if showManualConnect {
                    manualConnectRow
                } else {
                    redactedURLRow
                }
            } else if showManualConnect || session.isFailure || session.phase == .idle {
                manualConnectRow
            }

            // #232: one-shot confirmation after an automatic reconnect.
            if session.transientNotice != nil {
                Label("Reconnected", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let rejection = model.rejection {
                Label(rejection, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .onChange(of: session.phase) { _, newPhase in
            if case .connected = newPhase {
                showManualConnect = false
            } else {
                showManualConnect = true
            }
        }
    }

    /// #237: Redacted URL row — shows `host:port` only, with full URL
    /// in tooltip. Double-click reveals the manual connect field.
    private var redactedURLRow: some View {
        HStack(spacing: 8) {
            if let url = session.editorURL {
                let reduced = EditorURL.hostPort(for: url)
                Text(reduced)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .help(url.absoluteString)
                    .onTapGesture(count: 2) {
                        showManualConnect = true
                    }
                Spacer()
            }

            Button {
                showManualConnect = true
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Show URL field")
            .accessibilityAddTraits(.isButton)
            .help("Reveal the manual URL field")
        }
    }

    /// #237: Manual connect row — URL text field + Connect button.
    /// Hidden by default when connected; shown when idle, failed, or toggled.
    private var manualConnectRow: some View {
        HStack(spacing: 8) {
            TextField("BORIS_EDITOR_URL=http://127.0.0.1:49152/#token=…", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
                .accessibilityLabel("Editor URL")

            Button("Connect", action: submit)
                .accessibilityLabel("Connect")
                .accessibilityAddTraits(.isButton)

            if session.isConnected {
                Button {
                    showManualConnect = false
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Hide URL field")
                .accessibilityAddTraits(.isButton)
                .help("Hide the manual URL field")
            }
        }
    }

    private func submit() {
        if session.isConnected, let current = session.editorURL ?? model.currentURL {
            let targeted = EditorURL.opening(current, sourcePath: pageSourcePath)
            model.load(url: targeted)
            return
        }
        do {
            let url = try EditorURL.parse(urlText)
            model.load(url: url)
            urlText = EditorURL.maskedDisplayString(for: url)
        } catch let err as EditorURL.ParseError {
            model.reject(err.localizedDescription)
        } catch {
            model.reject(error.localizedDescription)
        }
    }
}

/// #267: the only navigation control left — Reload. Back/Forward are gone:
/// the web view never navigates cross-page by design, and dead controls
/// read as broken.
private struct ReloadButton: View {
    let model: EditorWebModel

    var body: some View {
        Button {
            model.reload()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("Reload")
        .accessibilityAddTraits(.isButton)
        .help("Reload")
        .disabled(!model.canReload)
    }
}

private struct EditorPhaseIndicator: View {
    let phase: EditorSession.Phase
    let isFailure: Bool

    var body: some View {
        HStack(spacing: 5) {
            phaseIcon
            Text(EditorPhaseCopy.label(for: phase))
                .font(.caption)
                .foregroundStyle(isFailure ? Color.red : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(EditorPhaseCopy.accessibilityLabel(for: phase))
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch phase {
        case .idle:
            Image(systemName: "circle.dotted")
        case .starting, .reconnecting:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
