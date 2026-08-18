import AppKit
import SwiftUI

/// Publish pane (M8 / #77 / #91): renders publication target details, deployment plan,
/// evidence chain (`_boris/proof/`), Proof Pack claims & checks, Nostr relay verdicts,
/// package checksums, and publish actions.
struct PublishPane: View {
    let source: LocalSource

    @Environment(WorkspaceStore.self) private var store
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.toolbarBand) private var toolbarBand
    @State private var profile: PublicationProfile?
    @State private var proofFiles: [ProofFileItem] = []
    @State private var proofPack: ProofPackDocument?
    @State private var claimsDoc: ProofClaimsDocument?
    @State private var checksDoc: ProofChecksDocument?
    @State private var nostrReport: NostrPublishReport?
    @State private var machineVersion: MachineReadableVersion?
    @State private var checksumEntries: [PackageChecksumEntry] = []
    @State private var loadError: String?
    @State private var credentialEpoch = 0

    var body: some View {
        List {
            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                }
            }

            publicationSection

            if let target = profile?.publication?.target, target == "github-pages" {
                githubPagesPlanSection
            }

            actionsSection

            if let nostr = nostrReport, let relays = nostr.relays, !relays.isEmpty {
                nostrVerdictsSection(report: nostr, relays: relays)
            }

            claimsAndChecksSection

            packageEvidenceSection

            evidenceFilesSection
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .safeAreaPadding(.top, toolbarBand)
        .task(id: source.id) {
            load()
        }
        .onChange(of: runtime.coordinator.isRunning) { wasRunning, isRunning in
            if wasRunning, !isRunning {
                credentialEpoch += 1
                load()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var publicationSection: some View {
        Section("Publication Declaration") {
            if let pub = profile?.publication {
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
                    LabeledContent("DID / Identity", value: did)
                }
                if let name = pub.name, !name.isEmpty {
                    LabeledContent("Site Name", value: name)
                }
                if let desc = pub.description, !desc.isEmpty {
                    LabeledContent("Description", value: desc)
                }
                if let discover = pub.show_in_discover {
                    LabeledContent("Discover Directory", value: discover ? "Visible" : "Hidden")
                }
                if let prune = pub.prune {
                    LabeledContent("Prune Stale Records", value: prune ? "Enabled" : "Disabled")
                }
            } else {
                Text("No `publication` section configured in boris.json.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var githubPagesPlanSection: some View {
        Section("GitHub Pages Deployment Plan") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.blue)
                    Text("Deterministic Static Build (No Local Secrets)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Boris builds `.nojekyll`, static HTML, and the cryptographic Proof Pack into staging. GitHub Actions deploys the committed artifacts without requiring local personal access tokens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            if let pub = profile?.publication {
                if let baseUrl = pub.base_url, !baseUrl.isEmpty {
                    LabeledContent("Public URL", value: baseUrl)
                }
                LabeledContent("Staging Output", value: "dist/")
                LabeledContent("Evidence Root", value: "_boris/proof/")
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section("Publish Actions") {
            VStack(alignment: .leading, spacing: 10) {
                // Top row: Plan + Target-specific actions
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("Plan") {
                            runtime.coordinator.run(.plan, store: store, runtime: runtime)
                        }
                        .controlSize(.small)
                        .disabled(!runtime.coordinator.canRunVerb)

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
                                .disabled(!runtime.coordinator.canRunVerb)

                                Button("Verify") {
                                    runtime.coordinator.run(
                                        .standardSiteVerify,
                                        store: store,
                                        runtime: runtime
                                    )
                                }
                                .controlSize(.small)
                                .disabled(!runtime.coordinator.canRunVerb)

                                Button("Records") {
                                    runtime.coordinator.run(
                                        .standardSiteRecords,
                                        store: store,
                                        runtime: runtime
                                    )
                                }
                                .controlSize(.small)
                                .disabled(!runtime.coordinator.canRunVerb)

                                Button("Sessions") {
                                    runtime.coordinator.run(
                                        .standardSiteSessions,
                                        store: store,
                                        runtime: runtime
                                    )
                                }
                                .controlSize(.small)
                                .disabled(!runtime.coordinator.canRunVerb)

                                Button("Smoke") {
                                    runtime.coordinator.run(
                                        .standardSiteSmoke,
                                        store: store,
                                        runtime: runtime
                                    )
                                }
                                .controlSize(.small)
                                .disabled(!runtime.coordinator.canRunVerb)

                                Button("Logout") {
                                    runtime.coordinator.run(
                                        .standardSiteLogout,
                                        store: store,
                                        runtime: runtime
                                    )
                                }
                                .controlSize(.small)
                                .disabled(!runtime.coordinator.canRunVerb)
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
                                .disabled(!runtime.coordinator.canRunVerb)
                            } else if target == "github-pages" {
                                Button("Build HTML & Proof") {
                                    runtime.coordinator.run(
                                        .buildHTML,
                                        store: store,
                                        runtime: runtime
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!runtime.coordinator.canRunVerb)
                            }
                        }

                        Button("Package Archive") {
                            runtime.coordinator.run(.package, store: store, runtime: runtime)
                        }
                        .controlSize(.small)
                        .disabled(!runtime.coordinator.canRunVerb)
                    }
                }

                credentialRow

                Text("Secrets are never put in argv or logs; they stream to Boris over stdin.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func nostrVerdictsSection(report: NostrPublishReport, relays: [NostrRelayVerdict]) -> some View {
        Section("Nostr Relay Publication Verdicts") {
            if let verdict = report.verdict {
                HStack {
                    Text("Overall Verdict")
                    Spacer()
                    Text(verdict.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(verdict.lowercased() == "complete" || verdict.lowercased() == "ok" ? .green : .orange)
                }
            }

            ForEach(relays) { relay in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: relay.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(relay.isSuccess ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(relay.relayURL)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(relay.displayMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var claimsAndChecksSection: some View {
        let allClaims = proofPack?.claims ?? claimsDoc?.claims ?? []
        let allChecks = proofPack?.checks ?? checksDoc?.checks ?? []
        let limitations = proofPack?.limitations ?? claimsDoc?.limitations ?? []

        if !allClaims.isEmpty || !allChecks.isEmpty || !limitations.isEmpty {
            Section("Proof Pack & Verification Claims") {
                if let digest = proofPack?.digest ?? proofPack?.model_digest {
                    LabeledContent("Model Digest", value: digest)
                        .font(.caption)
                }

                if !allClaims.isEmpty {
                    Text("Declared Claims")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(allClaims) { claim in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: claim.isVerified ? "checkmark.seal.fill" : "seal")
                                .foregroundStyle(claim.isVerified ? .green : .blue)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(claim.displayText)
                                        .font(.subheadline)
                                    Spacer()
                                    if let cat = claim.category {
                                        Text(cat)
                                            .font(.caption2)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.secondary.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                }
                                if let evidence = claim.evidence ?? claim.artifacts, !evidence.isEmpty {
                                    Text("Evidence: " + evidence.joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !allChecks.isEmpty {
                    Text("Verification Checks")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(allChecks) { check in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: check.isPassed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(check.isPassed ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.displayTitle)
                                    .font(.subheadline)
                                if let msg = check.displayMessage {
                                    Text(msg)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let target = check.target ?? check.path {
                                    Text(target)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !limitations.isEmpty {
                    Text("Declared Limitations")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(limitations, id: \.self) { limitation in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.orange)
                            Text(limitation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var packageEvidenceSection: some View {
        if machineVersion != nil || !checksumEntries.isEmpty {
            Section("Package Evidence & Checksums") {
                if let ver = machineVersion {
                    LabeledContent("Engine Version", value: ver.displayVersion)
                    if let commit = ver.displayCommit {
                        LabeledContent("Commit", value: commit)
                    }
                    if let platform = ver.displayPlatform {
                        LabeledContent("Platform", value: platform)
                    }
                    if let compiler = ver.displayCompiler {
                        LabeledContent("Compiler ID", value: compiler)
                    }
                    if let ir = ver.ir_version {
                        LabeledContent("IR Version", value: ir)
                    }
                }

                if !checksumEntries.isEmpty {
                    Text("SHA256 Fingerprints")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(checksumEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.filename)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.sha256, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .help("Copy SHA-256")
                            }
                            Text(entry.sha256)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var evidenceFilesSection: some View {
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

    @ViewBuilder
    private var credentialRow: some View {
        let target = credentialTarget
        HStack {
            Text("Credential")
            Spacer()
            Text(credentialStatus)
                .foregroundStyle(.secondary)
            if let target, runtime.credentials.hasSecret(for: target) {
                Button("Forget") {
                    try? runtime.credentials.clearCredential(for: target)
                    credentialEpoch += 1
                }
                .controlSize(.small)
            }
        }
        .font(.caption)
    }

    private var credentialTarget: String? {
        switch profile?.publication?.target {
        case "standard-site": PublishTargets.standardSite
        case "nostr": PublishTargets.nostr
        default: nil
        }
    }

    private var credentialStatus: String {
        _ = credentialEpoch
        guard let target = credentialTarget else { return "not required" }
        if runtime.credentials.isRemembered(for: target) {
            return "in Keychain"
        }
        if runtime.credentials.hasSecret(for: target) {
            return "this session"
        }
        return "not set"
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
        loadProofArtifacts(in: root)
        loadNostrReport(in: root)
        loadPackageMetadata(in: root)
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

    private func loadProofArtifacts(in root: URL) {
        let proofDir = root.appendingPathComponent("_boris/proof", isDirectory: true)

        let proofPackURL = proofDir.appendingPathComponent("proof-pack.json")
        if let data = try? Data(contentsOf: proofPackURL) {
            proofPack = try? JSONDecoder().decode(ProofPackDocument.self, from: data)
        } else {
            proofPack = nil
        }

        let claimsURL = proofDir.appendingPathComponent("claims.json")
        if let data = try? Data(contentsOf: claimsURL) {
            claimsDoc = try? JSONDecoder().decode(ProofClaimsDocument.self, from: data)
        } else {
            claimsDoc = nil
        }

        let checksURL = proofDir.appendingPathComponent("checks.json")
        if let data = try? Data(contentsOf: checksURL) {
            checksDoc = try? JSONDecoder().decode(ProofChecksDocument.self, from: data)
        } else {
            checksDoc = nil
        }
    }

    private func loadNostrReport(in root: URL) {
        let nostrURL = root.appendingPathComponent("_boris/nostr-publish.json")
        if let data = try? Data(contentsOf: nostrURL) {
            nostrReport = try? JSONDecoder().decode(NostrPublishReport.self, from: data)
        } else {
            nostrReport = nil
        }
    }

    private func loadPackageMetadata(in root: URL) {
        // Look for MACHINE-READABLE-VERSION.json in packages/ or _boris/ or root
        let candidates = [
            root.appendingPathComponent("packages/MACHINE-READABLE-VERSION.json"),
            root.appendingPathComponent("_boris/MACHINE-READABLE-VERSION.json"),
            root.appendingPathComponent("MACHINE-READABLE-VERSION.json"),
            root.appendingPathComponent("vendor/boris-agent-kit/MANIFEST.json"),
        ]
        machineVersion = nil
        for candidate in candidates {
            if let data = try? Data(contentsOf: candidate),
               let decoded = try? JSONDecoder().decode(MachineReadableVersion.self, from: data) {
                machineVersion = decoded
                break
            }
        }

        // Look for SHA256SUMS in packages/ or _boris/ or root
        let checksumCandidates = [
            root.appendingPathComponent("packages/SHA256SUMS"),
            root.appendingPathComponent("_boris/SHA256SUMS"),
            root.appendingPathComponent("SHA256SUMS"),
            root.appendingPathComponent("vendor/boris-agent-kit/SHA256SUMS"),
        ]
        checksumEntries = []
        for candidate in checksumCandidates {
            if let text = try? String(contentsOf: candidate, encoding: .utf8) {
                let parsed = PackageChecksumEntry.parse(from: text)
                if !parsed.isEmpty {
                    checksumEntries = parsed
                    break
                }
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
