import XCTest

@MainActor
final class GithubComposeBufferTests: XCTestCase {
    private let noun = WorkspaceNoun(kind: "page", id: "index", title: "Index", sourcePath: "index.md")

    private struct Fixture {
        let root: URL
        let local: LocalSource
        let github: GithubSource

        var fileURL: URL { root.appendingPathComponent("content/index.md") }
    }

    private func withFixture(_ test: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("github-compose-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("content"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".boris"), withIntermediateDirectories: true)
        try "{}".write(to: root.appendingPathComponent("boris.json"), atomically: true, encoding: .utf8)
        try "Original page".write(to: root.appendingPathComponent("content/index.md"), atomically: true, encoding: .utf8)
        let graph = """
        {"schemaVersion":"0.4.0","frozen":true,"nodes":[
        {"index":0,"id":"index","sourcePath":"index.md","role":"trunk","parent":null,
        "parentIndex":null,"title":"Index","status":null,"tags":[],"bodyOffset":null}
        ],"edges":[],"reverseIndex":[],"nav":[]}
        """
        try graph.write(to: root.appendingPathComponent(".boris/graph.json"), atomically: true, encoding: .utf8)
        let fixture = try Fixture(
            root: root, local: LocalSource.make(from: root),
            github: GithubSource.make(workingCopy: root, owner: "example", repository: "publication", defaultBranch: "main", grantedScopes: [])
        )
        try test(fixture)
    }

    private func request(_ source: SourceItem) -> ComposeBuffer.Request {
        ComposeBuffer.Request(
            source: source,
            selection: WorkspaceSelection(sourceID: source.id, mailbox: WorkspaceMailbox.pages, noun: noun)
        )
    }

    func testLocalAndGithubUseTheSameFolderContractAndContentRoot() throws {
        try withFixture { fixture in
            for item in [SourceItem.local(fixture.local), .github(fixture.github)] {
                let folder = item.folderSource
                let binding = try ComposeSourceBinding(source: folder)
                XCTAssertEqual(binding.source.id, item.id)
                XCTAssertEqual(binding.source.kind, item.kind)
                XCTAssertEqual(binding.contentRoot, binding.workspaceRoot.appendingPathComponent("content", isDirectory: true))
                XCTAssertEqual(try folder.artifactDirectory(named: ".boris"), binding.workspaceRoot.appendingPathComponent(".boris", isDirectory: true))
                XCTAssertEqual(folder.profileURL(), binding.workspaceRoot.appendingPathComponent("boris.json"))
            }
        }
    }

    func testGithubComposeLoadsAndSavesWithoutRemoteCredentialsOrWrites() throws {
        try withFixture { fixture in
            let buffer = ComposeBuffer()
            XCTAssertTrue(buffer.select(request(.github(fixture.github))))
            XCTAssertEqual(buffer.document.text, "Original page")
            XCTAssertEqual(buffer.page?.owner.source.kind, .github)
            buffer.document.text = "Explicit local save"
            var savedOwner: ComposeSourceBinding?
            let outcome = ComposeSaveFlow.run(
                beginTreeWrite: {}, endTreeWrite: {},
                noteSave: { savedOwner = buffer.page?.owner },
                save: { try buffer.document.save() }
            )
            XCTAssertEqual(outcome, .saved)
            XCTAssertEqual(savedOwner?.source.id, fixture.github.id)
            XCTAssertEqual(savedOwner?.source.kind, .github)
            XCTAssertEqual(savedOwner?.contentRoot, buffer.document.fileURL?.deletingLastPathComponent())
            XCTAssertEqual(try String(contentsOf: fixture.fileURL, encoding: .utf8), "Explicit local save")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(".git").path))
        }
    }

    func testEqualNounsAcrossLocalAndGithubKeepDistinctSourceIdentity() throws {
        try withFixture { fixture in
            let buffer = ComposeBuffer()
            XCTAssertTrue(buffer.select(request(.local(fixture.local))))
            buffer.document.text = "Dirty local buffer"
            XCTAssertFalse(buffer.select(request(.github(fixture.github))))
            XCTAssertEqual(buffer.pendingPage?.owner.source.id, fixture.github.id)
            buffer.cancelSwitch()
            XCTAssertEqual(buffer.page?.owner.source.id, fixture.local.id)
            XCTAssertEqual(buffer.document.text, "Dirty local buffer")
            buffer.select(request(.github(fixture.github)))
            XCTAssertTrue(buffer.discardAndSwitch())
            XCTAssertEqual(buffer.page?.owner.source.id, fixture.github.id)
            XCTAssertEqual(buffer.document.text, "Original page")
        }
    }

    func testUnavailableSourcesNeverReplaceTheBuffer() throws {
        try withFixture { fixture in
            let buffer = ComposeBuffer()
            buffer.select(request(.local(fixture.local)))
            buffer.document.text = "Keep this"
            var unavailable = fixture.github
            unavailable.isAvailable = false
            XCTAssertFalse(buffer.select(request(.github(unavailable))))
            XCTAssertTrue(buffer.loadError?.contains("unavailable or unreadable") == true)
            XCTAssertEqual(buffer.page?.owner.source.id, fixture.local.id)
            XCTAssertEqual(buffer.document.text, "Keep this")
            XCTAssertTrue(buffer.document.isDirty)
            XCTAssertNil(buffer.pendingPage)
        }
    }

    func testInvalidBookmarkFailsWithoutReplacingTheBuffer() throws {
        try withFixture { fixture in
            let buffer = ComposeBuffer()
            buffer.select(request(.local(fixture.local)))
            var invalid = fixture.github
            invalid.bookmarkData = Data([0, 1, 2])
            XCTAssertFalse(buffer.select(request(.github(invalid))))
            XCTAssertNotNil(buffer.loadError)
            XCTAssertEqual(buffer.page?.owner.source.id, fixture.local.id)
            XCTAssertEqual(buffer.document.text, "Original page")
        }
    }

    func testMissingWorkingFolderIsAnExplicitBindingFailure() throws {
        try withFixture { fixture in
            try FileManager.default.removeItem(at: fixture.root)
            XCTAssertThrowsError(try ComposeSourceBinding(source: fixture.github))
            XCTAssertThrowsError(try ComposeSourceBinding(source: fixture.local))
        }
    }

    func testUnreadablePageRetainsTheExistingBufferAndBinding() throws {
        try withFixture { fixture in
            let buffer = ComposeBuffer()
            buffer.select(request(.local(fixture.local)))
            buffer.document.text = "Keep this"
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fixture.fileURL.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.fileURL.path) }
            buffer.select(request(.github(fixture.github)))
            XCTAssertFalse(buffer.discardAndSwitch())
            XCTAssertNotNil(buffer.loadError)
            XCTAssertEqual(buffer.page?.owner.source.id, fixture.local.id)
            XCTAssertEqual(buffer.document.text, "Keep this")
            XCTAssertTrue(buffer.document.isDirty)
        }
    }

    func testGithubBindingSurvivesRemovalAndDoesNotMatchForeignWatchRoots() throws {
        try withFixture { fixture in
            let buffer = ComposeBuffer()
            buffer.select(request(.github(fixture.github)))
            buffer.document.text = "After source removal"
            buffer.select(nil)
            let owner = try XCTUnwrap(buffer.page?.owner)
            XCTAssertTrue(owner.isWatched(sourceID: fixture.github.id, contentRoot: owner.contentRoot))
            XCTAssertFalse(owner.isWatched(sourceID: fixture.local.id, contentRoot: owner.contentRoot))
            XCTAssertFalse(owner.isWatched(sourceID: fixture.github.id, contentRoot: owner.workspaceRoot))
            XCTAssertTrue(try buffer.document.save())
            XCTAssertEqual(owner.source.kind, .github)
        }
    }
}
