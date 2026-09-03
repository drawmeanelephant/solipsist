import SwiftUI

/// Form over `boris.json`. Every control maps 1:1 to a profile key; Save
/// writes the file. Execution knobs do not live here.
struct ProfileSection: View {
    let source: LocalSource

    @State private var fields = InspectorProfileFields.empty
    @State private var loaded = InspectorProfileFields.empty
    @State private var originalData: Data?
    @State private var status: Status = .idle
    @State private var note: String?
    @State private var availableThemes: [String] = []
    /// #298: the target row whose theme browser sheet is open.
    @State private var browsingTheme: BrowsableTargetTheme?

    /// Identifiable wrapper for the sheet(item:) binding — the target
    /// row index whose theme the browser writes.
    private struct BrowsableTargetTheme: Identifiable {
        let index: Int
        var id: Int { index }
    }

    var body: some View {
        Group {
            switch status {
            case .idle:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .unavailable:
                quiet("This folder is no longer reachable.")
            case .missing:
                quiet("No publication profile (boris.json) in this folder.")
            case .invalid:
                quiet(note ?? "boris.json is not a JSON object.")
            case .ready:
                form
            }
        }
        .task(id: source.id.raw) {
            reload()
        }
    }

    private var form: some View {
        Group {
            Section("Site") {
                TextField("Title", text: $fields.siteTitle)
                TextField("URL", text: $fields.siteURL)
                TextField("Description", text: $fields.siteDescription)
                TextField("Input", text: $fields.input)
                Picker("Input format", selection: $fields.inputFormat) {
                    ForEach(InspectorProfile.inputFormats, id: \.self) { format in
                        Text(format).tag(format)
                    }
                }
            }

            Section("Publication") {
                Picker("Target", selection: $fields.publicationTarget) {
                    if loaded.publicationTarget.isEmpty {
                        Text("None").tag("")
                    }
                    ForEach(InspectorProfile.publicationTargets, id: \.self) { target in
                        Text(Self.label(forTarget: target)).tag(target)
                    }
                }
                if !fields.publicationTarget.isEmpty {
                    TextField("Base URL", text: $fields.publicationBaseURL)
                    TextField("Origin", text: $fields.publicationOrigin)
                    TextField("Base Path", text: $fields.publicationBasePath)
                    if fields.publicationTarget == "standard-site" {
                        TextField("DID", text: $fields.publicationDid)
                        TextField("PDS", text: $fields.publicationPds)
                    }
                }
            }

            Section("HTML Targets") {
                ForEach($fields.targets.indices, id: \.self) { index in
                    targetRow(index: index)
                }
                Button("Add Target") {
                    let nextIndex = fields.targets.count + 1
                    fields.targets.append(
                        PublicationTarget(name: "target-\(nextIndex)", output: "dist/target-\(nextIndex)", public: true)
                    )
                }
                .controlSize(.small)
            }

            Section("Editions") {
                editionsForm
            }

            HStack {
                Button("Save") { save() }
                    .disabled(!isDirty)
                if let note {
                    Text(note)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .sheet(item: $browsingTheme) { browse in
            ThemeBrowserView(
                themes: availableThemes,
                selection: browse.index < fields.targets.count ? fields.targets[browse.index].theme : nil,
                workspaceRoot: try? source.resolve().url,
                onSelect: { theme in
                    guard browse.index < fields.targets.count else { return }
                    fields.targets[browse.index].theme = theme
                },
                onCancel: {}
            )
        }
    }

    @ViewBuilder
    private func targetRow(index: Int) -> some View {
        if index < fields.targets.count {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField("Name", text: $fields.targets[index].name)
                    Button {
                        fields.targets.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove target")
                }
                TextField("Output", text: $fields.targets[index].output)
                // #298: the theme control is a button opening the visual
                // browser (was: flat name Picker). Writes the same
                // `target.theme` string the Picker wrote; Save unchanged.
                Button {
                    browsingTheme = BrowsableTargetTheme(index: index)
                } label: {
                    HStack {
                        Text("Theme")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(fields.targets[index].theme ?? "Default")
                            .foregroundStyle(fields.targets[index].theme == nil ? .secondary : .primary)
                        Image(systemName: "paintpalette")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Browse themes visually")
                .accessibilityLabel("Theme: \(fields.targets[index].theme ?? "Default")")
                .accessibilityHint("Opens the theme browser")
                TextField("Layout", text: Binding(
                    get: { fields.targets[index].layout ?? "" },
                    set: { fields.targets[index].layout = $0.isEmpty ? nil : $0 }
                ))
                Toggle("Public", isOn: Binding(
                    get: { fields.targets[index].public ?? false },
                    set: { fields.targets[index].public = $0 }
                ))
            }
            .padding(.vertical, 2)
            Divider()
        }
    }

    private var editionsForm: some View {
        Group {
            // IR
            Toggle("IR Edition", isOn: Binding(
                get: { fields.editions.ir != nil },
                set: { enabled in
                    fields.editions.ir = enabled ? PublicationEdition(output: ".boris") : nil
                }
            ))
            if fields.editions.ir != nil {
                TextField("IR Output", text: Binding(
                    get: { fields.editions.ir?.output ?? "" },
                    set: { fields.editions.ir?.output = $0 }
                ))
            }

            // RAG
            Toggle("RAG Edition", isOn: Binding(
                get: { fields.editions.rag != nil },
                set: { enabled in
                    fields.editions.rag = enabled ? PublicationRagEdition(output: "rag") : nil
                }
            ))
            if fields.editions.rag != nil {
                TextField("RAG Output", text: Binding(
                    get: { fields.editions.rag?.output ?? "" },
                    set: { fields.editions.rag?.output = $0 }
                ))
                TextField("Scope", text: Binding(
                    get: { fields.editions.rag?.scope ?? "" },
                    set: { fields.editions.rag?.scope = $0.isEmpty ? nil : $0 }
                ))
            }

            // Context
            Toggle("Context Edition", isOn: Binding(
                get: { fields.editions.context != nil },
                set: { enabled in
                    fields.editions.context = enabled ? PublicationContextEdition(output: "context") : nil
                }
            ))
            if fields.editions.context != nil {
                TextField("Context Output", text: Binding(
                    get: { fields.editions.context?.output ?? "" },
                    set: { fields.editions.context?.output = $0 }
                ))
            }
        }
    }

    private var isDirty: Bool { fields != loaded }

    private func reload() {
        note = nil
        guard source.isAvailable else {
            status = .unavailable
            return
        }
        do {
            let root = try source.resolve().url
            availableThemes = ThemeCatalog.allThemes(for: root)
            guard let loaded = try InspectorProfile.load(from: root) else {
                status = .missing
                return
            }
            fields = loaded.fields
            self.loaded = loaded.fields
            originalData = loaded.data
            status = .ready
        } catch {
            status = .invalid
            note = String(describing: error)
        }
    }

    private func save() {
        guard let originalData else { return }
        do {
            let root = try source.resolve().url
            try InspectorProfile.save(to: root, original: originalData, fields: fields)
            if let reloaded = try InspectorProfile.load(from: root) {
                fields = reloaded.fields
                loaded = reloaded.fields
                self.originalData = reloaded.data
            } else {
                loaded = fields
            }
            note = "Saved"
        } catch {
            note = String(describing: error)
        }
    }

    private func quiet(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func label(forTarget target: String) -> String {
        switch target {
        case "github-pages": return "GitHub Pages"
        case "standard-site": return "Standard Site"
        default: return target
        }
    }

    private enum Status {
        case idle
        case unavailable
        case missing
        case invalid
        case ready
    }
}
