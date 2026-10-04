import XCTest

@MainActor
final class ComposeBufferTests: XCTestCase {
    private let noun = WorkspaceNoun(kind: "page", id: "index", title: "Index", sourcePath: "index.md")

    private struct Fixture {
        let root: URL
        let source: LocalSource
        let fileURL: URL
    }

    private func withSources(_ test: (Fixture, Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("compose-identity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try makeSource(root: root.appendingPathComponent("A"), text: "Publication A")
        let second = try makeSource(root: root.appendingPathComponent("B"), text: "Publication B")
        try test(first, second)
    }

    private func makeSource(root: URL, text: String) throws -> Fixture {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("content"), withIntermediateDirectories: true)
        try "{}".write(to: root.appendingPathComponent("boris.json"), atomically: true, encoding: .utf8)
        try writeGraph(root: root)
        let fileURL = root.appendingPathComponent("content/index.md")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return try Fixture(root: root.standardizedFileURL, source: LocalSource.make(from: root), fileURL: fileURL.standardizedFileURL)
    }

    private func writeGraph(root: URL, sourcePath: String = "index.md") throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".boris"), withIntermediateDirectories: true)
        let graph = """
        {
          "schemaVersion": "ir-graph-0.3.0", "frozen": true,
          "nodes": [{
            "index": 0, "id": "index", "sourcePath": "\(sourcePath)",
            "role": "trunk", "parent": null, "parentIndex": null,
            "title": "Index", "status": null, "tags": [], "bodyOffset": null
          }],
          "edges": [], "reverseIndex": [], "nav": []
        }
        """
        try graph.write(to: ComposePageResolver.graphURL(workspaceRoot: root), atomically: true, encoding: .utf8)
    }

    private func request(_ source: LocalSource) -> ComposeBuffer.Request {
        ComposeBuffer.Request(
            source: source,
            selection: WorkspaceSelection(sourceID: source.id, mailbox: WorkspaceMailbox.pages, noun: noun)
        )
    }

    func testEqualNounsInDifferentSourcesLoadAndSaveTheSecondFile() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            XCTAssertTrue(buffer.select(request(first.source)))
            XCTAssertFalse(buffer.select(nil), "the intermediate cleared noun must not erase the old binding")
            XCTAssertTrue(buffer.select(request(second.source)))
            XCTAssertEqual(buffer.document.text, "Publication B")
            XCTAssertEqual(buffer.page?.owner.source.id, second.source.id)
            XCTAssertEqual(buffer.document.fileURL, second.fileURL)
            buffer.document.text = "Edited B"
            XCTAssertTrue(try buffer.document.save())
            XCTAssertEqual(try String(contentsOf: second.fileURL, encoding: .utf8), "Edited B")
            XCTAssertEqual(try String(contentsOf: first.fileURL, encoding: .utf8), "Publication A")
        }
    }

    func testSameFileDoesNotReloadDirtyWork() throws {
        try withSources { first, _ in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Unsaved A"
            XCTAssertFalse(buffer.select(request(first.source)))
            XCTAssertNil(buffer.pendingPage)
            XCTAssertEqual(buffer.document.text, "Unsaved A")
            XCTAssertTrue(buffer.document.isDirty)
        }
    }

    func testDirtyCancelRetainsSourceSelectionAndFileBinding() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Unsaved A"
            XCTAssertFalse(buffer.select(request(second.source)))
            XCTAssertEqual(buffer.pendingPage?.owner.source.id, second.source.id)
            buffer.cancelSwitch()
            XCTAssertNil(buffer.pendingPage)
            XCTAssertEqual(buffer.page?.selection, request(first.source).selection)
            XCTAssertEqual(buffer.document.fileURL, first.fileURL)
            XCTAssertEqual(buffer.document.text, "Unsaved A")
            XCTAssertTrue(buffer.document.isDirty)
            XCTAssertEqual(try String(contentsOf: first.fileURL, encoding: .utf8), "Publication A")
            XCTAssertEqual(try String(contentsOf: second.fileURL, encoding: .utf8), "Publication B")
        }
    }

    func testDirtyDiscardLoadsPendingSourceWithoutWritingEitherFile() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Unsaved A"
            buffer.select(request(second.source))
            XCTAssertTrue(buffer.discardAndSwitch())
            XCTAssertEqual(buffer.document.text, "Publication B")
            XCTAssertEqual(buffer.document.fileURL, second.fileURL)
            XCTAssertFalse(buffer.document.isDirty)
            XCTAssertEqual(try String(contentsOf: first.fileURL, encoding: .utf8), "Publication A")
            XCTAssertEqual(try String(contentsOf: second.fileURL, encoding: .utf8), "Publication B")
        }
    }

    func testDirtySaveWritesAndQueuesValidationForTheOldSourceBeforeSwitch() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Saved A"
            buffer.select(request(second.source))
            var validationOwner: ComposeSourceBinding?
            var events: [String] = []
            XCTAssertTrue(buffer.saveAndSwitch {
                let outcome = ComposeSaveFlow.run(
                    beginTreeWrite: { events.append("begin") },
                    endTreeWrite: { events.append("end") },
                    noteSave: {
                        validationOwner = buffer.page?.owner
                        events.append("validate")
                    },
                    save: {
                        events.append("write")
                        return try buffer.document.save()
                    }
                )
                return outcome == .saved
            })
            XCTAssertEqual(events, ["begin", "write", "validate", "end"])
            XCTAssertEqual(validationOwner?.source.id, first.source.id)
            XCTAssertEqual(validationOwner?.contentRoot, first.fileURL.deletingLastPathComponent())
            XCTAssertEqual(validationOwner?.workspaceRoot, first.root)
            XCTAssertEqual(buffer.page?.owner.source.id, second.source.id)
            XCTAssertEqual(buffer.document.text, "Publication B")
            XCTAssertEqual(try String(contentsOf: first.fileURL, encoding: .utf8), "Saved A")
            XCTAssertEqual(try String(contentsOf: second.fileURL, encoding: .utf8), "Publication B")
        }
    }

    func testFailedSaveDoesNotSwitchOrLoseDirtyText() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Unsaved A"
            buffer.select(request(second.source))
            XCTAssertFalse(buffer.saveAndSwitch { false })
            XCTAssertEqual(buffer.document.fileURL, first.fileURL)
            XCTAssertEqual(buffer.document.text, "Unsaved A")
            XCTAssertTrue(buffer.document.isDirty)
            XCTAssertEqual(buffer.pendingPage?.owner.source.id, second.source.id)
        }
    }
}

extension ComposeBufferTests {
    func testRelocationWithSameSourceIDAndNounReloadsTheResolvedFile() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            var relocated = second.source
            relocated.id = first.source.id
            XCTAssertNotEqual(request(first.source), request(relocated), "the window's task must observe a changed bookmark")
            XCTAssertTrue(buffer.select(request(relocated)))
            XCTAssertEqual(buffer.document.text, "Publication B")
            XCTAssertEqual(buffer.document.fileURL, second.fileURL)
            XCTAssertEqual(buffer.page?.owner.workspaceRoot, second.root)
        }
    }

    func testDirtyRelocationKeepsOldSaveAndValidationRootsUntilAccepted() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Unsaved old folder"
            var relocated = second.source
            relocated.id = first.source.id
            buffer.select(request(relocated))
            buffer.cancelSwitch()
            XCTAssertEqual(buffer.document.fileURL, first.fileURL)
            XCTAssertEqual(buffer.page?.owner.workspaceRoot, first.root)
            XCTAssertEqual(buffer.document.text, "Unsaved old folder")
            let owner = try XCTUnwrap(buffer.page?.owner)
            XCTAssertFalse(owner.isWatched(sourceID: relocated.id, contentRoot: second.fileURL.deletingLastPathComponent()))
            XCTAssertTrue(owner.isWatched(sourceID: first.source.id, contentRoot: first.fileURL.deletingLastPathComponent()))
        }
    }

    func testChangedGraphFilePathIsPartOfLoadedIdentity() throws {
        try withSources { first, _ in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            let moved = first.root.appendingPathComponent("content/renamed.md")
            try "New path".write(to: moved, atomically: true, encoding: .utf8)
            try writeGraph(root: first.root, sourcePath: "renamed.md")
            XCTAssertTrue(buffer.select(request(first.source)))
            XCTAssertEqual(buffer.document.fileURL, moved)
            XCTAssertEqual(buffer.document.text, "New path")
        }
    }

    func testSourceRemovalRetainsDirtyBufferAndItsOwnSaveBinding() throws {
        try withSources { first, _ in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Edit after removal"
            buffer.select(nil)
            XCTAssertEqual(buffer.page?.owner.source.id, first.source.id)
            XCTAssertEqual(buffer.document.fileURL, first.fileURL)
            XCTAssertTrue(buffer.document.isDirty)
            XCTAssertTrue(try buffer.document.save())
            XCTAssertEqual(try String(contentsOf: first.fileURL, encoding: .utf8), "Edit after removal")
        }
    }

    func testFailedResolutionPreservesDirtyBufferAndCanRetrySameSelection() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Unsaved A"
            try "not JSON".write(to: ComposePageResolver.graphURL(workspaceRoot: second.root), atomically: true, encoding: .utf8)
            XCTAssertFalse(buffer.select(request(second.source)))
            XCTAssertNotNil(buffer.loadError)
            XCTAssertNil(buffer.pendingPage)
            XCTAssertEqual(buffer.document.text, "Unsaved A")
            XCTAssertEqual(buffer.document.fileURL, first.fileURL)
            try writeGraph(root: second.root)
            buffer.select(request(second.source))
            XCTAssertTrue(buffer.discardAndSwitch())
            XCTAssertEqual(buffer.document.text, "Publication B")
        }
    }

    func testUnreadablePendingFileDoesNotDiscardOldWork() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Unsaved A"
            buffer.select(request(second.source))
            try FileManager.default.removeItem(at: second.fileURL)
            XCTAssertFalse(buffer.discardAndSwitch())
            XCTAssertNotNil(buffer.loadError)
            XCTAssertEqual(buffer.page?.owner.source.id, first.source.id)
            XCTAssertEqual(buffer.document.fileURL, first.fileURL)
            XCTAssertEqual(buffer.document.text, "Unsaved A")
            XCTAssertTrue(buffer.document.isDirty)
        }
    }

    func testCleanReadFailureDoesNotCommitTheNewIdentity() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            try Data([0xFF, 0xFE, 0xFF]).write(to: second.fileURL)
            XCTAssertFalse(buffer.select(request(second.source)))
            XCTAssertNotNil(buffer.loadError)
            XCTAssertEqual(buffer.page?.owner.source.id, first.source.id)
            XCTAssertEqual(buffer.document.text, "Publication A")
            try "Recovered B".write(to: second.fileURL, atomically: true, encoding: .utf8)
            XCTAssertTrue(buffer.select(request(second.source)))
            XCTAssertEqual(buffer.document.text, "Recovered B")
        }
    }

    func testUnavailableSourceAndMissingNodePreserveTheLoadedBuffer() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            var unavailable = second.source
            unavailable.isAvailable = false
            XCTAssertFalse(buffer.select(request(unavailable)))
            XCTAssertNotNil(buffer.loadError)
            XCTAssertEqual(buffer.document.fileURL, first.fileURL)
            var selection = request(second.source).selection
            selection.noun?.id = "missing"
            XCTAssertFalse(buffer.select(ComposeBuffer.Request(source: second.source, selection: selection)))
            XCTAssertEqual(buffer.loadError, "No graph node for “Index”.")
            XCTAssertEqual(buffer.document.text, "Publication A")
        }
    }

    func testForeignValidationDaemonDoesNotOwnTheBuffersSave() throws {
        try withSources { first, second in
            let owner = try ComposeSourceBinding(source: first.source)
            XCTAssertFalse(owner.isWatched(sourceID: second.source.id, contentRoot: second.fileURL.deletingLastPathComponent()))
            XCTAssertFalse(owner.isWatched(sourceID: second.source.id, contentRoot: owner.contentRoot))
            XCTAssertFalse(owner.isWatched(sourceID: nil, contentRoot: nil))
            XCTAssertTrue(owner.isWatched(sourceID: first.source.id, contentRoot: owner.contentRoot))
        }
    }

    func testDialogDismissalDoesNotLoseCapturedDiscardDestination() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Unsaved A"
            buffer.select(request(second.source))
            let capturedPage = try XCTUnwrap(buffer.pendingPage)
            buffer.cancelSwitch()
            XCTAssertTrue(buffer.discardAndSwitch(to: capturedPage))
            XCTAssertEqual(buffer.document.text, "Publication B")
            XCTAssertEqual(buffer.document.fileURL, second.fileURL)
        }
    }

    func testDialogDismissalDoesNotLoseCapturedSaveDestination() throws {
        try withSources { first, second in
            let buffer = ComposeBuffer()
            buffer.select(request(first.source))
            buffer.document.text = "Saved A"
            buffer.select(request(second.source))
            let capturedPage = try XCTUnwrap(buffer.pendingPage)
            buffer.cancelSwitch()
            XCTAssertTrue(buffer.saveAndSwitch(to: capturedPage) {
                (try? buffer.document.save()) == true
            })
            XCTAssertEqual(buffer.document.text, "Publication B")
            XCTAssertEqual(try String(contentsOf: first.fileURL, encoding: .utf8), "Saved A")
        }
    }
}
