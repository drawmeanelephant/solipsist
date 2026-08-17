import SwiftUI

/// About window showing Solipsist application info and bundled engine details.
struct AboutWindow: View {
    @Environment(AppRuntime.self) private var runtime

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.hexagongrid.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.primary)

            VStack(spacing: 4) {
                Text("Solipsist")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Version \(versionString) (\(buildString))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Boris Engine")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                if let enginePath = runtime.enginePath {
                    Text(enginePath)
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                } else {
                    Text("No engine binary located.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)

            Spacer(minLength: 0)

            Text(copyrightString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 380, height: 260)
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var buildString: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var copyrightString: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "© 2026 draw me an elephant"
    }
}
