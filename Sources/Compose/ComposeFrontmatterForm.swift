import SwiftUI

/// The front-matter form (LATER-3.3): edits the closed key set
/// (`boris-frontmatter-1.schema.json`) and overlays it back onto the
/// buffer on Apply. Boundary 4 holds — Apply touches only the buffer;
/// the explicit Save / ⌘S is the only disk writer. Unknown keys in the
/// payload are preserved (never destroyed by the form).
struct ComposeFrontmatterForm: View {
    @Bindable var document: ComposeDocument

    @State private var fields = ComposeFrontmatter.Fields()
    @State private var fence = "---"
    /// Payload the form was last synced from, so editor-side edits refresh
    /// the form but Apply's own write-back does not clobber it.
    @State private var appliedPayload: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Front Matter", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Button("Apply") { apply() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Overlay these fields onto the buffer's front matter")
            }
            .padding(10)
            Divider()
            Form {
                Section("Identity") {
                    TextField("ID", text: $fields.id)
                    TextField("Title", text: $fields.title)
                    TextField("Parent", text: $fields.parent)
                    Picker("Status", selection: $fields.status) {
                        Text("—").tag("")
                        Text("Draft").tag("draft")
                        Text("Published").tag("published")
                        Text("Archived").tag("archived")
                    }
                }
                Section("Publication") {
                    TextField("Published At", text: $fields.publishedAt)
                    TextField("Summary", text: $fields.summary)
                    TextField("Servings", text: $fields.servings)
                }
                Section("Tags") {
                    TextField("Comma-separated", text: tagsText)
                }
                Section("Relations") {
                    ForEach(Array($fields.relations.enumerated()), id: \.offset) { _, $relation in
                        HStack(spacing: 6) {
                            TextField("kind", text: $relation.kind)
                                .frame(minWidth: 70)
                            TextField("target", text: $relation.target)
                        }
                    }
                    Button("Add Relation") {
                        fields.relations.append(ComposeFrontmatter.Relation(kind: "", target: ""))
                    }
                }
            }
            .formStyle(.grouped)
            .font(.callout)
        }
        .frame(minWidth: 230, idealWidth: 260)
        .task(id: document.fileURL) {
            syncFromBuffer()
        }
        .onChange(of: document.text) { _, _ in
            syncFromBuffer()
        }
    }

    private var tagsText: Binding<String> {
        Binding(
            get: { fields.tags.joined(separator: ", ") },
            set: { newValue in
                fields.tags = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func syncFromBuffer() {
        if let frontmatter = document.frontmatter {
            let payload = frontmatter.payloadString
            guard payload != appliedPayload else { return }
            fields = ComposeFrontmatter.parse(payload: payload)
            fence = frontmatter.kind == .toml ? "+++" : "---"
            appliedPayload = payload
        } else if appliedPayload != nil {
            // The buffer lost its front matter (or never had any on first load).
            fields = ComposeFrontmatter.Fields()
            fence = "---"
            appliedPayload = nil
        }
    }

    private func apply() {
        let current = document.frontmatter?.payloadString ?? ""
        let newPayload = ComposeFrontmatter.apply(fields, to: current)
        if document.frontmatter == nil, newPayload.isEmpty {
            return // nothing to create
        }
        let newBlock = "\(fence)\n\(newPayload)\n\(fence)\n"
        if let frontmatter = document.frontmatter {
            document.text.replaceSubrange(frontmatter.range, with: newBlock)
        } else {
            document.text = newBlock + document.text
        }
        appliedPayload = newPayload
    }
}
