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
            TextField("Title", text: $fields.siteTitle)
            TextField("URL", text: $fields.siteURL)
            TextField("Input", text: $fields.input)
            Picker("Input format", selection: $fields.inputFormat) {
                ForEach(InspectorProfile.inputFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
            Picker("Publication target", selection: $fields.publicationTarget) {
                if loaded.publicationTarget.isEmpty {
                    Text("None").tag("")
                }
                ForEach(InspectorProfile.publicationTargets, id: \.self) { target in
                    Text(Self.label(forTarget: target)).tag(target)
                }
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
