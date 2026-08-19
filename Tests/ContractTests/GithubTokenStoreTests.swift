import XCTest

final class GithubTokenStoreTests: XCTestCase {
    func testSaveLoadDelete() throws {
        let store = GithubTokenStore(keychain: MockKeychainStore(), service: "test.service")

        XCTAssertFalse(store.hasToken())
        try store.save(SecureBuffer(utf8String: "gho_secret"))

        XCTAssertTrue(store.hasToken())
        let loaded = try store.load()
        XCTAssertEqual(loaded?.copyBytes(), Array("gho_secret".utf8))

        try store.delete()
        XCTAssertFalse(store.hasToken())
        XCTAssertNil(try store.load())
    }

    func testSaveOverwritesExistingToken() throws {
        let store = GithubTokenStore(keychain: MockKeychainStore(), service: "test.service")

        try store.save(SecureBuffer(utf8String: "gho_old"))
        try store.save(SecureBuffer(utf8String: "gho_new"))

        XCTAssertEqual(try store.load()?.copyBytes(), Array("gho_new".utf8))
    }

    func testHostKeyedAccount() throws {
        let keychain = MockKeychainStore()
        let store = GithubTokenStore(keychain: keychain, service: "svc")

        try store.save(SecureBuffer(utf8String: "gho_t"))

        // Host-keyed, not per-repo: git omits the repo path from
        // credential-helper input, so a per-repo account could never be
        // looked up. One token serves every GitHub source.
        XCTAssertEqual(GithubTokenStore.account, "github")
        XCTAssertNotNil(keychain.storage["svc:github"])
    }
}
