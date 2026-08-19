import SwiftUI

/// Content-audit mailbox (LATER-1 / #165): runs `boris-content-audit`
/// against the selected source and renders the findings report. Play
/// never spawns the tool — the coordinator does, through the engine's
/// single process slot (`runTool`). Report lands in the app container
/// (`ContentAuditOutput`), never the user's content tree.
struct ContentAuditPane: View {
    let source: LocalSource

    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.toolbarBand) private var toolbarBand

    @State private var report: ContentAuditReport?
    @State private var loadError: String?
    @State private var ranOnce = false

    var body: some View {
        Group {
            if let report {
                reportView(report)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Audit Unavailable", systemImage: "checkmark.shield")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Run Again") { run() }
                }
            } else {
                ContentUnavailableView {
                    Label("Content Audit", systemImage: "checkmark.shield")
                } description: {
                    Text(isAuditing ? "Auditing the content graph…" : "No audit report yet")
                } actions: {
                    Button("Run Audit") { run() }
                }
            }
        }
        .safeAreaPadding(.top, toolbarBand)
        .task(id: source.id) {
            loadReport()
            ranOnce = true
            run()
        }
        .onChange(of: runtime.coordinator.isRunning) { _, running in
            guard !running, runtime.coordinator.lastVerb == .contentAudit else { return }
            loadReport()
        }
    }

    private var isAuditing: Bool {
        runtime.coordinator.isRunning && runtime.coordinator.verb == .contentAudit
    }

    private func run() {
        guard runtime.coordinator.canRunVerb else { return }
        runtime.coordinator.run(.contentAudit, store: store, runtime: runtime)
    }

    private func loadReport() {
        let url = ContentAuditOutput.directory(for: source).appendingPathComponent("report.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            report = nil
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ContentAuditReport.self, from: data)
            report = decoded
            loadError = nil
        } catch {
            loadError = "Could not read the audit report: \(String(describing: error))"
        }
    }

    private func reportView(_ report: ContentAuditReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(report)
            Divider()
            if report.exceptions.isEmpty {
                ContentUnavailableView {
                    Label("No Findings", systemImage: "checkmark.circle")
                } description: {
                    Text("The content graph passed the selected audit checks.")
                }
            } else {
                exceptionsList(report.exceptions)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ report: ContentAuditReport) -> some View {
        HStack(spacing: 16) {
            Label("Content Audit", systemImage: "checkmark.shield")
                .font(.headline)
            Spacer()
            if let totals = report.totals {
                stat("\(totals.records_discovered ?? 0)", "records")
                stat("\(totals.malformed_records ?? 0)", "malformed")
                stat("\(totals.dead_references ?? 0)", "dead refs")
                stat("\(totals.mapped_poetry ?? 0)", "poetry mapped")
            }
            Button(isAuditing ? "Auditing…" : "Re-run") {
                run()
            }
            .disabled(isAuditing)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func exceptionsList(_ exceptions: [ContentAuditReport.Exception]) -> some View {
        List(exceptions) { item in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.severity ?? "finding")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background((item.severity == "structural" ? Color.orange : Color.red).opacity(0.18))
                        .foregroundStyle(item.severity == "structural" ? Color.orange : Color.red)
                        .clipShape(Capsule())
                    Text(item.record_id ?? "unknown record")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                }
                Text(item.detail ?? item.kind ?? "finding")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
    }
}

/// Decoded `boris-content-audit` report.json (ENGINE-CONTRACTS §8,
/// schema_version 1). Field names follow the tool's snake_case contract;
/// only the fields this pane renders are declared (D8: unknown fields
/// degrade, never crash).
struct ContentAuditReport: Decodable, Sendable {
    var format_id: String?
    var schema_version: Int?
    var mode: String?
    var totals: Totals?
    var exceptions: [Exception]
    var records: [Record]?

    struct Totals: Decodable, Sendable {
        var records_discovered: Int?
        var source_records: Int?
        var poetry_records: Int?
        var other_records: Int?
        var excluded_records: Int?
        var mapped_poetry: Int?
        var orphan_poetry: Int?
        var ambiguous_poetry: Int?
        var malformed_records: Int?
        var dead_references: Int?
    }

    struct Exception: Decodable, Sendable, Identifiable {
        var id: String { "\(record_id ?? "")-\(kind ?? "")-\(detail ?? "")" }
        var kind: String?
        var severity: String?
        var record_id: String?
        var detail: String?
    }

    struct Record: Decodable, Sendable {
        var id: String?
        var kind: String?
        var collection: String?
        var source_path: String?
        var status: String?
        var poetry_type: String?
        var alignment: String?
        var owner: String?
        var verse_units: Int?
        var malformed_units: Int?
        var density_in_band: Bool?
    }
}
