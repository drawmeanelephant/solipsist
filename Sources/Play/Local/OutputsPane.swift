import SwiftUI

/// Outputs pane (M7 / #76): lists HTML targets and editions declared in the
/// publication profile (`boris.json`). Supports fan-out "Build All" and per-row
/// "Build this". Selection is written to `WorkspaceStore` as `noun.kind == "target"`
/// or `noun.kind == "edition"`.
struct OutputsPane: View {
    let source: LocalSource

    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.toolbarBand) private var toolbarBand
    @State private var profile: PublicationProfile?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let profile {
                outputsList(profile)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Profile Unavailable", systemImage: "gearshape")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Reload") { load() }
                }
            } else {
                ContentUnavailableView {
                    Label("No Profile", systemImage: "gearshape")
                } description: {
                    Text("No boris.json found in this workspace. Create one or plan to generate defaults.")
                }
            }
        }
        .task(id: source.id) {
            load()
        }
    }

    private func outputsList(_ profile: PublicationProfile) -> some View {
        List(selection: selectedOutputID) {
            Section {
                if let targets = profile.targets, !targets.isEmpty {
                    ForEach(targets, id: \.name) { target in
                        TargetRow(
                            target: target,
                            isBusy: runtime.coordinator.isRunning,
                            onBuild: { requestBuild(kind: "target", id: target.name, title: target.name) }
                        )
                        .tag("target:\(target.name)")
                    }
                } else {
                    let defaultTarget = PublicationTarget(name: "default", output: "dist")
                    TargetRow(
                        target: defaultTarget,
                        isBusy: runtime.coordinator.isRunning,
                        onBuild: { requestBuild(kind: "target", id: "default", title: "default") }
                    )
                    .tag("target:default")
                }
            } header: {
                HStack {
                    Text("HTML Targets")
                    Spacer()
                    Button("Build All") {
                        runtime.coordinator.run(.buildAll, store: store, runtime: runtime)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(runtime.coordinator.isRunning)
                }
            }

            if let editions = profile.editions {
                Section("Editions") {
                    if let ir = editions.ir {
                        EditionRow(
                            name: "IR (.boris)",
                            output: ir.output,
                            kind: "ir",
                            isBusy: runtime.coordinator.isRunning,
                            onBuild: { requestBuild(kind: "edition", id: "ir", title: "IR") }
                        )
                        .tag("edition:ir")
                    }
                    if let rag = editions.rag {
                        EditionRow(
                            name: "RAG",
                            output: rag.output,
                            kind: "rag",
                            isBusy: runtime.coordinator.isRunning,
                            onBuild: { requestBuild(kind: "edition", id: "rag", title: "RAG") }
                        )
                        .tag("edition:rag")
                    }
                    if let context = editions.context {
                        EditionRow(
                            name: "Context",
                            output: context.output,
                            kind: "context",
                            isBusy: runtime.coordinator.isRunning,
                            onBuild: { requestBuild(kind: "edition", id: "context", title: "Context") }
                        )
                        .tag("edition:context")
                    }
                }
            }
        }
        .listStyle(.inset)
        .safeAreaPadding(.top, toolbarBand)
    }

    private var selectedOutputID: Binding<String?> {
        Binding(
            get: {
                if let noun = store.selection.noun {
                    return "\(noun.kind):\(noun.id)"
                }
                return nil
            },
            set: { newTag in
                guard let newTag else {
                    store.select(noun: nil)
                    return
                }
                let parts = newTag.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let kind = String(parts[0])
                    let id = String(parts[1])
                    store.select(noun: WorkspaceNoun(kind: kind, id: id, title: id))
                }
            }
        )
    }

    private func load() {
        guard let root = try? source.workspaceRoot() else {
            loadError = "Could not resolve workspace root."
            return
        }
        do {
            if let pair = try InspectorProfile.load(from: root) {
                do {
                    profile = try JSONDecoder().decode(PublicationProfile.self, from: pair.data)
                    loadError = nil
                } catch {
                    profile = nil
                    loadError = error.localizedDescription
                }
            } else {
                profile = nil
                loadError = nil
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Select the row, then ask the coordinator. Play never spawns `boris`.
    private func requestBuild(kind: String, id: String, title: String) {
        store.select(noun: WorkspaceNoun(kind: kind, id: id, title: title))
        runtime.coordinator.run(.buildThis, store: store, runtime: runtime)
    }
}

private struct TargetRow: View {
    let target: PublicationTarget
    let isBusy: Bool
    let onBuild: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text(target.name)
                    .font(.headline)
                if target.public == true {
                    Text("PUBLIC")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.2))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Spacer()
                Button("Build", action: onBuild)
                    .controlSize(.small)
                    .disabled(isBusy)
            }
            HStack(spacing: 12) {
                Label(target.output, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let theme = target.theme, !theme.isEmpty {
                    Label(theme, systemImage: "paintpalette")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let layout = target.layout, !layout.isEmpty {
                    Label(layout, systemImage: "rectangle.3.group")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let projections = projectionsList, !projections.isEmpty {
                HStack(spacing: 8) {
                    ForEach(projections, id: \.self) { proj in
                        Text(proj)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var projectionsList: [String]? {
        var list: [String] = []
        if let sitemap = target.sitemap { list.append("sitemap: \(sitemap.path)") }
        if let rss = target.rss { list.append("rss: \(rss.path)") }
        if let llms = target.llms { list.append("llms: \(llms.path)") }
        return list.isEmpty ? nil : list
    }
}

private struct EditionRow: View {
    let name: String
    let output: String
    let kind: String
    let isBusy: Bool
    let onBuild: () -> Void

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body)
                Text(output)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Build", action: onBuild)
                .controlSize(.small)
                .disabled(isBusy)
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch kind {
        case "ir": return "cpu"
        case "rag": return "brain"
        case "context": return "doc.text.magnifyingglass"
        default: return "shippingbox"
        }
    }
}
