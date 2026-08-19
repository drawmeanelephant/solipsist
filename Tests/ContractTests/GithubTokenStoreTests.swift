import XCTest

final class GithubTokenStoreTests: XCTestCase {
    func testSaveLoadDelete() throws {
        let store = GithubTokenStore(keychain: MockKeychainStore(), service: "test.service")
        let token = SecureBuffer(utf8String: "gho_secret")

        try store.save(token, owner: "acme", repository: "blog")

        XCTAssertTrue(store.hasToken(owner: "acme", repository: "blog"))
        let loaded = try store.load(owner: "acme", repository: "blog")
        XCTAssertEqual(loaded?.copyBytes(), Array("gho_secret".utf8))

        // Other repos are untouched.
        XCTAssertNil(try store.load(owner: "acme", repository: "other"))

        try store.delete(owner: "acme", repository: "blog")
        XCTAssertFalse(store.hasToken(owner: "acme", repository: "blog"))
        XCTAssertNil(try store.load(owner: "acme", repository: "blog"))
    }

    func testSaveOverwritesExistingToken() throws {
        let store = GithubTokenStore(keychain: MockKeychainStore(), service: "test.service")

        try store.save(SecureBuffer(utf8String: "gho_old"), owner: "acme", repository: "blog")
        try store.save(SecureBuffer(utf8String: "gho_new"), owner: "acme", repository: "blog")

        XCTAssertEqual(
            try store.load(owner: "acme", repository: "blog")?.copyBytes(),
            Array("gho_new".utf8)
        )
    }

    func testAccountMatchesGithubSourceTokenAccount() throws {
        let keychain = MockKeychainStore()
        let store = GithubTokenStore(keychain: keychain, service: "svc")

        try store.save(SecureBuffer(utf8String: "gho_t"), owner: "acme", repository: "blog")

        // The Keychain account is `github:<owner>/<repo>` — the same
        // account `GithubSource.tokenAccount` names.
        XCTAssertNotNil(keychain.storage["svc:github:acme/blog"])
        let source = GithubSource(
            id: SourceID(),
            title: "acme/blog",
            owner: "acme",
            repository: "blog",
            defaultBranch: "main",
            bookmarkData: Data([1, 2, 3]),
            displayPath: "/tmp/blog",
            grantedScopes: ["repo"]
        )
        XCTAssertEqual(source.tokenAccount, "github:acme/blog")
    }
}
