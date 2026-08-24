import SwiftUI

/// The front-matter form (LATER-3.3): edits the closed key set
/// (`boris-frontmatter-1.schema.json`) and overlays it back onto the
/// buffer on Apply. Boundary 4 holds — Apply touches only the buffer;
/// the explicit Save / ⌘S is the only disk writer. Unknown keys in the
/// payload are preserved (never destroyed by the form).
///
/// #266: every field carries a human label plus a tooltip naming its
/// schema key, Apply is named for what it does ("Apply to Source"), and a
/// page without front matter gets an empty state that can add one.
struct ComposeFrontmatterForm: View {
    @Bindable var document: ComposeDocument

    @State private var fields = ComposeFrontmatter.Fields()
    @State private var fence = "---"
    /// Payload the form was last synced from, so editor-side edits refresh
    /// the form but Apply's own write-back does not clobber it.
    @State private var appliedPayload: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if document.frontmatter != nil {
                Divider()
                editorForm
            } else {
                emptyState
            }
        }
        .frame(minWidth: 230, idealWidth: 260)
        .task(id: document.fileURL) {
            syncFromBuffer()
        }
        .onChange(of: document.text) { _, _ in
            syncFromBuffer()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label("Front Matter", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Button("Apply to Source") { apply() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(document.frontmatter == nil && fields == .empty)
                    .help("Overlay these fields onto the buffer's front matter")
            }
            // Boundary 4 made legible (#266): Apply edits the buffer; disk
            // waits for the explicit save.
            Text("Edits the buffer only — Save (⌘S) writes the file.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    // MARK: - Empty state (#266)

    private var emptyState: some View {
        VStack(spacing: 10) {
            Label("No Front Matter", systemImage: "doc.plaintext")
                .font(.headline)
            Text(
                "This page starts straight in with its body. Add a front-matter "
                    + "block to set metadata like ID, status, or tags."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button("Add Front Matter") {
                addFrontMatter()
            }
            .controlSize(.small)
            .help("Insert a starter front-matter block at the top of the buffer")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Form

    private var editorForm: some View {
        Form {
            Section("Identity") {
                labeledRow("Page ID", help: "`id` — stable identifier used by links and the graph.") {
                    TextField("page-id", text: $fields.id)
                }
                labeledRow("Title", help: "`title` — the page title shown in mailboxes and the graph.") {
                    TextField("Title", text: $fields.title)
                }
                labeledRow("Appears under", help: "`parent` — the page this one appears under (its parent trunk).") {
                    TextField("parent-page", text: $fields.parent)
                }
                labeledRow("Status", help: "`status` — draft, published, or archived.") {
                    Picker("Status", selection: $fields.status) {
                        Text("—").tag("")
                        Text("Draft").tag("draft")
                        Text("Published").tag("published")
                        Text("Archived").tag("archived")
                    }
                }
            }
            Section("Publication") {
                labeledRow("Publish date", help: "`published_at` — when the page goes live (e.g. 2026-08-19).") {
                    TextField("2026-08-19", text: $fields.publishedAt)
                }
                labeledRow("Summary", help: "`summary` — short summary for listings.") {
                    TextField("Summary", text: $fields.summary)
                }
                labeledRow("Servings", help: "`servings` — recipe yield (Cooklang recipes only).") {
                    TextField("Servings", text: $fields.servings)
                }
            }
            Section("Tags") {
                labeledRow("Tags", help: "`tags` — comma-separated list.") {
                    TextField("Comma-separated", text: tagsText)
                }
            }
            Section("Relations") {
                ForEach(Array($fields.relations.enumerated()), id: \.offset) { _, $relation in
                    HStack(spacing: 6) {
                        TextField("Relationship type", text: $relation.kind)
                            .frame(minWidth: 70)
                        TextField("Links to", text: $relation.target)
                    }
                    .help("`relations` entry — `kind` / `target` pair linking a related page.")
                }
                Button("Add Relation") {
                    fields.relations.append(ComposeFrontmatter.Relation(kind: "", target: ""))
                }
            }
        }
        .formStyle(.grouped)
        .font(.callout)
    }

    /// Visible label + control + schema-faithful tooltip (#266).
    private func labeledRow(
        _ label: String,
        help: String,
        @ViewBuilder control: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
            control()
        }
        .help(help)
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

    // MARK: - Sync / apply

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

    /// #266: inserts a starter block through the existing apply path. A
    /// draft status seeds the payload so the block is never empty.
    private func addFrontMatter() {
        if fields == .empty {
            fields = ComposeFrontmatter.Fields(status: "draft")
        }
        apply()
    }
}
