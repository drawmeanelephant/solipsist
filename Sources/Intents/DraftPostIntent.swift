import AppIntents
import AppKit
import CoreLocation
import Foundation

/// Siri / Shortcuts / Spotlight: “Create an entry in Solipsist …”.
///
/// Adopts the journal-domain `createEntry` schema so Apple Intelligence
/// routes entry-creation requests here. Foreground-only: the staged
/// draft must be visible for review before anything reaches disk.
///
/// Semantics against the schema contract:
/// - `message` is the *topic seed*, expanded by the on-device model;
///   dictated filler is cleaned up without changing meaning.
/// - `title`, when spoken, wins over the model-generated headline.
/// - `entryDate` / `location` / `mediaItems` are accepted because the
///   schema names them; staging is text-only, so they are not consumed
///   (files would need an explicit save path — boundary 4).
///
/// The model writes *content*, never Boris semantics; nothing touches
/// the content tree until the author saves in Compose.
@AppIntent(schema: .journal.createEntry)
struct DraftPostIntent: AppIntent {
    static let title: LocalizedStringResource = "Draft Post"
    static let description = IntentDescription(
        "Drafts a post with Apple Intelligence and opens it in Solipsist’s compose window."
    )
    static var supportedModes: IntentModes { [.foreground] }

    /// Named `message`: that is what the schema expects for entry text.
    @Parameter(
        title: "Topic",
        requestValueDialog: "What should the post be about?"
    )
    var message: AttributedString

    @Parameter(title: "Title")
    var title: String?

    @Parameter(title: "Entry Date")
    var entryDate: Date?

    @Parameter(title: "Location")
    var location: CLPlacemark?

    @Parameter(title: "Media Items", default: [])
    var mediaItems: [IntentFile]

    @MainActor
    func perform() async throws -> some ReturnsValue<StagedDraftEntity> & ProvidesDialog {
        let topic = String(message.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else {
            return .result(
                value: StagedDraftEntity(topic: message, title: ""),
                dialog: "Give me a topic and I’ll draft the post."
            )
        }
        var draft = try await PostDraftEngine.draft(topic: topic, origin: .siri)
        if let spoken = title?.trimmingCharacters(in: .whitespacesAndNewlines), !spoken.isEmpty {
            draft.title = spoken
        }
        DraftRouter.shared.deliver(draft)
        NSApp.activate(ignoringOtherApps: true)
        return .result(
            value: StagedDraftEntity(topic: message, title: draft.title),
            dialog: "Draft “\(draft.title)” is waiting in Compose for your save."
        )
    }

    /// The File-menu path performs the same action by hand; donating it
    /// teaches suggestions. Donation failures are advisory by nature and
    /// must not spam alerts over the staged-draft success dialog.
    @MainActor
    func donateQuietly() {
        Task {
            _ = try? donate()
        }
    }
}

/// Lightweight stand-in for the schema’s journal entry: the staged
/// draft while it waits in Compose. Carries the schema’s expected
/// properties so the metadata export can verify the shape; only the
/// text fields are ever populated. Drafts are transient by design
/// (memory-only until an explicit save), so the query resolves nothing
/// after the fact — there is no addressable store to lie about.
@AppEntity(schema: .journal.entry)
struct StagedDraftEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Draft")
    static let defaultQuery = StagedDraftQuery()

    var id: UUID
    var message: AttributedString?
    var title: String?
    var entryDate: Date?
    var location: CLPlacemark?
    var mediaItems: [IntentFile]

    init(topic: AttributedString, title: String) {
        self.id = UUID()
        self.message = topic
        self.title = title.isEmpty ? nil : title
        self.entryDate = nil
        self.location = nil
        self.mediaItems = []
    }

    var displayRepresentation: DisplayRepresentation {
        let name = title ?? "Untitled draft"
        return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct StagedDraftQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [StagedDraftEntity] {
        []
    }
}

struct SolipsistShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DraftPostIntent(),
            phrases: [
                "Draft a post in \(.applicationName)",
                "Draft a post with \(.applicationName)",
                "\(.applicationName) draft post",
                "Create an entry in \(.applicationName)",
            ],
            shortTitle: "Draft Post",
            systemImageName: "square.and.pencil"
        )
    }
}
