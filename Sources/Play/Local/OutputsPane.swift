import SwiftUI

/// Outputs pane (M7 / #76): lists HTML targets and editions declared in the
/// publication profile (`boris.json`). Supports fan-out "Build All" and per-row
/// "Build this". Selection is written to `WorkspaceStore` as `noun.kind == "target"`
/// or `noun.kind == "edition"`.
struct OutputsPane: View {
    let source: any PlayFolderSource

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

    /// True when boris.json was modified after the last successful Plan.
    private var isStalePlan: Bool {
        guard let planTime = runtime.coordinator.planTimestamp else { return false }
        guard let root = try? source.workspaceRoot() else { return false }
        let profileURL = root.appendingPathComponent("boris.json")
        guard let mtime = (try? FileManager.default.attributesOfItem(atPath: profileURL.path))?[.modificationDate] as? Date else { return false }
        return mtime > planTime
    }

    private func outputsList(_ profile: PublicationProfile) -> some View {
        List(selection: selectedOutputID) {
            Section {
                if let targets = profile.targets, !targets.isEmpty {
                    ForEach(targets, id: \.name) { target in
                        TargetRow(
                            target: target,
                            activity: runtime.coordinator.lastActivity(for: target.name),
                            isBusy: runtime.coordinator.isRunning,
                            onBuild: { requestBuild(kind: "target", id: target.name, title: target.name) }
                        )
                        .tag("target:\(target.name)")
                    }
                } else {
                    let defaultTarget = PublicationTarget(name: "default", output: "dist")
                    TargetRow(
                        target: defaultTarget,
                        activity: runtime.coordinator.lastActivity(for: "default"),
                        isBusy: runtime.coordinator.isRunning,
                        onBuild: { requestBuild(kind: "target", id: "default", title: "default") }
                    )
                    .tag("target:default")
                }
            } header: {
                HStack {
                    Text("HTML Targets")
                    if isStalePlan {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .help("boris.json changed since last Plan — run Plan to refresh")
                    }
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
                            activity: runtime.coordinator.lastActivity(for: "ir"),
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
                            activity: runtime.coordinator.lastActivity(for: "rag"),
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
                            activity: runtime.coordinator.lastActivity(for: "context"),
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
    let activity: CoordinatorActivity?
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
                if let activity {
                    exitBadge(activity)
                    if let duration = activity.durationNs {
                        Text(formatDuration(duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
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

    @ViewBuilder
    private func exitBadge(_ activity: CoordinatorActivity) -> some View {
        if let exit = activity.exitCode {
            Text("exit \(exit)")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(exit == 0 ? Color.secondary : Color.red)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    (exit == 0 ? Color.secondary : Color.red).opacity(0.12),
                    in: Capsule()
                )
        }
    }

    private func formatDuration(_ ns: Int) -> String {
        if ns < 1_000 {
            return "\(ns)ns"
        } else if ns < 1_000_000 {
            return "\(ns / 1_000)µs"
        } else if ns < 1_000_000_000 {
            return "\(ns / 1_000_000)ms"
        } else {
            let seconds = Double(ns) / 1_000_000_000.0
            return String(format: "%.2fs", seconds)
        }
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
    let activity: CoordinatorActivity?
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
            if let activity {
                if let exit = activity.exitCode {
                    Text("exit \(exit)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(exit == 0 ? Color.secondary : Color.red)
                }
                if let duration = activity.durationNs {
                    Text(formatDuration(duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Build", action: onBuild)
                .controlSize(.small)
                .disabled(isBusy)
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ ns: Int) -> String {
        if ns < 1_000 {
            return "\(ns)ns"
        } else if ns < 1_000_000 {
            return "\(ns / 1_000)µs"
        } else if ns < 1_000_000_000 {
            return "\(ns / 1_000_000)ms"
        } else {
            let seconds = Double(ns) / 1_000_000_000.0
            return String(format: "%.2fs", seconds)
        }
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
