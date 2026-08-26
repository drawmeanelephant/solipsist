import FoundationModels
import XCTest

/// M18 — Siri drafts: shaping, handoff, and unavailability mapping.
/// The model call itself is not unit-testable headless; everything the
/// model's output flows through is.
final class PostDraftTests: XCTestCase {
    // MARK: - Slug

    func testSlugLowercasesAndDashes() {
        XCTAssertEqual(PostDraftAssembly.slug("My Post Title"), "my-post-title")
        XCTAssertEqual(PostDraftAssembly.slug("  Spaced   Out  "), "spaced-out")
    }

    func testSlugDropsPunctuationButKeepsUnicodeLetters() {
        XCTAssertEqual(PostDraftAssembly.slug("Hello, World! (Again)"), "hello-world-again")
        XCTAssertEqual(PostDraftAssembly.slug("Über-Cool Æther"), "über-cool-æther")
    }

    func testSlugFallsBackToUntitled() {
        XCTAssertEqual(PostDraftAssembly.slug(""), "untitled")
        XCTAssertEqual(PostDraftAssembly.slug("!!! ???"), "untitled")
    }

    func testSlugIsCapped() {
        let long = String(repeating: "word ", count: 40)
        XCTAssertLessThanOrEqual(PostDraftAssembly.slug(long).count, 80)
    }

    // MARK: - Assembly

    private var sample = StagedPostDraft(
        title: "Field Notes",
        summary: "What the trip taught me.",
        tags: ["travel", "notes"],
        body: "First paragraph.\n\nSecond paragraph.",
        origin: .siri
    )

    @MainActor
    func testAssembledMarkdownCarriesClosedKeysOnly() throws {
        let text = PostDraftAssembly.markdown(for: sample)
        XCTAssertTrue(text.hasPrefix("---\n"))
        XCTAssertTrue(text.contains("title: Field Notes"))
        XCTAssertTrue(text.contains("summary: What the trip taught me."))
        XCTAssertTrue(text.contains("tags:\n  - travel\n  - notes"))

        // No invented keys: id / parent / status stay absent.
        let payload = try XCTUnwrap(ComposeDocument(text: text).frontmatter).payloadString
        for key in ["id:", "parent:", "status:", "published_at:", "servings:", "relations:"] {
            XCTAssertFalse(payload.contains(key), "assembly must not emit \(key)")
        }
    }

    @MainActor
    func testAssembledFrontmatterParsesBackThroughTheCanonicalReader() throws {
        let text = PostDraftAssembly.markdown(for: sample)
        let frontmatter = try XCTUnwrap(ComposeDocument(text: text).frontmatter)
        let fields = ComposeFrontmatter.parse(payload: frontmatter.payloadString)
        XCTAssertEqual(fields.title, "Field Notes")
        XCTAssertEqual(fields.summary, "What the trip taught me.")
        XCTAssertEqual(fields.tags, ["travel", "notes"])
        XCTAssertEqual(frontmatter.kind, .yaml)
    }

    func testBodySurvivesAfterFrontmatter() {
        let text = PostDraftAssembly.markdown(for: sample)
        XCTAssertTrue(text.hasSuffix("First paragraph.\n\nSecond paragraph.\n"))
    }

    func testEmptyMetadataYieldsBareBody() {
        let bare = StagedPostDraft(title: "", summary: "", tags: [], body: "Just words.", origin: .menu)
        XCTAssertEqual(PostDraftAssembly.markdown(for: bare), "Just words.")
    }

    func testStagedDraftTrimsMetadata() {
        let draft = StagedPostDraft(
            title: "  T  ", summary: "\n s \n", tags: [" a ", "", "b"],
            body: "b", origin: .menu
        )
        XCTAssertEqual(draft.title, "T")
        XCTAssertEqual(draft.summary, "s")
        XCTAssertEqual(draft.tags, ["a", "b"])
    }

    // MARK: - Save-panel naming

    @MainActor
    func testSuggestedFileNameSlugsTheDraftTitle() {
        XCTAssertEqual(
            ComposeStagedDraft.suggestedFileName(
                frontmatterPayload: "title: Field Notes\nsummary: s\ntags:\n  - travel"
            ),
            "field-notes.md"
        )
        XCTAssertEqual(
            ComposeStagedDraft.suggestedFileName(frontmatterPayload: ""),
            "untitled.md"
        )
    }

    // MARK: - Router handoff

    @MainActor
    func testRouterQueuesUntilConsumerRegisters() {
        let router = DraftRouter()
        let staged = sample
        router.deliver(staged)
        var received: [StagedPostDraft] = []
        router.register { received.append($0) }
        XCTAssertEqual(received, [staged])

        router.deliver(sample)
        XCTAssertEqual(received, [staged, sample])
        router.reset()
    }

    @MainActor
    func testRouterDeliversInOrderWhenRegistered() {
        let router = DraftRouter()
        var received: [StagedPostDraft] = []
        router.register { received.append($0) }
        router.deliver(sample)
        router.deliver(StagedPostDraft(title: "x", body: "y", origin: .menu))
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.first?.origin, .siri)
        XCTAssertEqual(received.last?.origin, .menu)
        router.reset()
    }

    // MARK: - Unavailability mapping

    func testAvailabilityMappingSurfacesEveryReason() {
        XCTAssertNil(PostDraftEngine.EngineError.from(.available))
        XCTAssertEqual(
            PostDraftEngine.EngineError.from(.unavailable(.deviceNotEligible)),
            .unavailable(.deviceNotEligible)
        )
        XCTAssertEqual(
            PostDraftEngine.EngineError.from(.unavailable(.appleIntelligenceNotEnabled)),
            .unavailable(.appleIntelligenceNotEnabled)
        )
        XCTAssertEqual(
            PostDraftEngine.EngineError.from(.unavailable(.modelNotReady)),
            .unavailable(.modelNotReady)
        )
        // Every error carries human-readable copy — never swallowed.
        for reason in [
            PostDraftEngine.Unavailability.deviceNotEligible,
            .appleIntelligenceNotEnabled,
            .modelNotReady,
        ] {
            XCTAssertFalse(reason.message.isEmpty)
        }
    }
}
