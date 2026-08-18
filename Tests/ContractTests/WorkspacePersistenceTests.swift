import XCTest

final class WorkspacePersistenceTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("solipsist-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
        scratch = nil
    }

    func testLocalSourceRoundTripKeepsBookmarkAndDropsAvailability() throws {
        let source = try LocalSource.make(from: scratch)
        XCTAssertTrue(source.isAvailable)

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(LocalSource.self, from: encoded)

        XCTAssertEqual(decoded.id, source.id)
        XCTAssertEqual(decoded.title, source.title)
        XCTAssertEqual(decoded.displayPath, source.displayPath)
        XCTAssertEqual(decoded.bookmarkData, source.bookmarkData)
        XCTAssertTrue(decoded.isAvailable, "availability is transient and defaults true")

        let resolved = try decoded.resolve()
        XCTAssertEqual(
            resolved.url.standardizedFileURL.path,
            scratch.standardizedFileURL.path
        )
    }

    func testPersistedWorkspaceRoundTripViaDefaults() throws {
        let source = try LocalSource.make(from: scratch)
        let payload = PersistedWorkspace(sources: [source], selected: source.id)
        let suiteName = "solipsist.workspace.test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("suite defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(try WorkspacePersistence.encode(payload), forKey: WorkspacePersistence.defaultsKey)
        guard let data = defaults.data(forKey: WorkspacePersistence.defaultsKey) else {
            return XCTFail("missing payload")
        }
        let decoded = try WorkspacePersistence.decode(data)
        XCTAssertEqual(decoded.selected, source.id)
        XCTAssertNil(decoded.mailbox)
        XCTAssertEqual(decoded.sources.count, 1)
        XCTAssertEqual(decoded.sources[0].id, source.id)
        XCTAssertEqual(decoded.sources[0].bookmarkData, source.bookmarkData)
    }

    func testV1PayloadWithoutMailboxDecodesNil() throws {
        let source = try LocalSource.make(from: scratch)
        let encodedSource = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(source)
        )
        let encodedSelected = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(source.id)
        )
        let legacyPayload: [String: Any] = [
            "sources": [encodedSource],
            "selected": encodedSelected,
        ]
        let decoded = try WorkspacePersistence.decode(
            try JSONSerialization.data(withJSONObject: legacyPayload)
        )
        XCTAssertNil(decoded.mailbox)
        XCTAssertEqual(decoded.selected, source.id)
        XCTAssertEqual(decoded.sources.count, 1)
        XCTAssertEqual(decoded.sources[0].id, source.id)
    }

    func testMailboxActivitySurvivesRoundTrip() throws {
        let source = try LocalSource.make(from: scratch)
        let payload = PersistedWorkspace(
            sources: [source],
            selected: source.id,
            mailbox: WorkspaceMailbox.activity
        )
        let decoded = try WorkspacePersistence.decode(try WorkspacePersistence.encode(payload))
        XCTAssertEqual(decoded.mailbox, WorkspaceMailbox.activity)
        XCTAssertEqual(decoded.selected, source.id)
    }

    func testUnknownMailboxIsNotRewrittenToPages() throws {
        let source = try LocalSource.make(from: scratch)
        for raw in ["trunk:guides", "guides/overview"] {
            let payload = PersistedWorkspace(
                sources: [source],
                selected: source.id,
                mailbox: raw
            )
            let decoded = try WorkspacePersistence.decode(try WorkspacePersistence.encode(payload))
            XCTAssertEqual(decoded.mailbox, raw)
            XCTAssertNotEqual(decoded.mailbox, WorkspaceMailbox.pages)
        }
    }

    func testForwardCompatibleLegacyShapeIgnoresMailbox() throws {
        struct LegacyPersistedWorkspace: Codable {
            var sources: [LocalSource]
            var selected: SourceID?
        }

        let source = try LocalSource.make(from: scratch)
        let payload = PersistedWorkspace(
            sources: [source],
            selected: source.id,
            mailbox: WorkspaceMailbox.outputs
        )
        let decoded = try JSONDecoder().decode(
            LegacyPersistedWorkspace.self,
            from: try WorkspacePersistence.encode(payload)
        )
        XCTAssertEqual(decoded.selected, source.id)
        XCTAssertEqual(decoded.sources.count, 1)
        XCTAssertEqual(decoded.sources[0].id, source.id)
    }

    func testDeletedFolderFailsResolve() throws {
        let folder = scratch.appendingPathComponent("gone", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = try LocalSource.make(from: folder)
        _ = try source.resolve()

        try FileManager.default.removeItem(at: folder)
        XCTAssertThrowsError(try source.resolve())
    }

    func testRelocatedFolderKeepsIdentity() throws {
        let original = try LocalSource.make(from: scratch)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("solipsist-relocated-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        var relocated = try LocalSource.make(from: destination)
        relocated.id = original.id
        XCTAssertEqual(relocated.id, original.id)
        XCTAssertNotEqual(relocated.bookmarkData, original.bookmarkData)
        XCTAssertEqual(
            try relocated.resolve().url.standardizedFileURL.path,
            destination.standardizedFileURL.path
        )
    }

    func testRefreshedBookmarkPreservesIdentity() throws {
        let source = try LocalSource.make(from: scratch)
        let refreshed = try source.refreshedBookmark()
        XCTAssertEqual(refreshed.id, source.id)
        XCTAssertEqual(
            try refreshed.resolve().url.standardizedFileURL.path,
            scratch.standardizedFileURL.path
        )
    }
}
