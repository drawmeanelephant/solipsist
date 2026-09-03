import SwiftUI
import WebKit

/// #298 — visual theme browser. Presents `ThemeCatalog.allThemes(for:)`
/// as a grid of preview tiles (a small HTML fragment styled by the
/// theme's CSS) so authors pick a target theme by appearance. Selection
/// only — never authoring (the explicit ROADMAP §3 boundary): no CSS
/// editing, no theme creation, no writes under `themes/`.
///
/// The preview tile reuses the compose preview's render path
/// (`ComposeThemeCSS.collect` for local CSS; a neutral fallback sample
/// when a theme has no resolvable stylesheet — first-class themes ship
/// no CSS in this workspace). Boris owns theme rendering; the tile is
/// either theme-CSS-styled or the bundled neutral sample, never a
/// Swift HTML/CSS engine.
struct ThemeBrowserView: View {
    /// All themes, local first then first-class (from ThemeCatalog).
    let themes: [String]
    /// The currently selected theme name, `nil`/empty meaning Default.
    let selection: String?
    /// Workspace root for local theme CSS collection.
    let workspaceRoot: URL?
    /// Called with the chosen theme name, or nil for the Default tile.
    let onSelect: (String?) -> Void
    /// Called when the browser is dismissed without a choice.
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var visibleThemes: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return themes }
        return themes.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a Theme")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            if themes.count > 8 {
                // Search field only earns its chrome on the long list.
                TextField("Filter themes…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)],
                    spacing: 12
                ) {
                    ThemeTile(
                        name: "Default",
                        css: nil,
                        isSelected: (selection ?? "").isEmpty,
                        caption: "Boris chooses the theme"
                    ) {
                        onSelect(nil)
                        dismiss()
                    }

                    ForEach(visibleThemes, id: \.self) { theme in
                        ThemeTile(
                            name: theme,
                            css: ThemePreviewDocument.css(
                                for: theme,
                                workspaceRoot: workspaceRoot
                            ),
                            isSelected: selection == theme,
                            caption: nil
                        ) {
                            onSelect(theme)
                            dismiss()
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme Browser")
    }
}

/// One preview tile: a fixed sample fragment styled by the theme's CSS
/// in a sandboxed WKWebView (same host shape as the compose preview —
/// `loadHTMLString`, nil baseURL, no navigation). A theme whose CSS
/// does not resolve renders the neutral fallback sample plus its name;
/// never a blank tile, never an error.
private struct ThemeTile: View {
    let name: String
    let css: String?
    let isSelected: Bool
    let caption: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ThemeTileWebView(
                    html: ThemePreviewDocument.html(sampleCSS: css)
                )
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(.callout.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                        if let caption {
                            Text(caption)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : Color(nsColor: .controlBackgroundColor)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) theme\(isSelected ? ", selected" : "")")
        .accessibilityHint(caption ?? "Select this theme")
    }
}

/// Sandboxed host for one tile's sample document — the compose preview's
/// shape: non-persistent data store, single load, no delegate-driven
/// navigation beyond it.
private struct ThemeTileWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Tiles are immutable per theme; no reload dance needed.
    }
}

/// Pure document assembly for a preview tile — mirrors
/// `ComposePreviewDocument` (same style-element inlining and
/// `</style>` neutralization) but with the browser's fixed sample
/// fragment. Unit-testable without WebKit.
enum ThemePreviewDocument {
    /// The representative fragment every tile renders: heading,
    /// paragraph, link, list — the #298 sample set.
    static let sampleFragment = """
    <h1>Theme Sample</h1>
    <p>A paragraph of <a href="#">text</a> to show the theme.</p>
    <ul><li>One</li><li>Two</li></ul>
    """

    /// Neutral sample stylesheet for themes whose CSS does not resolve
    /// (first-class themes ship no CSS in this workspace) — the fallback
    /// tile, never blank, never an error. Mirrors the compose preview's
    /// fallback so both read as the same "no theme" voice.
    static let fallbackCSS = ComposePreviewDocument.fallbackCSS

    /// CSS for a theme: local `themes/<name>` stylesheets collected via
    /// the existing `ComposeThemeCSS.collect` path (no second resolver);
    /// nil when nothing resolves.
    static func css(for theme: String, workspaceRoot: URL?) -> String? {
        guard let workspaceRoot else { return nil }
        return ComposeThemeCSS.collect(workspaceRoot: workspaceRoot, themePath: "themes/\(theme)")
    }

    /// Full tile document.
    static func html(sampleCSS: String?) -> String {
        let css = sampleCSS.flatMap { $0.isEmpty ? nil : ComposePreviewDocument.sanitize($0) }
            ?? fallbackCSS
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
        \(css)
        </style>
        </head>
        <body>
        \(sampleFragment)
        </body>
        </html>
        """
    }
}
