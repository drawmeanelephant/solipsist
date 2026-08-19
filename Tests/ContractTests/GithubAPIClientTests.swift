import XCTest

final class GithubAPIClientTests: XCTestCase {
    func testUserDecode() async throws {
        let transport = StubTransport()
        await transport.enqueue(
            json(["login": "octocat", "name": "Mona", "id": 1]),
            for: GithubAPIClient.userURL
        )

        let user = try await GithubAPIClient.user(
            bearer: SecureBuffer(utf8String: "gho_test"),
            transport: transport
        )

        XCTAssertEqual(user.login, "octocat")
        XCTAssertEqual(user.name, "Mona")
        XCTAssertEqual(user.id, 1)
    }

    func testUserWithoutNameDecodes() async throws {
        let transport = StubTransport()
        await transport.enqueue(json(["login": "octocat", "id": 2]), for: GithubAPIClient.userURL)

        let user = try await GithubAPIClient.user(
            bearer: SecureBuffer(utf8String: "gho_test"),
            transport: transport
        )

        XCTAssertEqual(user.login, "octocat")
        XCTAssertNil(user.name)
    }

    func testRepositoryDecode() async throws {
        let transport = StubTransport()
        await transport.enqueue(
            json(["full_name": "acme/blog", "default_branch": "main", "private": false]),
            for: GithubAPIClient.repositoryURL(owner: "acme", repository: "blog")
        )

        let repo = try await GithubAPIClient.repository(
            owner: "acme",
            repository: "blog",
            bearer: SecureBuffer(utf8String: "gho_test"),
            transport: transport
        )

        XCTAssertEqual(repo.fullName, "acme/blog")
        XCTAssertEqual(repo.defaultBranch, "main")
        XCTAssertFalse(repo.isPrivate)
    }

    func testRepositoryPrivateDecodes() async throws {
        let transport = StubTransport()
        await transport.enqueue(
            json(["full_name": "acme/private", "default_branch": "trunk", "private": true]),
            for: GithubAPIClient.repositoryURL(owner: "acme", repository: "private")
        )

        let repo = try await GithubAPIClient.repository(
            owner: "acme",
            repository: "private",
            bearer: SecureBuffer(utf8String: "gho_test"),
            transport: transport
        )

        XCTAssertTrue(repo.isPrivate)
        XCTAssertEqual(repo.defaultBranch, "trunk")
    }

    func testErrorSurfacesMessage() async {
        let transport = StubTransport()
        await transport.enqueue(
            error: GithubOAuthError.httpStatus(404, message: "Not Found"),
            for: GithubAPIClient.repositoryURL(owner: "acme", repository: "missing")
        )

        do {
            _ = try await GithubAPIClient.repository(
                owner: "acme",
                repository: "missing",
                bearer: SecureBuffer(utf8String: "gho_test"),
                transport: transport
            )
            XCTFail("expected httpStatus")
        } catch let GithubOAuthError.httpStatus(status, message) {
            XCTAssertEqual(status, 404)
            XCTAssertEqual(message, "Not Found")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMalformedBodyIsInvalidResponse() async {
        let transport = StubTransport()
        await transport.enqueue(json(["unexpected": true]), for: GithubAPIClient.userURL)

        do {
            _ = try await GithubAPIClient.user(
                bearer: SecureBuffer(utf8String: "gho_test"),
                transport: transport
            )
            XCTFail("expected invalidResponse")
        } catch GithubOAuthError.invalidResponse {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testBearerRidesTheGetRequest() async throws {
        let transport = StubTransport()
        await transport.enqueue(json(["login": "octocat", "id": 1]), for: GithubAPIClient.userURL)

        _ = try await GithubAPIClient.user(
            bearer: SecureBuffer(utf8String: "gho_secret"),
            transport: transport
        )

        let recorded = await transport.recorded
        let call = try XCTUnwrap(recorded.first)
        XCTAssertEqual(call.url, GithubAPIClient.userURL)
        XCTAssertNil(call.form)
        XCTAssertNil(call.json)
        XCTAssertEqual(call.bearerBytes, Array("gho_secret".utf8))
    }

    // MARK: - PR creation (M16-3)

    func testCreatePullRequestDecode() async throws {
        let transport = StubTransport()
        await transport.enqueue(
            json(["number": 42, "html_url": "https://github.com/acme/blog/pull/42"]),
            for: GithubAPIClient.pullsURL(owner: "acme", repository: "blog")
        )

        let created = try await GithubAPIClient.createPullRequest(
            owner: "acme",
            repository: "blog",
            title: "Add a page",
            body: "Body",
            head: "feature/x",
            base: "main",
            bearer: SecureBuffer(utf8String: "gho_secret"),
            transport: transport
        )

        XCTAssertEqual(created.number, 42)
        XCTAssertEqual(created.htmlURL, "https://github.com/acme/blog/pull/42")
    }

    func testCreatePullRequestJsonAndBearerRideThePost() async throws {
        let transport = StubTransport()
        await transport.enqueue(
            json(["number": 7, "html_url": "https://github.com/acme/blog/pull/7"]),
            for: GithubAPIClient.pullsURL(owner: "acme", repository: "blog")
        )

        _ = try await GithubAPIClient.createPullRequest(
            owner: "acme",
            repository: "blog",
            title: "T",
            body: "B",
            head: "h",
            base: "b",
            bearer: SecureBuffer(utf8String: "gho_secret"),
            transport: transport
        )

        let recorded = await transport.recorded
        let call = try XCTUnwrap(recorded.first)
        XCTAssertEqual(call.url, GithubAPIClient.pullsURL(owner: "acme", repository: "blog"))
        XCTAssertNil(call.form)
        XCTAssertEqual(call.bearerBytes, Array("gho_secret".utf8))
        let json = try XCTUnwrap(call.json)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: String])
        XCTAssertEqual(object["title"], "T")
        XCTAssertEqual(object["body"], "B")
        XCTAssertEqual(object["head"], "h")
        XCTAssertEqual(object["base"], "b")
    }

    func testCreatePullRequestErrorSurfacesMessage() async {
        let transport = StubTransport()
        await transport.enqueue(
            error: GithubOAuthError.httpStatus(422, message: "Validation Failed"),
            for: GithubAPIClient.pullsURL(owner: "acme", repository: "blog")
        )

        do {
            _ = try await GithubAPIClient.createPullRequest(
                owner: "acme",
                repository: "blog",
                title: "T",
                body: "B",
                head: "h",
                base: "b",
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

    func testCreatePullRequestMalformedBodyIsInvalidResponse() async {
        let transport = StubTransport()
        await transport.enqueue(json(["unexpected": true]), for: GithubAPIClient.pullsURL(owner: "acme", repository: "blog"))

        do {
            _ = try await GithubAPIClient.createPullRequest(
                owner: "acme",
                repository: "blog",
                title: "T",
                body: "B",
                head: "h",
                base: "b",
                bearer: SecureBuffer(utf8String: "gho_secret"),
                transport: transport
            )
            XCTFail("expected invalidResponse")
        } catch GithubOAuthError.invalidResponse {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
