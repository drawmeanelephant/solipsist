import Foundation

/// Unified manager handling the lifecycle of publishing credentials between
/// macOS Keychain (for persistent storage) and EphemeralSecretStore (for session-only memory).
public final class PublishCredentialManager: SecretProviding, @unchecked Sendable {
    public let keychain: KeychainStoring
    public let ephemeral: EphemeralSecretStoring
    public let service: String

    public init(
        keychain: KeychainStoring = KeychainStore(),
        ephemeral: EphemeralSecretStoring = EphemeralSecretStore(),
        service: String = KeychainStore.defaultService
    ) {
        self.keychain = keychain
        self.ephemeral = ephemeral
        self.service = service
    }

    /// Sets the credential for a publishing target.
    ///
    /// - Parameters:
    ///   - secret: The secret buffer.
    ///   - target: The publishing target identifier (e.g. `PublishTargets.standardSite` or `PublishTargets.nostr`).
    ///   - rememberInKeychain: If `true`, saves into macOS Keychain. If `false`, stores in-memory only and deletes any prior Keychain item.
    public func setCredential(
        _ secret: SecureBuffer,
        for target: String,
        rememberInKeychain: Bool
    ) throws {
        if rememberInKeychain {
            ephemeral.deleteSecret(for: target)
            try keychain.saveSecret(secret, account: target, service: service)
        } else {
            try? keychain.deleteSecret(account: target, service: service)
            ephemeral.storeSecret(secret, for: target)
        }
    }

    /// Retrieves the secret for the target, checking ephemeral memory first, then Keychain.
    public func provideSecret(for target: String) -> SecureBuffer? {
        if let ephemeralSecret = ephemeral.loadSecret(for: target) {
            return ephemeralSecret
        }
        if let keychainSecret = try? keychain.loadSecret(account: target, service: service) {
            return keychainSecret
        }
        return nil
    }

    /// Checks if a credential is saved in the macOS Keychain for the target.
    public func isRemembered(for target: String) -> Bool {
        keychain.hasSecret(account: target, service: service)
    }

    /// Clears any credential stored in both ephemeral memory and Keychain for the target.
    public func clearCredential(for target: String) throws {
        ephemeral.deleteSecret(for: target)
        try keychain.deleteSecret(account: target, service: service)
    }

    /// Clears all session secrets from memory.
    public func wipeAllEphemeral() {
        ephemeral.wipeAll()
    }
}
