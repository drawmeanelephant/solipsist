import SwiftUI

/// The compose status bar (#265): word count leads the right-hand
/// cluster; cursor position, char count, and the coordinator token live
/// behind a chevron, collapsed by default. Save state is a typed signal
/// (icon + color), never a substring match. #228's stats stay reachable
/// in the expanded strip.
struct ComposeStatusBar: View {
    let loadError: String?
    @Bindable var document: ComposeDocument
    let coordinatorSummary: String
    let saveSignal: ComposeSaveFlow.Signal?
    @Binding var showDetailStats: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                leftCluster
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    Text(document.wordCountText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .layoutPriority(1)
                        .help("Word count")
                    if showDetailStats {
                        detailStats
                    }
                    if let signal = saveSignal {
                        saveSignalView(signal)
                    }
                }
                .accessibilityElement(children: .combine)
                detailStatsToggle
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    @ViewBuilder
    private var leftCluster: some View {
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
    }

    /// Secondary strip (#265): cursor position, chars/selection, and the
    /// coordinator token demoted out of the primary bar.
    private var detailStats: some View {
        HStack(spacing: 10) {
            Text(document.cursorText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help("Cursor position")
            Text(document.characterCountText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help(document.selectedLength > 0 ? "Selected characters" : "Character count")
            Text(coordinatorSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help("Save → validate coordinator activity")
        }
    }

    /// ✓ Saved in secondary / ✗ + message in red — driven by the outcome
    /// enum, not text matching.
    private func saveSignalView(_ signal: ComposeSaveFlow.Signal) -> some View {
        HStack(spacing: 4) {
            Image(systemName: signal.symbolName)
                .imageScale(.small)
            Text(signal.message)
        }
        .font(.caption)
        .foregroundStyle(signal.isError ? Color.red : Color.secondary)
        .help(signal.isError ? signal.message : "Buffer written to disk")
        .accessibilityLabel(
            signal.isError ? "Save failed: \(signal.message)" : "Saved"
        )
    }

    private var detailStatsToggle: some View {
        Button {
            showDetailStats.toggle()
        } label: {
            Image(systemName: showDetailStats ? "chevron.left" : "chevron.right")
                .resizable()
                .scaledToFit()
                .frame(width: 9, height: 9)
                .padding(3)
        }
        .buttonStyle(.borderless)
        .help(showDetailStats ? "Hide detailed statistics" : "Show detailed statistics")
        .accessibilityLabel("Detailed statistics")
        .accessibilityHint("Show or hide cursor position and character counts")
        .accessibilityAddTraits(showDetailStats ? [.isSelected] : [])
    }
}
