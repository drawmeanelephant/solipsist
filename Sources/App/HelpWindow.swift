import SwiftUI

/// In-app Help viewer rendering the bundled documentation guide.
struct HelpWindow: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(.init(helpContent))
                    .textSelection(.enabled)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 520, minHeight: 440)
        .navigationTitle("Solipsist Help")
    }

    private var helpContent: String {
        if let url = Bundle.main.url(forResource: "help", withExtension: "md"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        // Single source of truth is docs/help.md (bundled as a resource).
        // Keep this fallback to a stub so shortcuts/content never drift here.
        return """
        # Solipsist Help

        The bundled help guide is missing from this build.
        See `docs/help.md` in the repository for the full guide.
        """
    }
}
