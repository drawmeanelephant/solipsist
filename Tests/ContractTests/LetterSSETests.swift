import XCTest

/// M14-2 (#148): the letter reloads on the existing helper's SSE
/// `event: reload`; a fixture event triggers the reload hook, and a
/// bound-root mismatch never opens the channel. No live `watch` in CI.
final class LetterSSETests: XCTestCase {
    // MARK: SSE wire parse

    func testFixtureReloadEventParses() {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for line in ["event: reload", "data: 1", "", ""] {
            events.append(contentsOf: parser.feed(line: line))
        }
        XCTAssertEqual(events, [SSEEvent(name: "reload", data: "1")])
    }

    func testHandshakeLineParses() {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for line in ["event: reload", "data: 0", ""] {
            events.append(contentsOf: parser.feed(line: line))
        }
        XCTAssertEqual(events, [SSEEvent(name: "reload", data: "0")])
    }

    func testCommentAndRetryFieldsAreIgnored() {
        var parser = SSEParser()
        let ignored = parser.feed(line: ": keep-alive comment")
        XCTAssertTrue(ignored.isEmpty)
        let retry = parser.feed(line: "retry: 1000")
        XCTAssertTrue(retry.isEmpty)
        let id = parser.feed(line: "id: 7")
        XCTAssertTrue(id.isEmpty)
    }

    func testMultiLineDataJoinsWithNewline() {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for line in ["event: reload", "data: a", "data: b", ""] {
            events.append(contentsOf: parser.feed(line: line))
        }
        XCTAssertEqual(events, [SSEEvent(name: "reload", data: "a\nb")])
    }

    func testCarriageReturnsAreTolerated() {
        var parser = SSEParser()
        var events: [SSEEvent] = []
        for line in ["event: reload\r", "data: 2\r", "\r"] {
            events.append(contentsOf: parser.feed(line: line))
        }
        XCTAssertEqual(events, [SSEEvent(name: "reload", data: "2")])
    }

    // MARK: Reload policy (generation counter)

    func testFirstEventIsHandshakeNotReload() {
        let result = LetterSSEClient.shouldReload(generation: 0, lastGeneration: nil)
        XCTAssertFalse(result.reload)
        XCTAssertEqual(result.last, 0)
    }

    func testAdvancingGenerationReloads() {
        let result = LetterSSEClient.shouldReload(generation: 1, lastGeneration: 0)
        XCTAssertTrue(result.reload)
        XCTAssertEqual(result.last, 1)
    }

    func testSameGenerationDoesNotReload() {
        let result = LetterSSEClient.shouldReload(generation: 3, lastGeneration: 3)
        XCTAssertFalse(result.reload)
        XCTAssertEqual(result.last, 3)
    }

    func testCounterResetAfterRestartReloads() {
        let result = LetterSSEClient.shouldReload(generation: 0, lastGeneration: 5)
        XCTAssertTrue(result.reload)
        XCTAssertEqual(result.last, 0)
    }

    // MARK: Channel gating

    func testEventsURLDerivedFromLoopbackHelper() throws {
        let helper = try XCTUnwrap(URL(string: "http://127.0.0.1:58343/__boris/"))
        let events = try XCTUnwrap(PreviewURL.eventsURL(fromHelper: helper))
        XCTAssertEqual(events.absoluteString, "http://127.0.0.1:58343/__boris/events")
    }

    func testEventsURLRejectsForeignHost() throws {
        let helper = try XCTUnwrap(URL(string: "https://example.com/__boris/"))
        XCTAssertNil(PreviewURL.eventsURL(fromHelper: helper))
    }

    func testPolicyRequiresBoundRoot() throws {
        let helper = try XCTUnwrap(URL(string: "http://127.0.0.1:58343/__boris/"))
        // Bound-root mismatch → idle, even with a serving helper.
        XCTAssertNil(LetterReloadPolicy.eventsURL(helper: helper, bound: false, showingPage: true))
        // No page showing → idle.
        XCTAssertNil(LetterReloadPolicy.eventsURL(helper: helper, bound: true, showingPage: false))
        // Watch down (no helper) → idle.
        XCTAssertNil(LetterReloadPolicy.eventsURL(helper: nil, bound: true, showingPage: true))
    }

    func testPolicyOpensChannelOnlyWhenBoundAndShowing() throws {
        let helper = try XCTUnwrap(URL(string: "http://127.0.0.1:58343/__boris/"))
        let events = try XCTUnwrap(
            LetterReloadPolicy.eventsURL(helper: helper, bound: true, showingPage: true)
        )
        XCTAssertEqual(events.absoluteString, "http://127.0.0.1:58343/__boris/events")
    }
}
