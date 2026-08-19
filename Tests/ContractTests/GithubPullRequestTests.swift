import XCTest

/// M17-1 / #192: the Pull Requests mailbox list seam — decode of the
/// `/pulls` list shape (draft + head/base refs) and the `state` query
/// riding the bearer-`get` seam. No network — everything is injected.
final class GithubPullRequestTests: XCTestCase {
    func testListDecodesDraftAndHeadBase() async throws {
        let transport = StubTransport()
        let openPR: [String: Any] = [
            "number": 42,
            "title": "Add a page",
            "html_url": "https://github.com/acme/blog/pull/42",
            "draft": false,
            "state": "open",
            "head": ["label": "acme:feature/x", "ref": "feature/x"],
            "base": ["label": "acme:main", "ref": "main"],
        ]
        let draftPR: [String: Any] = [
            "number": 43,
            "title": "WIP sidebar",
            "html_url": "https://github.com/acme/blog/pull/43",
            "draft": true,
            "state": "open",
            "head": ["label": "octocat:fork-branch", "ref": "fork-branch"],
            "base": ["label": "acme:trunk", "ref": "trunk"],
        ]
        await transport.enqueue(
            jsonArray([openPR, draftPR]),
            for: GithubAPIClient.listPullsURL(owner: "acme", repository: "blog", state: "open")
        )

        let pulls = try await GithubAPIClient.listPullRequests(
            owner: "acme",
            repository: "blog",
            bearer: SecureBuffer(utf8String: "gho_secret"),
            transport: transport
        )

        XCTAssertEqual(pulls.count, 2)
        let first = try XCTUnwrap(pulls.first)
        XCTAssertEqual(first.number, 42)
        XCTAssertEqual(first.title, "Add a page")
        XCTAssertEqual(first.htmlURL, "https://github.com/acme/blog/pull/42")
        XCTAssertFalse(first.draft)
        XCTAssertEqual(first.state, "open")
        XCTAssertEqual(first.head.label, "acme:feature/x")
        XCTAssertEqual(first.head.ref, "feature/x")
        XCTAssertEqual(first.base.ref, "main")

        let draft = try XCTUnwrap(pulls.last)
        XCTAssertTrue(draft.draft, "open draft PRs are included by state=open")
        XCTAssertEqual(draft.head.label, "octocat:fork-branch", "fork PRs show the fork owner, never a guessed one")
        XCTAssertEqual(draft.base.ref, "trunk")
    }

    func testDefaultStateRidesTheGet() async throws {
        let transport = StubTransport()
        await transport.enqueue(
            jsonArray([]),
            for: GithubAPIClient.listPullsURL(owner: "acme", repository: "blog", state: "open")
        )

        _ = try await GithubAPIClient.listPullRequests(
            owner: "acme",
            repository: "blog",
            bearer: SecureBuffer(utf8String: "gho_secret"),
            transport: transport
        )

        let recorded = await transport.recorded
        let call = try XCTUnwrap(recorded.first)
        XCTAssertEqual(call.url, GithubAPIClient.listPullsURL(owner: "acme", repository: "blog", state: "open"))
        XCTAssertNil(call.form)
        XCTAssertNil(call.json)
        XCTAssertEqual(call.bearerBytes, Array("gho_secret".utf8))
    }

    func testNonDefaultStateRidesTheURL() async throws {
        let transport = StubTransport()
        await transport.enqueue(
            jsonArray([]),
            for: GithubAPIClient.listPullsURL(owner: "acme", repository: "blog", state: "closed")
        )

        _ = try await GithubAPIClient.listPullRequests(
            owner: "acme",
            repository: "blog",
            state: "closed",
            bearer: SecureBuffer(utf8String: "gho_secret"),
            transport: transport
        )

        let recorded = await transport.recorded
        let call = try XCTUnwrap(recorded.first)
        XCTAssertEqual(call.url, GithubAPIClient.listPullsURL(owner: "acme", repository: "blog", state: "closed"))
    }

    func testErrorSurfacesMessage() async {
        let transport = StubTransport()
        await transport.enqueue(
            error: GithubOAuthError.httpStatus(422, message: "Validation Failed"),
            for: GithubAPIClient.listPullsURL(owner: "acme", repository: "blog", state: "open")
        )

        do {
            _ = try await GithubAPIClient.listPullRequests(
                owner: "acme",
                repository: "blog",
                bearer: SecureBuffer(utf8String: "gho_secret"),
                transport: transport
            )
            XCTFail("expected httpStatus")
        } catch let GithubOAuthError.httpStatus(status, message) {
            XCTAssertEqual(status, 422)
            XCTAssertEqual(message, "Validation Failed")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
