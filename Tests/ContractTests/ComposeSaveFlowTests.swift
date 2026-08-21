import XCTest

/// #231 — Compose toolbar save must suspend the preview watch.
///
/// The toolbar Save button never writes the buffer itself: it calls the
/// host's `onSave`, which runs `ComposeSaveFlow.run` so the write lands
/// inside `beginTreeWrite()` / `endTreeWrite()` and a clean write queues
/// validation (`noteSave()`). These tests pin that sequence — the bug was
/// an unsuspended write racing boris's watch mid-write.
@MainActor
final class ComposeSaveFlowTests: XCTestCase {
    // MARK: - Fixtures

    /// A dirty document backed by a real temp file.
    private func makeDocument(url: URL) -> ComposeDocument {
        let doc = ComposeDocument(text: "Hello", fileURL: url)
        doc.text = "Hello, world."
        return doc
    }

    // MARK: - The three gate tests

    func testToolbarSaveWritesInsideTreeWrite() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-flow-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = makeDocument(url: url)
        var events: [String] = []

        let outcome = ComposeSaveFlow.run(
            beginTreeWrite: { events.append("begin") },
            endTreeWrite: { events.append("end") },
            noteSave: { events.append("noteSave") },
            save: {
                events.append("write")
                return try doc.save()
            }
        )

        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(events.first, "begin", "the watch must be suspended before the write")
        XCTAssertEqual(events.last, "end", "the watch must resume after the write")
        guard let begin = events.firstIndex(of: "begin"),
              let write = events.firstIndex(of: "write"),
              let end = events.lastIndex(of: "end")
        else {
            return XCTFail("missing begin/write/end in \(events)")
        }
        XCTAssertLessThan(begin, write, "expected begin < write < end, got \(events)")
        XCTAssertLessThan(write, end, "expected begin < write < end, got \(events)")
    }

    func testToolbarSaveWritesOnce() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-flow-once-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = makeDocument(url: url)
        var writes = 0

        _ = ComposeSaveFlow.run(
            beginTreeWrite: {},
            endTreeWrite: {},
            noteSave: {},
            save: {
                writes += 1
                return try doc.save()
            }
        )

        XCTAssertEqual(writes, 1, "one Save must produce exactly one write")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Hello, world.")
        XCTAssertFalse(doc.isDirty)
    }

    func testToolbarSaveQueuesValidation() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compose-flow-queue-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = makeDocument(url: url)
        var events: [String] = []

        let outcome = ComposeSaveFlow.run(
            beginTreeWrite: { events.append("begin") },
            endTreeWrite: { events.append("end") },
            noteSave: { events.append("noteSave") },
            save: {
                events.append("write")
                return try doc.save()
            }
        )

        XCTAssertEqual(outcome, .saved)
        guard let write = events.firstIndex(of: "write"),
              let noteSave = events.firstIndex(of: "noteSave")
        else {
            return XCTFail("missing write/noteSave in \(events)")
        }
        XCTAssertLessThan(write, noteSave, "validation is queued only after the write")
    }

    // MARK: - Edge cases from the card

    func testFailedWriteResumesWatchAndSkipsValidation() {
        struct Boom: LocalizedError {
            var errorDescription: String? { "disk on strike" }
        }
        var events: [String] = []

        let outcome = ComposeSaveFlow.run(
            beginTreeWrite: { events.append("begin") },
            endTreeWrite: { events.append("end") },
            noteSave: { events.append("noteSave") },
            save: {
                events.append("write")
                throw Boom()
            }
        )

        XCTAssertEqual(outcome, .failed("disk on strike"))
        XCTAssertFalse(events.contains("noteSave"), "a failed write must not queue validation")
        XCTAssertEqual(events.last, "end", "deferred endTreeWrite must run even when the write throws")
    }

    func testCleanBufferWritesNothingAndQueuesNothing() {
        var events: [String] = []

        let outcome = ComposeSaveFlow.run(
            beginTreeWrite: { events.append("begin") },
            endTreeWrite: { events.append("end") },
            noteSave: { events.append("noteSave") },
            save: {
                events.append("write-attempt")
                return false
            }
        )

        XCTAssertEqual(outcome, .notDirty)
        XCTAssertFalse(events.contains("noteSave"), "no write → no validate queued")
        XCTAssertEqual(events.last, "end", "the window still opens and closes around the attempt")
    }
}
