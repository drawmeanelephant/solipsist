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
        XCTAssertEqual(call.bearerBytes, Array("gho_secret".utf8))
    }
}
