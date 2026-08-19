import Foundation

/// GitHub source token lifecycle (M15 / #179): Keychain persistence
/// only, wrapped in `SecureBuffer`; the token never touches
/// UserDefaults, plists, argv, env, or logs (zero-leak invariant).
///
/// The account is host-keyed (`"github"`), not per-repo: git omits the
/// repo `path` when it invokes credential helpers (probed against
/// CLT/Xcode git), so a per-repo account could never be looked up. One
/// device-flow token per GitHub user per OAuth client — the natural key
/// is the host. Multiple GitHub accounts are a v1 limitation.
struct GithubTokenStore: Sendable {
    /// Keychain account for the GitHub token.
    static let account = "github"

    let keychain: KeychainStoring
    let service: String

    init(keychain: KeychainStoring = KeychainStore(), service: String = KeychainStore.defaultService) {
        self.keychain = keychain
        self.service = service
    }

    func save(_ token: SecureBuffer) throws {
        try keychain.saveSecret(token, account: Self.account, service: service)
    }

    func load() throws -> SecureBuffer? {
        try keychain.loadSecret(account: Self.account, service: service)
    }

    func delete() throws {
        try keychain.deleteSecret(account: Self.account, service: service)
    }

    func hasToken() -> Bool {
        keychain.hasSecret(account: Self.account, service: service)
    }
}
