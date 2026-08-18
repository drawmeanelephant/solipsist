import SwiftUI

/// Publish pane (M8 / #77): renders publication target details, plan,
/// evidence chain (`_boris/proof/`), Proof Pack archives, and publish actions.
struct PublishPane: View {
    let source: LocalSource

    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime
    @State private var profile: PublicationProfile?
    @State private var proofFiles: [ProofFileItem] = []
    @State private var planSummary: String?
    @State private var publishStatus: String?
    @State private var loadError: String?

    var body: some View {
        List {
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
                        planPublication()
                    }
                    .controlSize(.small)

                    if let target = profile?.publication?.target {
                        if target == "standard-site" {
                            Button("Publish to Standard.site") {
                                publishStandardSite()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else if target == "nostr" {
                            Button("Publish to Nostr…") {
                                publishNostr()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                if let planSummary {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan Output")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(planSummary)
                            .font(.caption.monospaced())
                    }
                    .padding(.vertical, 4)
                }

                if let publishStatus {
                    Text(publishStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
    }

    private func load() {
        guard let root = try? source.workspaceRoot() else {
            loadError = "Could not resolve workspace root."
            return
        }
        do {
            if let pair = try InspectorProfile.load(from: root) {
                profile = try? JSONDecoder().decode(PublicationProfile.self, from: pair.data)
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

    private func planPublication() {
        guard let root = try? source.workspaceRoot(), let engine = runtime.engine else { return }
        let profileURL = root.appendingPathComponent("boris.json")
        Task {
            if let result = try? await engine.plan(profileURL: profileURL) {
                planSummary = result.stdout.isEmpty ? "Exit code: \(result.exitCode)" : result.stdout
            }
        }
    }

    private func publishStandardSite() {
        guard let root = try? source.workspaceRoot(), let engine = runtime.engine else { return }
        let profileURL = root.appendingPathComponent("boris.json")
        Task {
            do {
                let result = try await engine.standardSitePublish(profileURL: profileURL)
                publishStatus = "Standard.site publish finished with exit code \(result.exitCode)."
                scanProofFiles(in: root)
            } catch {
                publishStatus = "Standard.site publish error: \(error.localizedDescription)"
            }
        }
    }

    private func publishNostr() {
        guard let root = try? source.workspaceRoot(), let engine = runtime.engine else { return }
        let profileURL = root.appendingPathComponent("boris.json")
        Task {
            do {
                let planResult = try await engine.nostrPlan(profileURL: profileURL)
                publishStatus = "Nostr plan: exit \(planResult.exitCode)"
                scanProofFiles(in: root)
            } catch {
                publishStatus = "Nostr error: \(error.localizedDescription)"
            }
        }
    }
}

struct ProofFileItem: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let size: String
}
