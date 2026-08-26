import SwiftUI

/// Settings pane displaying the Boris compiler, Oliver renderer, and
/// boris-editor host status: resolved paths, detected versions, origin,
/// and search-order guidance (#292). There are no binary pickers — under
/// App Sandbox only the embedded engines can execute; developers override
/// via `SOLIPSIST_BORIS_BIN` / `SOLIPSIST_OLIVER_BIN` /
/// `SOLIPSIST_BORIS_EDITOR_BIN`.
struct EngineSettingsPane: View {
    @Environment(AppRuntime.self) private var runtime

    private var borisURL: URL? {
        runtime.enginePath.map(URL.init(fileURLWithPath:)) ?? BorisBinary.locate()
    }

    private var oliverURL: URL? {
        OliverBinary.locate(borisBinary: borisURL)
    }

    private var editorURL: URL? {
        borisURL.flatMap { EditorServerFactory.findEditorBinary(relativeTo: $0) }
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
                            title: "Environment Variables",
                            detail: "SOLIPSIST_BORIS_BIN / SOLIPSIST_OLIVER_BIN / SOLIPSIST_BORIS_EDITOR_BIN"
                        )
                        searchStep(
                            index: "2",
                            title: "App Bundle (Embedded)",
                            detail: "Solipsist.app/Contents/Resources/…"
                        )
                        searchStep(
                            index: "3",
                            title: "Sibling Repository / Kits",
                            detail: "SUPPORT-NOT-FOR-GITHUB/boris-agent-kit/… or ../boris/zig-out/bin/…"
                        )
                    }
                    .padding(.top, 2)

                    Text("App Sandbox can only execute binaries inside our own bundle, so there is no user-selected engine setting. Developer overrides use the environment variables above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Binary Discovery & Sourcing")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        if path.contains(".app/Contents/Resources") {
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
