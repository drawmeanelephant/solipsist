import Network
import WebKit
import XCTest

@MainActor
final class ReadingWebNavigationTests: XCTestCase {
    func testNavigationPoliciesAreRegisteredDelegateMethods() {
        let model = ReadingWebModel()
        XCTAssertTrue(model.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")))
        XCTAssertTrue(model.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationResponse:decisionHandler:")))
    }

    func testNonLoopbackLoadFailsWithoutNavigating() throws {
        let model = ReadingWebModel()
        model.load(url: try XCTUnwrap(URL(string: "https://example.invalid/")))
        XCTAssertEqual(model.outcome, .failed("Only loopback URLs are allowed."))
        XCTAssertNil(model.webView.url)
    }

    func testReal404FallsBackToTheContractSummary() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                let body = "<html><body>Not found</body></html>"
                let response = "HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .global())
        defer { listener.cancel() }
        try await waitUntil("loopback listener") { listener.port.map { $0.rawValue > 0 } == true }
        let port = try XCTUnwrap(listener.port).rawValue
        let model = ReadingWebModel()
        model.load(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/missing.html")))
        defer { model.reset() }
        try await waitUntil("HTTP 404 fallback (outcome: \(model.outcome))") {
            if case .unavailable = model.outcome { return true }
            return false
        }
        XCTAssertEqual(
            model.outcome,
            .unavailable("This page is not at the served URL yet. Build HTML or wait for watch.")
        )
    }

    private func waitUntil(_ description: @autoclosure () -> String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Timed out waiting for \(description())")
                throw NSError(domain: "ReadingWebNavigationTests", code: 1)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
