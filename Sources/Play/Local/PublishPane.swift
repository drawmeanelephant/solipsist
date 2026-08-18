import SwiftUI

/// Publish pane (M8 / #77): renders publication target details, plan,
/// evidence chain (`_boris/proof/`), and publish actions. Actions go through
/// the coordinator — this view never spawns `boris`.
struct PublishPane: View {
    let source: LocalSource

    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime
    @State private var profile: PublicationProfile?
    @State private var proofFiles: [ProofFileItem] = []
    @State private var loadError: String?

    var body: some View {
        List {
            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                }
            }

            Section("Publication Declaration") {
                if let pub = profile?.publication {
                    LabeledContent("Target", value: pub.target)
                    LabeledContent("Base URL", value: pub.base_url)
                    LabeledContent("Origin", value: pub.origin)
                    if !pub.base_path.isEmpty {
                        LabeledContent("Base Path", value: pub.base_path)
                    }
                    if let did = pub.did {
                        LabeledContent("DID", value: did)
                    }
                    if let name = pub.name {
                        LabeledContent("Site Name", value: name)
                    }
                } else {
                    Text("No `publication` section configured in boris.json.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Publish Actions") {
                HStack(spacing: 12) {
                    Button("Plan Publication") {
                        runtime.coordinator.run(.plan, store: store, runtime: runtime)
                    }
                    .controlSize(.small)
                    .disabled(runtime.coordinator.isRunning)

                    if let target = profile?.publication?.target {
                        if target == "standard-site" {
                            Button("Publish to Standard.site") {
                                runtime.coordinator.run(
                                    .publishStandardSite,
                                    store: store,
                                    runtime: runtime
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(runtime.coordinator.isRunning)
                        } else if target == "nostr" {
                            Button("Publish to Nostr…") {
                                runtime.coordinator.run(
                                    .publishNostr,
                                    store: store,
                                    runtime: runtime
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(runtime.coordinator.isRunning)
                        }
                    }
                }

                Text("Results land in the problems list. Stop (⌘.) cancels the job.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Evidence Chain (_boris/proof/)") {
                if proofFiles.isEmpty {
                    Text("No proof files generated yet. Run a build to generate evidence.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(proofFiles) { file in
                        HStack {
                            Image(systemName: "checkmark.seal")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.name)
                                    .font(.body)
                                Text(file.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(file.size)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .task(id: source.id) {
            load()
        }
        .onChange(of: runtime.coordinator.isRunning) { wasRunning, isRunning in
            if wasRunning, !isRunning, let root = try? source.workspaceRoot() {
                scanProofFiles(in: root)
            }
        }
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
            }
        } catch {
            loadError = error.localizedDescription
        }

        scanProofFiles(in: root)
    }

    private func scanProofFiles(in root: URL) {
        let proofDir = root.appendingPathComponent("_boris/proof", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: proofDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            proofFiles = []
            return
        }

        var items: [ProofFileItem] = []
        for file in contents {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            items.append(ProofFileItem(
                id: file.lastPathComponent,
                name: file.lastPathComponent,
                path: "_boris/proof/\(file.lastPathComponent)",
                size: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            ))
        }
        proofFiles = items.sorted(by: { $0.name < $1.name })
    }
}

struct ProofFileItem: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let size: String
}
