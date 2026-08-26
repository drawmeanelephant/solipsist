import Foundation
import FoundationModels

/// The on-device drafting engine. One job: topic → structured post draft.
///
/// Boundaries honored here:
/// - The model writes *content*, never Boris semantics. It returns a
///   closed-schema frontmatter candidate plus markdown; assembly and any
///   write stay in `StagedPostDraft` / compose's explicit save.
/// - Unavailability is surfaced, never swallowed (boundary 3): every
///   failure mode is a typed error the caller shows.
enum PostDraftEngine {
    /// Mirror of `SystemLanguageModel.Availability.UnavailableReason` so
    /// callers (and tests) can read a reason without touching the model.
    enum Unavailability: Equatable, Sendable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        /// Future/unknown reasons from a newer OS.
        case modelUnavailable

        var message: String {
            switch self {
            case .deviceNotEligible:
                return "This Mac doesn’t support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is off. Turn it on in System Settings to draft posts."
            case .modelNotReady:
                return "The on-device model isn’t ready yet. Try again shortly."
            case .modelUnavailable:
                return "Apple Intelligence isn’t available right now."
            }
        }
    }

    enum EngineError: LocalizedError, Equatable {
        case unavailable(Unavailability)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason):
                return reason.message
            case .emptyResponse:
                return "The model returned an empty draft. Try rephrasing the topic."
            }
        }

        static func from(_ availability: SystemLanguageModel.Availability) -> EngineError? {
            switch availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return .unavailable(.deviceNotEligible)
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(.appleIntelligenceNotEnabled)
            case .unavailable(.modelNotReady):
                return .unavailable(.modelNotReady)
            case .unavailable:
                // A reason this OS build doesn't name yet — still surfaced.
                return .unavailable(.modelUnavailable)
            }
        }
    }

    /// The guided-generation schema. Field guides keep the model inside
    /// the shapes compose can actually use: short title, 1–5 tags, body
    /// that is markdown paragraphs (no frontmatter — we emit that).
    @Generable
    struct GeneratedDraft {
        @Guide(description: "A headline for the post, at most ten words.")
        var title: String
        @Guide(description: "One-sentence summary of what the post says.")
        var summary: String
        @Guide(description: "Between one and five lowercase topical tags.")
        var tags: [String]
        @Guide(description: "The post body in Markdown: short paragraphs, optional headings and lists. No YAML frontmatter.")
        var body: String
    }

    static func instructions(origin: StagedPostDraft.Origin) -> String {
        let voiceNote = origin == .siri
            ? " The topic may have been dictated by voice: clean up filler without changing meaning."
            : ""
        return """
        You draft posts for a personal publication compiled by Boris. \
        The author gives a topic; return a headline, a one-sentence \
        summary, 1–5 lowercase topical tags, and a Markdown body of short \
        paragraphs. Never include YAML frontmatter in the body.\(voiceNote)
        """
    }

    static func prompt(topic: String) -> String {
        """
        Draft a post about: \(topic)
        """
    }

    /// Topic → staged draft. Throws typed errors; never returns partials.
    static func draft(topic: String, origin: StagedPostDraft.Origin) async throws -> StagedPostDraft {
        if let unavailable = EngineError.from(SystemLanguageModel.default.availability) {
            throw unavailable
        }
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: instructions(origin: origin)
        )
        let response = try await session.respond(
            to: prompt(topic: topic),
            generating: GeneratedDraft.self
        )
        let generated = response.content
        let staged = StagedPostDraft(
            title: generated.title,
            summary: generated.summary,
            tags: generated.tags,
            body: generated.body,
            origin: origin
        )
        guard !staged.title.isEmpty || !staged.body.isEmpty else {
            throw EngineError.emptyResponse
        }
        return staged
    }
}
