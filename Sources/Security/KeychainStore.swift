import Foundation
import Security

/// Errors encountered during macOS Keychain operations.
public enum KeychainError: Error, Equatable, Sendable {
    case duplicateItem
    case itemNotFound
    case unhandledError(status: OSStatus)
    case unexpectedDataFormat
}

/// Protocol defining macOS Keychain storage operations for publish credentials.
public protocol KeychainStoring: Sendable {
    func saveSecret(_ secret: SecureBuffer, account: String, service: String) throws
    func loadSecret(account: String, service: String) throws -> SecureBuffer?
    func deleteSecret(account: String, service: String) throws
    func hasSecret(account: String, service: String) -> Bool
}

extension KeychainStoring {
    public func saveSecret(_ secret: SecureBuffer, account: String) throws {
        try saveSecret(secret, account: account, service: KeychainStore.defaultService)
    }

    public func loadSecret(account: String) throws -> SecureBuffer? {
        try loadSecret(account: account, service: KeychainStore.defaultService)
    }

    public func deleteSecret(account: String) throws {
        try deleteSecret(account: account, service: KeychainStore.defaultService)
    }

    public func hasSecret(account: String) -> Bool {
        hasSecret(account: account, service: KeychainStore.defaultService)
    }
}

/// Production Keychain store using `kSecClassGenericPassword`.
public final class KeychainStore: KeychainStoring {
    public static let defaultService = "dev.drawmeanelephant.solipsist"

    public let defaultTargetService: String

    public init(defaultTargetService: String = KeychainStore.defaultService) {
        self.defaultTargetService = defaultTargetService
    }

    public func saveSecret(_ secret: SecureBuffer, account: String, service: String) throws {
        let secretData: Data = secret.withUnsafeBytes { raw in
            Data(raw)
        } ?? Data()

        // Check if item already exists
        if hasSecret(account: account, service: service) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: secretData,
            ]
            let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.unhandledError(status: status)
            }
        } else {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: secretData,
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                if status == errSecDuplicateItem {
                    throw KeychainError.duplicateItem
                }
                throw KeychainError.unhandledError(status: status)
            }
        }
    }

    public func loadSecret(account: String, service: String) throws -> SecureBuffer? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status != errSecItemNotFound else {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
        guard let data = item as? Data else {
            throw KeychainError.unexpectedDataFormat
        }

        return SecureBuffer(data: data)
    }

    public func deleteSecret(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    public func hasSecret(account: String, service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
