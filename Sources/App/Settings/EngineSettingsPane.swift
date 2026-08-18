import AppKit
import SwiftUI

/// Settings pane displaying the Boris compiler and Oliver renderer binary status,
/// active paths, detected versions, custom path selection, and search-order guidance.
struct EngineSettingsPane: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var refreshTrigger = UUID()

    @AppStorage("customBorisBinaryPath") private var customBorisPath: String = ""
    @AppStorage("customOliverBinaryPath") private var customOliverPath: String = ""
    @AppStorage("customBorisEditorBinaryPath") private var customEditorPath: String = ""

    private var borisURL: URL? {
        _ = refreshTrigger
        return BorisBinary.locate()
    }

    private var oliverURL: URL? {
        _ = refreshTrigger
        return OliverBinary.locate(borisBinary: borisURL)
    }

    private var editorURL: URL? {
        _ = refreshTrigger
        if !customEditorPath.isEmpty, FileManager.default.isExecutableFile(atPath: customEditorPath) {
            return URL(fileURLWithPath: customEditorPath)
        }
        if let env = ProcessInfo.processInfo.environment["SOLIPSIST_BORIS_EDITOR_BIN"],
           !env.isEmpty, FileManager.default.isExecutableFile(atPath: env)
        {
            return URL(fileURLWithPath: env)
        }
        if let boris = borisURL {
            let sibling = boris.deletingLastPathComponent().appendingPathComponent("boris-editor")
            if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        }
        if let bundled = Bundle.main.url(forResource: "boris-editor", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path)
        {
            return bundled
        }
        return nil
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Boris Engine") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(runtime.engine != nil ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(runtime.engineVersion)
                            .fontWeight(.medium)
                    }
                }

                if let path = runtime.enginePath ?? borisURL?.path {
                    LabeledContent("Binary Path") {
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    LabeledContent("Origin") {
                        Text(originDescription(for: path))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let error = runtime.engineError {
                    LabeledContent("Error") {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                LabeledContent("Custom Binary") {
                    HStack(spacing: 8) {
                        Button("Choose Custom Boris…") {
                            chooseBinary(prompt: "Select Boris executable") { path in
                                customBorisPath = path
                                runtime.reloadEngine()
                                refreshTrigger = UUID()
                            }
                        }
                        if !customBorisPath.isEmpty {
                            Button("Reset to Embedded") {
                                customBorisPath = ""
                                runtime.reloadEngine()
                                refreshTrigger = UUID()
                            }
                        }
                    }
                }
            } header: {
                Text("Boris Compiler")
            }

            Section {
                LabeledContent("Oliver Renderer") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(oliverURL != nil ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(oliverURL != nil ? "Available" : "Not Found")
                            .fontWeight(.medium)
                    }
                }

                if let oliverPath = oliverURL?.path {
                    LabeledContent("Binary Path") {
                        Text(oliverPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }

                LabeledContent("Custom Binary") {
                    HStack(spacing: 8) {
                        Button("Choose Custom Oliver…") {
                            chooseBinary(prompt: "Select Oliver executable") { path in
                                customOliverPath = path
                                refreshTrigger = UUID()
                            }
                        }
                        if !customOliverPath.isEmpty {
                            Button("Reset to Default") {
                                customOliverPath = ""
                                refreshTrigger = UUID()
                            }
                        }
                    }
                }
            } header: {
                Text("Oliver Markup Engine")
            }

            Section {
                LabeledContent("Boris Editor") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(editorURL != nil ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(editorURL != nil ? "Available" : "Not Found")
                            .fontWeight(.medium)
                    }
                }

                if let edPath = editorURL?.path {
                    LabeledContent("Binary Path") {
                        Text(edPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }

                LabeledContent("Custom Binary") {
                    HStack(spacing: 8) {
                        Button("Choose Custom Editor…") {
                            chooseBinary(prompt: "Select boris-editor executable") { path in
                                customEditorPath = path
                                refreshTrigger = UUID()
                            }
                        }
                        if !customEditorPath.isEmpty {
                            Button("Reset to Default") {
                                customEditorPath = ""
                                refreshTrigger = UUID()
                            }
                        }
                    }
                }
            } header: {
                Text("Boris Editor Host")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Solipsist searches for binaries in the following order:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        searchStep(
                            index: "1",
                            title: "Settings Custom Preference",
                            detail: "User-selected path saved in Preferences"
                        )
                        searchStep(
                            index: "2",
                            title: "Environment Variables",
                            detail: "SOLIPSIST_BORIS_BIN / SOLIPSIST_OLIVER_BIN / SOLIPSIST_BORIS_EDITOR_BIN"
                        )
                        searchStep(
                            index: "3",
                            title: "App Bundle (Embedded)",
                            detail: "Solipsist.app/Contents/Resources/…"
                        )
                        searchStep(
                            index: "4",
                            title: "Sibling Repository / Kits",
                            detail: "SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/… or ../boris/zig-out/bin/…"
                        )
                    }
                    .padding(.top, 2)
                }
            } header: {
                Text("Binary Discovery & Sourcing")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseBinary(prompt: String, onSelect: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = prompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if panel.runModal() == .OK, let url = panel.url {
            onSelect(url.path)
        }
    }

    private func searchStep(index: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(index).")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func originDescription(for path: String) -> String {
        if !customBorisPath.isEmpty, path == customBorisPath {
            return "User-selected custom binary"
        } else if path.contains(".app/Contents/Resources") {
            return "Embedded in Solipsist.app bundle"
        } else if let env = ProcessInfo.processInfo.environment["SOLIPSIST_BORIS_BIN"], !env.isEmpty, path == env {
            return "Custom override via SOLIPSIST_BORIS_BIN"
        } else if path.contains("SUPPORT-NOT-FOR-GITHUB") {
            return "Local agent transport kit"
        } else if path.contains("zig-out") {
            return "Local Zig build checkout"
        } else {
            return "Local file system"
        }
    }
}
