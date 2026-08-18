import SwiftUI

/// Read-only document view for a decoded PublicationPlan (M8 / #89).
/// Shows declared targets, projections, inputs, site metadata, and editions.
struct PlanPane: View {
    let source: LocalSource

    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.toolbarBand) private var toolbarBand
    @State private var plan: PublicationPlan?

    var body: some View {
        Group {
            if let plan = activePlan {
                planDocument(plan)
            } else {
                ContentUnavailableView {
                    Label("No Publication Plan", systemImage: "doc.plaintext")
                } description: {
                    Text("No publication plan has been computed yet. Run plan to inspect declared outputs.")
                } actions: {
                    Button("Plan Publication") {
                        runtime.coordinator.run(.plan, store: store, runtime: runtime)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!runtime.coordinator.canRunVerb)
                }
            }
        }
        .task(id: source.id) {
            loadIfPossible()
        }
    }

    private var activePlan: PublicationPlan? {
        runtime.coordinator.latestPlan ?? plan
    }

    private func planDocument(_ plan: PublicationPlan) -> some View {
        List {
            Section {
                LabeledContent("Format", value: plan.format)
                if let version = plan.schema_version {
                    LabeledContent("Schema Version", value: "\(version)")
                }
                if let input = plan.input {
                    LabeledContent("Input Root", value: input)
                }
                if let format = plan.input_format {
                    LabeledContent("Input Format", value: format)
                }
            } header: {
                HStack {
                    Text("Publication Plan Overview")
                    Spacer()
                    Button("Re-plan") {
                        runtime.coordinator.run(.plan, store: store, runtime: runtime)
                    }
                    .controlSize(.small)
                    .disabled(!runtime.coordinator.canRunVerb)
                }
            }

            if let site = plan.site {
                Section("Site Metadata") {
                    if let title = site.title {
                        LabeledContent("Title", value: title)
                    }
                    if let url = site.url {
                        LabeledContent("URL", value: url)
                    }
                    if let desc = site.description {
                        LabeledContent("Description", value: desc)
                    }
                }
            }

            if let pub = plan.publication {
                Section("Publication Declaration") {
                    LabeledContent("Target", value: pub.target)
                    if let baseUrl = pub.base_url, !baseUrl.isEmpty {
                        LabeledContent("Base URL", value: baseUrl)
                    }
                    if let origin = pub.origin, !origin.isEmpty {
                        LabeledContent("Origin", value: origin)
                    }
                    if let basePath = pub.base_path, !basePath.isEmpty {
                        LabeledContent("Base Path", value: basePath)
                    }
                    if let did = pub.did, !did.isEmpty {
                        LabeledContent("DID", value: did)
                    }
                    if let name = pub.name, !name.isEmpty {
                        LabeledContent("Site Name", value: name)
                    }
                    if let siteKind = pub.site_kind, !siteKind.isEmpty {
                        LabeledContent("Site Kind", value: siteKind)
                    }
                    if let includes = pub.include, !includes.isEmpty {
                        LabeledContent("Include", value: includes.joined(separator: ", "))
                    }
                    if let excludes = pub.exclude, !excludes.isEmpty {
                        LabeledContent("Exclude", value: excludes.joined(separator: ", "))
                    }
                }
            }

            if let targets = plan.targets, !targets.isEmpty {
                Section("Declared Targets (\(targets.count))") {
                    ForEach(targets, id: \.name) { target in
                        PlanTargetRow(target: target)
                    }
                }
            }

            if let editions = plan.editions {
                Section("Declared Editions") {
                    if let ir = editions.ir {
                        LabeledContent("IR", value: ir.output)
                    }
                    if let rag = editions.rag {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("RAG Output", value: rag.output)
                            if let scope = rag.scope {
                                LabeledContent("Scope", value: scope)
                            }
                            if let split = rag.split_size {
                                LabeledContent("Split Size", value: "\(split) bytes")
                            }
                        }
                    }
                    if let context = editions.context {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Context Output", value: context.output)
                            if let scope = context.scope {
                                LabeledContent("Scope", value: scope)
                            }
                            if let split = context.split_size {
                                LabeledContent("Split Size", value: "\(split) bytes")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .safeAreaPadding(.top, toolbarBand)
    }

    private func loadIfPossible() {
        if runtime.coordinator.latestPlan == nil,
           runtime.coordinator.canRunVerb,
           source.profileURL() != nil {
            runtime.coordinator.run(.plan, store: store, runtime: runtime)
        }
    }
}

private struct PlanTargetRow: View {
    let target: PublicationPlanTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(target.name)
                    .font(.headline)
                Spacer()
                Text(target.public == true ? "Public" : "Internal")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }

            LabeledContent("Output Path", value: target.output)
                .font(.caption)

            if let theme = target.theme {
                LabeledContent("Theme", value: theme)
                    .font(.caption)
            }

            if let layout = target.layout {
                LabeledContent("Layout", value: layout)
                    .font(.caption)
            }

            if let projections = target.projections {
                HStack(spacing: 6) {
                    Text("Projections:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if projections.html == true {
                        ProjectionChip(title: "HTML")
                    }
                    if let sitemap = projections.sitemap {
                        ProjectionChip(title: "Sitemap: \(sitemap.path)")
                    }
                    if let rss = projections.rss {
                        ProjectionChip(title: "RSS: \(rss.path)")
                    }
                    if let llms = projections.llms {
                        ProjectionChip(title: "LLMs: \(llms.path)")
                    }
                }
                .padding(.top, 2)
            }

            if let rules = target.layout_rules, !rules.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Layout Rules:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(rules, id: \.selector) { rule in
                        HStack {
                            Text(rule.selector)
                                .font(.caption.monospaced())
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(rule.layout)
                                .font(.caption)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProjectionChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }
}
