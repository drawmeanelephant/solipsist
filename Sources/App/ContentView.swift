import SwiftUI

/// Minimal M1 app shell: proves the engine wiring (locate embedded binary →
/// run Boris IR build → decode JSON contracts) inside the sandboxed app.
struct ContentView: View {
    private let engine: BorisEngine?
    private let engineError: String?

    @State private var status = "idle"
    @State private var detail = ""
    @State private var contentRoot: URL?

    init() {
        do {
            let engine = try BorisEngine()
            self.engine = engine
            self.engineError = nil
        } catch {
            self.engine = nil
            self.engineError = String(describing: error)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Solipsist — Boris Desktop")
                .font(.title2.weight(.semibold))

            engineStatus

            HStack(spacing: 8) {
                Button("Open Content Folder…", action: openPanel)
                    .disabled(engine == nil)
                Button("Build IR", action: runBuild)
                    .disabled(engine == nil || contentRoot == nil)
            }

            if let contentRoot {
                Text("content: \(contentRoot.path)")
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            Text(status)
                .font(.headline)

            ScrollView {
                Text(detail)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
    }

    private var engineStatus: some View {
        Group {
            if let engine {
                Text("engine: \(engine.binaryURL.path)")
            } else {
                Text("engine: NOT FOUND — \(engineError ?? "?")")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .textSelection(.enabled)
        .foregroundStyle(.secondary)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a Boris content folder (the --input root)"
        if panel.runModal() == .OK, let url = panel.url {
            contentRoot = url
        }
    }

    private func runBuild() {
        guard let engine, let contentRoot else { return }
        status = "building…"
        detail = ""
        let outDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("solipsist-build-\(UUID().uuidString)")

        Task {
            // Sandboxed app: keep the security-scoped access alive for the
            // duration of the build.
            let scoped = contentRoot.startAccessingSecurityScopedResource()
            defer {
                if scoped { contentRoot.stopAccessingSecurityScopedResource() }
            }
            do {
                let build = try await engine.buildIR(contentRoot: contentRoot, outDir: outDir)
                var lines: [String] = []
                lines.append("exit \(build.exitCode)  ok=\(build.report.ok)")
                lines.append("schema \(build.report.schemaVersion)  compiler \(build.report.compiler ?? "n/a")")
                lines.append("pages \(build.report.pageCount ?? -1)  errors \(build.report.errorCount ?? -1)")
                for d in build.report.diagnostics {
                    let loc = "\(d.sourcePath ?? "-"):\(d.line.map(String.init) ?? "-"):\(d.column.map(String.init) ?? "-")"
                    lines.append("[\(d.severity)] \(d.code) \(loc) \(d.message)")
                }
                if let manifest = build.manifest {
                    let trunks = manifest.pages.filter(\.isTrunk)
                    lines.append("manifest: \(manifest.pages.count) pages, \(trunks.count) trunks")
                }
                if let graph = build.graph {
                    lines.append("graph: \(graph.nodes.count) nodes, \(graph.edges.count) edges, frozen=\(graph.frozen)")
                }
                status = build.report.ok
                    ? "build succeeded"
                    : "build failed (\(build.report.errorCount ?? 0) error(s))"
                detail = lines.joined(separator: "\n")
            } catch {
                status = "build error"
                detail = String(describing: error)
            }
        }
    }
}
