import SwiftUI

/// Seam between the SwiftUI toolbar and the AppKit text-view coordinator
/// (#263). The hosted view registers its applier; toolbar buttons publish.
@MainActor
final class ComposeFormatApplier: ObservableObject {
    /// Registered by the hosted text view; weakly captures its coordinator.
    var handler: ((ComposeFormat) -> Void)?

    func send(_ format: ComposeFormat) {
        handler?(format)
    }
}

/// The formatting row (#263): Bold · Italic · Strikethrough · Heading ·
/// Link · Code · Bullet · Numbered · Quote, hidden entirely for Cooklang.
struct ComposeFormatToolbar: View {
    let applier: ComposeFormatApplier

    var body: some View {
        HStack(spacing: 2) {
            wrapButton(.bold, icon: "bold", name: "Bold", hint: "Wrap the selection in bold markers")
            wrapButton(
                .italic, icon: "italic", name: "Italic",
                hint: "Wrap the selection in italic markers"
            )
            wrapButton(
                .strikethrough, icon: "strikethrough", name: "Strikethrough",
                hint: "Wrap the selection in strikethrough markers"
            )

            Menu {
                ForEach(ComposeFormat.headingLevels, id: \.self) { level in
                    Button("Heading \(level)") {
                        applier.send(.heading(level: level))
                    }
                }
            } label: {
                Text("H")
                    .frame(minWidth: 14)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Heading level")
            .accessibilityLabel("Heading")
            .accessibilityHint("Apply a heading level to the selected lines")

            wrapButton(.link, icon: "link", name: "Link", hint: "Turn the selection into a link")
            wrapButton(
                .codeSpan, icon: "chevron.left.forwardslash.chevron.right", name: "Code span",
                hint: "Wrap the selection in inline code markers"
            )
            wrapButton(
                .bulletList, icon: "list.bullet", name: "Bulleted list",
                hint: "Prefix every selected line with a bullet marker"
            )
            wrapButton(
                .numberedList, icon: "list.numbered", name: "Numbered list",
                hint: "Prefix every selected line with an ordered-list marker"
            )
            wrapButton(
                .quote, icon: "text.quote", name: "Block quote",
                hint: "Prefix every selected line with a quote marker"
            )
        }
        .buttonStyle(.borderless)
    }

    private func wrapButton(
        _ format: ComposeFormat,
        icon: String,
        name: String,
        hint: String
    ) -> some View {
        Button {
            applier.send(format)
        } label: {
            Image(systemName: icon)
        }
        .help(name)
        .accessibilityLabel(name)
        .accessibilityHint(hint)
    }
}
