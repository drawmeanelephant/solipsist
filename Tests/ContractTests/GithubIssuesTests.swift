import XCTest

/// M16-4 / #185: the issues mailbox API surface (list with PRs filtered
/// out, create over the JSON-post seam) and the github-only `issues`
/// mailbox token. No network — everything rides the injected transport.
final class GithubIssuesTests: XCTestCase {
    func testListIssuesDecodesLabelsAndFiltersPullRequests() async throws {
        let transport = StubTransport()
        let issueJSON: [String: Any] = [
            "number": 12,
            "title": "Fix the sidebar",
            "html_url": "https://github.com/acme/blog/issues/12",
            "labels": [["name": "bug", "color": "d73a4a"], ["name": "help wanted", "color": "008672"]],
        ]
        // REST mixes PRs into /issues — the mailbox must drop them.
        let prJSON: [String: Any] = [
            "number": 42,
            "title": "Add a page",
            "html_url": "https://github.com/acme/blog/pull/42",
            "labels": [],
            "pull_request": ["url": "https://api.github.com/repos/acme/blog/pulls/42"],
        ]
        await transport.enqueue(
            jsonArray([issueJSON, prJSON]),
            for: GithubAPIClient.issuesURL(owner: "acme", repository: "blog")
        )

        let issues = try await GithubAPIClient.listIssues(
            owner: "acme",
            repository: "blog",
            bearer: SecureBuffer(utf8String: "gho_secret"),
            transport: transport
        )

        XCTAssertEqual(issues.count, 1, "the PR must be filtered out")
        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issue.number, 12)
        XCTAssertEqual(issue.title, "Fix the sidebar")
        XCTAssertEqual(issue.htmlURL, "https://github.com/acme/blog/issues/12")
        XCTAssertEqual(issue.labels.map(\.name), ["bug", "help wanted"])
        XCTAssertEqual(issue.labels.map(\.color), ["d73a4a", "008672"])
        XCTAssertFalse(issue.isPullRequest)
    }

    func testListIssuesBearerRidesTheGet() async throws {
        let transport = StubTransport()
        await transport.enqueue(jsonArray([]), for: GithubAPIClient.issuesURL(owner: "acme", repository: "blog"))

        _ = try await GithubAPIClient.listIssues(
            owner: "acme",
            repository: "blog",
            bearer: SecureBuffer(utf8String: "gho_secret"),
            transport: transport
        )

        let recorded = await transport.recorded
        let call = try XCTUnwrap(recorded.first)
        XCTAssertEqual(call.url, GithubAPIClient.issuesURL(owner: "acme", repository: "blog"))
        XCTAssertNil(call.form)
        XCTAssertNil(call.json)
        XCTAssertEqual(call.bearerBytes, Array("gho_secret".utf8))
    }

    func testCreateIssueDecodeAndJsonBearerRideThePost() async throws {
        let transport = StubTransport()
        await transport.enqueue(
            json(["number": 13, "title": "New bug", "html_url": "https://github.com/acme/blog/issues/13", "labels": []]),
            for: GithubAPIClient.issuesURL(owner: "acme", repository: "blog")
        )

        let created = try await GithubAPIClient.createIssue(
            owner: "acme",
            repository: "blog",
            title: "New bug",
            body: "Details here",
            bearer: SecureBuffer(utf8String: "gho_secret"),
            transport: transport
        )

        XCTAssertEqual(created.number, 13)
        XCTAssertEqual(created.htmlURL, "https://github.com/acme/blog/issues/13")

        let recorded = await transport.recorded
        let call = try XCTUnwrap(recorded.first)
        XCTAssertEqual(call.url, GithubAPIClient.issuesURL(owner: "acme", repository: "blog"))
        XCTAssertNil(call.form)
        XCTAssertEqual(call.bearerBytes, Array("gho_secret".utf8))
        let jsonBody = try XCTUnwrap(call.json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonBody) as? [String: String])
        XCTAssertEqual(object["title"], "New bug")
        XCTAssertEqual(object["body"], "Details here")
        XCTAssertEqual(object.count, 2, "title + body, never more")
    }

    func testCreateIssueErrorSurfacesMessage() async {
        let transport = StubTransport()
        await transport.enqueue(
            error: GithubOAuthError.httpStatus(422, message: "Validation Failed"),
            for: GithubAPIClient.issuesURL(owner: "acme", repository: "blog")
        )

        do {
            _ = try await GithubAPIClient.createIssue(
                owner: "acme",
                repository: "blog",
                title: "T",
                body: "B",
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

    func testMailboxRowsAreGithubOnly() {
        let source = makeSource()
        let githubRows = WorkspaceMailbox.all(for: SourceItem.github(source))
        XCTAssertTrue(githubRows.contains(WorkspaceMailbox.remote))
        XCTAssertTrue(githubRows.contains(WorkspaceMailbox.issues))
        XCTAssertTrue(githubRows.contains(WorkspaceMailbox.pulls), "M17: Pull Requests row is github-only too")

        // Every known token is in the github row set, in the canonical order.
        XCTAssertEqual(Array(githubRows.prefix(WorkspaceMailbox.all.count)), WorkspaceMailbox.all)
        XCTAssertEqual(
            githubRows.suffix(3),
            [WorkspaceMailbox.remote, WorkspaceMailbox.issues, WorkspaceMailbox.pulls]
        )

        // Local sources never see the github-only rows.
        let local = SourceItem.local(LocalSource(
            id: SourceID(),
            title: "Blog",
            bookmarkData: Data([1, 2, 3]),
            displayPath: "/tmp/blog",
            isAvailable: true
        ))
        let localRows = WorkspaceMailbox.all(for: local)
        XCTAssertFalse(localRows.contains(WorkspaceMailbox.remote))
        XCTAssertFalse(localRows.contains(WorkspaceMailbox.issues))
        XCTAssertFalse(localRows.contains(WorkspaceMailbox.pulls))
        XCTAssertEqual(localRows, WorkspaceMailbox.all)
    }

    private func makeSource() -> GithubSource {
        GithubSource(
            id: SourceID(),
            title: "acme/blog",
            owner: "acme",
            repository: "blog",
            defaultBranch: "main",
            bookmarkData: Data([1, 2, 3]),
            displayPath: "/tmp/blog",
            grantedScopes: ["repo"]
        )
    }
}
