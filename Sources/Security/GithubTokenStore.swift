import Foundation

/// GitHub source token lifecycle (M15 / #179): Keychain persistence
/// only, wrapped in `SecureBuffer`. The account
/// `github:<owner>/<repo>` matches `GithubSource.tokenAccount`; the
/// token never touches UserDefaults, plists, argv, env, or logs
/// (zero-leak invariant).
struct GithubTokenStore: Sendable {
    let keychain: KeychainStoring
    let service: String

    init(keychain: KeychainStoring = KeychainStore(), service: String = KeychainStore.defaultService) {
        self.keychain = keychain
        self.service = service
    }

    func save(_ token: SecureBuffer, owner: String, repository: String) throws {
        try keychain.saveSecret(token, account: account(owner: owner, repository: repository), service: service)
    }

    func load(owner: String, repository: String) throws -> SecureBuffer? {
        try keychain.loadSecret(account: account(owner: owner, repository: repository), service: service)
    }

    func delete(owner: String, repository: String) throws {
        try keychain.deleteSecret(account: account(owner: owner, repository: repository), service: service)
    }

    func hasToken(owner: String, repository: String) -> Bool {
        keychain.hasSecret(account: account(owner: owner, repository: repository), service: service)
    }

    private func account(owner: String, repository: String) -> String {
        "github:\(owner)/\(repository)"
    }
}
