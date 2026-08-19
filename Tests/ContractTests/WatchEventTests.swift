import XCTest

/// M14-1 (#147): A1 `--watch-json` NDJSON lines decode, `serve-started`
/// yields the helper URL after the `hello` handshake, and an unknown
/// `watch_events_schema` degrades without crashing. No live `watch` in CI.
final class WatchEventTests: XCTestCase {
    // MARK: Decode (fixture lines from the A1 contract)

    func testHelloDecodes() throws {
        let event = try XCTUnwrap(
            WatchEvent.decode(line: #"{"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.1"}"#)
        )
        guard case .hello(let schema, let compiler) = event else {
            return XCTFail("expected hello, got \(event)")
        }
        XCTAssertEqual(schema, 1)
        XCTAssertEqual(compiler, "boris/0.8.1")
    }

    func testServeStartedDecodesHelperURL() throws {
        let event = try XCTUnwrap(
            WatchEvent.decode(
                line: #"{"event":"serve-started","url":"http://127.0.0.1:53202/","helper":"http://127.0.0.1:53202/__boris/","port":53202}"#
            )
        )
        guard case .serveStarted(let url, let helper, let port) = event else {
            return XCTFail("expected serve-started, got \(event)")
        }
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:53202/")
        XCTAssertEqual(helper?.absoluteString, "http://127.0.0.1:53202/__boris/")
        XCTAssertEqual(port, 53202)
    }

    func testFailureAndStopEventsDecode() throws {
        let failed = try XCTUnwrap(
            WatchEvent.decode(
                line: #"{"event":"build-failed","phase":"rebuild","errors":1,"recoverable":true,"duration_ms":14}"#
            )
        )
        guard case .buildFailed(let errors, let recoverable, let diagnostics) = failed else {
            return XCTFail("expected build-failed, got \(failed)")
        }
        XCTAssertEqual(errors, 1)
        XCTAssertTrue(recoverable)
        XCTAssertTrue(diagnostics.isEmpty, "a build-failed without a diagnostics key decodes to an empty array")

        let watchError = try XCTUnwrap(
            WatchEvent.decode(line: #"{"event":"watch-error","message":"poll error (BrokenPipe)","recoverable":true}"#)
        )
        guard case .watchError(let message, _) = watchError else {
            return XCTFail("expected watch-error, got \(watchError)")
        }
        XCTAssertEqual(message, "poll error (BrokenPipe)")

        let stopped = try XCTUnwrap(
            WatchEvent.decode(line: #"{"event":"watch-stopped","reason":"signal"}"#)
        )
        guard case .watchStopped(let reason) = stopped else {
            return XCTFail("expected watch-stopped, got \(stopped)")
        }
        XCTAssertEqual(reason, "signal")
    }

    func testUnknownEventAndGarbageNeverCrash() {
        // Unknown event value → skipped, no crash.
        XCTAssertNotNil(
            WatchEvent.decode(line: #"{"event":"build-succeeded","pages_written":25}"#)
        )
        // Not JSON / empty lines → nil, no crash.
        XCTAssertNil(WatchEvent.decode(line: "preview: http://127.0.0.1:53202/  (auto-reload helper: …)"))
        XCTAssertNil(WatchEvent.decode(line: ""))
    }

    // MARK: Parser (handshake gate + helper URL + problem surfacing)

    func testServeStartedAfterHelloYieldsHelperURL() {
        var parser = WatchStreamParser()
        parser.consume(line: #"{"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.1"}"#)
        parser.consume(line: #"{"event":"serve-started","url":"http://127.0.0.1:53202/","helper":"http://127.0.0.1:53202/__boris/","port":53202}"#)
        XCTAssertEqual(parser.serveURL?.absoluteString, "http://127.0.0.1:53202/__boris/")
        XCTAssertTrue(parser.didServe)
        XCTAssertTrue(parser.problems.isEmpty)
    }

    func testServeStartedWithURLOnlyDerivesHelper() {
        var parser = WatchStreamParser()
        parser.consume(line: #"{"event":"hello","watch_events_schema":1}"#)
        parser.consume(line: #"{"event":"serve-started","url":"http://127.0.0.1:8123/","port":8123}"#)
        XCTAssertEqual(parser.serveURL?.absoluteString, "http://127.0.0.1:8123/__boris/")
    }

    func testUnknownSchemaDegradesWithoutCrash() {
        var parser = WatchStreamParser()
        parser.consume(line: #"{"event":"hello","watch_events_schema":2,"compiler":"boris/0.9.0"}"#)
        parser.consume(line: #"{"event":"serve-started","url":"http://127.0.0.1:9999/","helper":"http://127.0.0.1:9999/__boris/","port":9999}"#)
        // D8: unknown shape is not trusted — no helper URL, problem surfaced.
        XCTAssertNil(parser.serveURL)
        XCTAssertFalse(parser.didServe)
        XCTAssertEqual(
            parser.problems.first,
            "watch events schema 2 is not supported (supported: 1)"
        )
    }

    func testServeStartedBeforeHandshakeIsIgnored() {
        var parser = WatchStreamParser()
        parser.consume(line: #"{"event":"serve-started","helper":"http://127.0.0.1:1/__boris/"}"#)
        XCTAssertNil(parser.serveURL)
        XCTAssertEqual(
            parser.problems.first,
            "serve-started before a supported watch events handshake — ignoring"
        )
    }

    func testBuildFailedAndWatchStoppedAreSurfaced() {
        var parser = WatchStreamParser()
        parser.consume(line: #"{"event":"hello","watch_events_schema":1}"#)
        parser.consume(line: #"{"event":"build-failed","errors":2,"recoverable":true}"#)
        parser.consume(line: #"{"event":"watch-error","message":"poll error","recoverable":false}"#)
        parser.consume(line: #"{"event":"watch-stopped","reason":"signal"}"#)
        XCTAssertEqual(
            parser.problems,
            [
                "build failed: 2 errors (recoverable)",
                "watch error: poll error",
                "watch stopped: signal",
            ]
        )
    }

    // MARK: A5 validate --watch (boris#647, #161) — probe-shaped fixtures

    func testValidateStreamBuildSucceededOutcome() {
        // The probed A5 shape at bf464a0: mode "validate", rebuild cycles
        // carry `changed`, build-succeeded has pages_written null.
        var parser = WatchStreamParser()
        parser.consume(line: #"{"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.1"}"#)
        parser.consume(line: #"{"event":"build-started","phase":"initial","mode":"validate","targets":["default"]}"#)
        parser.consume(line: #"{"event":"build-succeeded","phase":"initial","mode":"validate","targets":["default"],"pages_written":null,"duration_ms":22}"#)
        XCTAssertEqual(parser.buildOutcome, .succeeded(changed: nil))
        XCTAssertTrue(parser.problems.isEmpty)

        // Probe-shaped build-failed (bf464a0): full diagnostic objects with
        // nulls, built via the json() test helper so the line stays readable.
        let failedObject: [String: Any] = [
            "event": "build-failed", "phase": "rebuild", "mode": "validate",
            "changed": ["guides.md"], "errors": 2, "recoverable": true, "duration_ms": 23,
            "diagnostics": [
                [
                    "severity": "error", "code": "EROUTEMISSING",
                    "message": "does not resolve to a published output [fix the path, or publish the file it names]",
                    "remediation": "Fix the path, or publish the file it names",
                    "sourcePath": "guides.html", "line": 133, "column": NSNull(), "id": NSNull(),
                ],
            ],
        ]
        let failedLine = String(data: json(failedObject), encoding: .utf8) ?? ""
        parser.consume(line: failedLine)
        guard case .failed(let diagnostics) = parser.buildOutcome else {
            return XCTFail("expected .failed after build-failed")
        }
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertEqual(diagnostics.first?.code, "EROUTEMISSING")
        XCTAssertEqual(diagnostics.first?.sourcePath, "guides.html")
        XCTAssertEqual(diagnostics.first?.line, 133)
        // The summary string still surfaces for the HTML watch — the daemon
        // filters it structurally, the parser keeps it.
        XCTAssertEqual(parser.problems, ["build failed: 2 errors (recoverable)"])

        parser.consume(line: #"{"event":"build-succeeded","phase":"rebuild","mode":"validate","changed":["guides.md"],"pages_written":null,"duration_ms":30}"#)
        XCTAssertEqual(parser.buildOutcome, .succeeded(changed: ["guides.md"]))
    }

    func testValidateBuildOutcomeIsHandshakeGated() {
        // D8: a build event before a supported hello is not trusted — no
        // outcome drives the pane.
        var parser = WatchStreamParser()
        parser.consume(line: #"{"event":"build-succeeded","phase":"initial","mode":"validate"}"#)
        XCTAssertNil(parser.buildOutcome)
        XCTAssertTrue(parser.problems.isEmpty)

        // An unknown schema also gates the outcome while surfacing the
        // schema problem.
        parser.consume(line: #"{"event":"hello","watch_events_schema":2}"#)
        parser.consume(line: #"{"event":"build-failed","errors":1,"recoverable":true,"diagnostics":[]}"#)
        XCTAssertNil(parser.buildOutcome)
        XCTAssertEqual(parser.problems.first, "watch events schema 2 is not supported (supported: 1)")
    }

    func testBuildFailedSummaryPrefixMarksOnlyBuildFailures() {
        XCTAssertTrue(
            WatchStreamParser.buildFailedSummary(errors: 1, recoverable: true)
                .hasPrefix(WatchStreamParser.buildFailedSummaryPrefix)
        )
        XCTAssertFalse("watch error: poll error".hasPrefix(WatchStreamParser.buildFailedSummaryPrefix))
    }

    func testFullFixtureStreamServesOnce() {
        // The probe of the pinned-kit lineage (boris 0.8.1 + A1).
        var parser = WatchStreamParser()
        let stream = [
            #"{"event":"hello","watch_events_schema":1,"compiler":"boris/0.8.1"}"#,
            #"{"event":"build-started","phase":"initial","mode":"html","targets":["default"]}"#,
            #"{"event":"build-succeeded","phase":"initial","mode":"html","targets":["default"],"pages_written":0,"duration_ms":69}"#,
            #"{"event":"watcher-started","mode":"html","targets":["default"]}"#,
            #"{"event":"serve-started","url":"http://127.0.0.1:58317/","helper":"http://127.0.0.1:58317/__boris/","port":58317}"#,
            #"{"event":"build-failed","phase":"rebuild","errors":1,"recoverable":true,"duration_ms":14}"#,
            #"{"event":"watch-stopped","reason":"signal"}"#,
        ]
        for line in stream {
            parser.consume(line: line)
        }
        XCTAssertEqual(parser.serveURL?.absoluteString, "http://127.0.0.1:58317/__boris/")
        XCTAssertTrue(parser.didServe)
        XCTAssertEqual(
            parser.problems,
            ["build failed: 1 error (recoverable)", "watch stopped: signal"]
        )
    }
}
