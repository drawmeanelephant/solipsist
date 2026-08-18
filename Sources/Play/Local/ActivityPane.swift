import SwiftUI

/// Activity pane (M3 / #89): shows execution history for the last N coordinator jobs,
/// tracking verb, exit code, execution timings duration, problem counts, and diagnostics.
struct ActivityPane: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.toolbarBand) private var toolbarBand

    var body: some View {
        Group {
            if runtime.coordinator.activityHistory.isEmpty {
                ContentUnavailableView {
                    Label("No Activity", systemImage: "clock")
                } description: {
                    Text("Jobs run by the coordinator will appear here.")
                }
            } else {
                activityList
            }
        }
    }

    private var activityList: some View {
        List {
            Section {
                ForEach(runtime.coordinator.activityHistory) { item in
                    ActivityRow(activity: item)
                }
            } header: {
                HStack {
                    Text("History (\(runtime.coordinator.activityHistory.count))")
                    Spacer()
                    Button("Clear") {
                        runtime.coordinator.clearActivity()
                    }
                    .controlSize(.small)
                }
            }
        }
        .listStyle(.inset)
        .safeAreaPadding(.top, toolbarBand)
    }
}

private struct ActivityRow: View {
    let activity: CoordinatorActivity
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                statusIcon
                Text(activity.verb.rawValue)
                    .font(.headline)
                Spacer()
                if let duration = activity.durationNs {
                    Text(formatDuration(duration))
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
                if let exit = activity.exitCode {
                    Text("exit \(exit)")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(exit == 0 ? Color.secondary : Color.red)
                }
                Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(activity.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if activity.timings != nil {
                DisclosureGroup("Timings breakdown", isExpanded: $isExpanded) {
                    if let timings = activity.timings {
                        VStack(alignment: .leading, spacing: 4) {
                            if let mode = timings.mode {
                                LabeledContent("Mode", value: mode)
                                    .font(.caption)
                            }
                            if let totalNs = timings.totalNs {
                                LabeledContent("Reported Total", value: formatDuration(totalNs))
                                    .font(.caption)
                            }
                            if let phases = timings.phases, !phases.isEmpty {
                                Text("Phases:")
                                    .font(.caption.weight(.medium))
                                    .padding(.top, 2)
                                ForEach(phases.keys.sorted(), id: \.self) { phase in
                                    if let durationNs = phases[phase] {
                                        LabeledContent(phase, value: formatDuration(durationNs))
                                            .font(.caption2.monospacedDigit())
                                    }
                                }
                            }
                            if let counters = timings.counters {
                                Text("Counters:")
                                    .font(.caption.weight(.medium))
                                    .padding(.top, 2)
                                if let reads = counters.page_reads {
                                    LabeledContent("Page Reads", value: "\(reads)")
                                        .font(.caption2.monospacedDigit())
                                }
                                if let inc = counters.include_reads {
                                    LabeledContent("Include Reads", value: "\(inc)")
                                        .font(.caption2.monospacedDigit())
                                }
                                if let fast = counters.fast_path_hits {
                                    LabeledContent("Fast Path Hits", value: "\(fast)")
                                        .font(.caption2.monospacedDigit())
                                }
                                if let bytes = counters.hash_bytes {
                                    LabeledContent("Hash Bytes", value: "\(bytes)")
                                        .font(.caption2.monospacedDigit())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if activity.isSuccess {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.medium)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .imageScale(.medium)
        }
    }

    private func formatDuration(_ ns: Int) -> String {
        if ns < 1_000 {
            return "\(ns) ns"
        } else if ns < 1_000_000 {
            return "\(ns / 1_000) µs"
        } else if ns < 1_000_000_000 {
            return "\(ns / 1_000_000) ms"
        } else {
            let seconds = Double(ns) / 1_000_000_000.0
            return String(format: "%.2f s", seconds)
        }
    }
}
