import Foundation

/// Protocol defining in-memory ephemeral secret storage.
public protocol EphemeralSecretStoring: Sendable {
    func storeSecret(_ secret: SecureBuffer, for target: String)
    func loadSecret(for target: String) -> SecureBuffer?
    func consumeSecret(for target: String) -> SecureBuffer?
    func deleteSecret(for target: String)
    func hasSecret(for target: String) -> Bool
    func wipeAll()
}

/// In-memory, thread-safe ephemeral secret store for publish sessions.
/// Secrets stored here are never written to disk or Keychain, and are wiped when the session ends.
public final class EphemeralSecretStore: EphemeralSecretStoring, @unchecked Sendable {
    private var secrets: [String: SecureBuffer] = [:]
    private let lock = NSLock()

    public init() {}

    deinit {
        wipeAll()
    }

    public func storeSecret(_ secret: SecureBuffer, for target: String) {
        lock.lock()
        defer { lock.unlock() }
        // If an existing secret exists for this target, wipe it before replacing
        secrets[target]?.wipe()
        secrets[target] = secret
    }

    public func loadSecret(for target: String) -> SecureBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return secrets[target]
    }

    public func consumeSecret(for target: String) -> SecureBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return secrets.removeValue(forKey: target)
    }

    public func deleteSecret(for target: String) {
        lock.lock()
        defer { lock.unlock() }
        if let existing = secrets.removeValue(forKey: target) {
            existing.wipe()
        }
    }

    public func hasSecret(for target: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let secret = secrets[target] else { return false }
        return !secret.isEmpty
    }

    public func wipeAll() {
        lock.lock()
        defer { lock.unlock() }
        for (_, secret) in secrets {
            secret.wipe()
        }
        secrets.removeAll()
    }
}
