import AppKit
import SwiftUI

/// Native About window displaying app metadata, bundle version, and Boris engine runtime details.
struct AboutWindow: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title2.bold())

                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Deterministic graph-native publication workstation.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Divider()
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text("Boris Engine:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 85, alignment: .trailing)

                    if let path = runtime.enginePath {
                        Text(path)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    } else {
                        Text(runtime.engineError ?? "Not located")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            Text(copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 20)
        .frame(minWidth: 380, maxWidth: 460, minHeight: 260, maxHeight: 320)
        .navigationTitle("About Solipsist")
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Solipsist"
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 draw me an elephant"
    }
}
