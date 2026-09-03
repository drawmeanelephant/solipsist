import SwiftUI

/// Inspector section for an individual HTML target (M7 / #76).
/// Displays target details and lets the author pick from the `ThemeCatalog`.
struct TargetSection: View {
    let source: LocalSource
    let targetName: String

    @State private var target: PublicationTarget?
    @State private var profile: PublicationProfile?
    @State private var availableThemes: [String] = []
    /// #298: opens the theme browser (browse-only here — this section
    /// reads the selected target; writes stay in ProfileSection).
    @State private var showThemeBrowser = false
    private var workspaceRoot: URL? { try? source.workspaceRoot() }

    var body: some View {
        Group {
            if let target {
                LabeledContent("Target Name", value: target.name)
                LabeledContent("Output", value: target.output)
                LabeledContent("Public", value: target.public == true ? "Yes" : "No")

                if let theme = target.theme, !theme.isEmpty {
                    LabeledContent("Theme", value: theme)
                }
                if let layout = target.layout, !layout.isEmpty {
                    LabeledContent("Layout", value: layout)
                }

                if let rules = target.layout_rules, !rules.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Layout Rules (\(rules.count))")
                            .foregroundStyle(.secondary)
                        ForEach(rules, id: \.selector) { rule in
                            Text("\(rule.selector) → \(rule.layout)")
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let sitemap = target.sitemap {
                    LabeledContent("Sitemap", value: sitemap.path)
                }
                if let rss = target.rss {
                    LabeledContent("RSS", value: rss.path)
                }
                if let llms = target.llms {
                    LabeledContent("LLMs.txt", value: llms.path)
                }

                if !availableThemes.isEmpty {
                    // #298: browse the themes visually (was: a comma blob).
                    Button {
                        showThemeBrowser = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Available Themes")
                                .foregroundStyle(.secondary)
                            Image(systemName: "paintpalette")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Browse themes visually")
                    .accessibilityLabel("Available Themes, \(availableThemes.count) themes")
                    .accessibilityHint("Opens the theme browser")
                }
            } else {
                Text("Target “\(targetName)” not found in profile.")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: "\(source.id.raw):\(targetName)") {
            load()
        }
        .sheet(isPresented: $showThemeBrowser) {
            ThemeBrowserView(
                themes: availableThemes,
                selection: target?.theme,
                workspaceRoot: workspaceRoot,
                onSelect: { _ in },
                onCancel: {}
            )
        }
    }

    private func load() {
        guard let root = try? source.workspaceRoot() else { return }
        availableThemes = ThemeCatalog.allThemes(for: root)
        if let pair = try? InspectorProfile.load(from: root),
           let prof = try? JSONDecoder().decode(PublicationProfile.self, from: pair.data)
        {
            profile = prof
            target = prof.targets?.first(where: { $0.name == targetName })
                ?? (targetName == "default" ? PublicationTarget(name: "default", output: "dist") : nil)
        }
    }
}
