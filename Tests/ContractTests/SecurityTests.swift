import Foundation
import XCTest

final class MockKeychainStore: KeychainStoring, @unchecked Sendable {
    var storage: [String: [UInt8]] = [:]
    var throwError: KeychainError?

    func saveSecret(_ secret: SecureBuffer, account: String, service: String) throws {
        if let err = throwError { throw err }
        storage["\(service):\(account)"] = secret.copyBytes()
    }

    func loadSecret(account: String, service: String) throws -> SecureBuffer? {
        if let err = throwError { throw err }
        guard let bytes = storage["\(service):\(account)"] else { return nil }
        return SecureBuffer(bytes: bytes)
    }

    func deleteSecret(account: String, service: String) throws {
        if let err = throwError { throw err }
        storage.removeValue(forKey: "\(service):\(account)")
    }

    func hasSecret(account: String, service: String) -> Bool {
        storage["\(service):\(account)"] != nil
    }
}

final class SecurityTests: XCTestCase {

    // MARK: - SecureBuffer Tests

    func testSecureBufferLifecycleAndZeroing() {
        let secretText = "super-secret-password-xyz"
        let buffer = SecureBuffer(utf8String: secretText)

        XCTAssertFalse(buffer.isEmpty)
        XCTAssertEqual(buffer.count, secretText.utf8.count)

        // Verify description redaction
        XCTAssertFalse(buffer.description.contains(secretText))
        XCTAssertEqual(buffer.description, "<SecureBuffer count=\(secretText.utf8.count)>")
        XCTAssertEqual(buffer.debugDescription, "<SecureBuffer count=\(secretText.utf8.count)>")

        // Verify byte reading
        let bytes = buffer.copyBytes()
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), secretText)

        // Verify wipe
        buffer.wipe()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.copyBytes(), [])
    }

    func testEmptySecureBuffer() {
        let empty = SecureBuffer(bytes: [])
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.count, 0)
        XCTAssertEqual(empty.copyBytes(), [])
    }

    // MARK: - EphemeralSecretStore Tests

    func testEphemeralSecretStoreLifecycle() {
        let store = EphemeralSecretStore()
        let secret1 = SecureBuffer(utf8String: "nostr-nsec12345")
        let target = PublishTargets.nostr

        store.storeSecret(secret1, for: target)
        XCTAssertTrue(store.hasSecret(for: target))

        let retrieved = store.loadSecret(for: target)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.copyBytes(), Array("nostr-nsec12345".utf8))

        // Consume removes from store
        let consumed = store.consumeSecret(for: target)
        XCTAssertNotNil(consumed)
        XCTAssertFalse(store.hasSecret(for: target))
        XCTAssertNil(store.loadSecret(for: target))

        // Replace wipes old secret
        let secA = SecureBuffer(utf8String: "token-AAA")
        let secB = SecureBuffer(utf8String: "token-BBB")
        store.storeSecret(secA, for: PublishTargets.standardSite)
        store.storeSecret(secB, for: PublishTargets.standardSite)
        XCTAssertTrue(secA.isEmpty) // Previous was wiped
        XCTAssertFalse(secB.isEmpty)

        // WipeAll clears and wipes everything
        store.wipeAll()
        XCTAssertFalse(store.hasSecret(for: PublishTargets.standardSite))
        XCTAssertTrue(secB.isEmpty)
    }

    // MARK: - StdinSecretWriter Tests

    func testStdinSecretWriterStreamsToPipe() throws {
        let pipe = Pipe()
        let secret = SecureBuffer(utf8String: "nsec1secretpayload999")

        try StdinSecretWriter.writeSecret(
            secret,
            to: pipe.fileHandleForWriting,
            appendNewline: true,
            closeAfterWriting: true
        )

        let readData = pipe.fileHandleForReading.readDataToEndOfFile()
        let receivedText = String(decoding: readData, as: UTF8.self)
        XCTAssertEqual(receivedText, "nsec1secretpayload999\n")
    }

    func testStdinSecretWriterWriteAndWipe() throws {
        let pipe = Pipe()
        let secret = SecureBuffer(utf8String: "app-password-token-abc")

        try StdinSecretWriter.writeAndWipe(
            secret,
            to: pipe.fileHandleForWriting,
            appendNewline: false,
            closeAfterWriting: true
        )

        let readData = pipe.fileHandleForReading.readDataToEndOfFile()
        let receivedText = String(decoding: readData, as: UTF8.self)
        XCTAssertEqual(receivedText, "app-password-token-abc")

        // Assert that the source secret buffer was wiped
        XCTAssertTrue(secret.isEmpty)
        XCTAssertEqual(secret.count, 0)
    }

    func testStdinSecretWriterEmptyThrows() {
        let pipe = Pipe()
        let emptySecret = SecureBuffer(bytes: [])

        XCTAssertThrowsError(
            try StdinSecretWriter.writeSecret(emptySecret, to: pipe.fileHandleForWriting)
        ) { error in
            XCTAssertEqual(error as? StdinSecretWriterError, .emptySecret)
        }
    }

    // MARK: - PublishCredentialManager Tests

    func testPublishCredentialManagerRememberToggle() throws {
        let mockKeychain = MockKeychainStore()
        let mockEphemeral = EphemeralSecretStore()
        let manager = PublishCredentialManager(
            keychain: mockKeychain,
            ephemeral: mockEphemeral,
            service: "test.service"
        )

        let secret = SecureBuffer(utf8String: "nostr-privkey-demo")

        // 1. Remember in Keychain = true
        try manager.setCredential(secret, for: PublishTargets.nostr, rememberInKeychain: true)
        XCTAssertTrue(manager.isRemembered(for: PublishTargets.nostr))
        XCTAssertFalse(mockEphemeral.hasSecret(for: PublishTargets.nostr))

        let resolved = manager.provideSecret(for: PublishTargets.nostr)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.copyBytes(), Array("nostr-privkey-demo".utf8))

        // 2. Remember in Keychain = false (switch to ephemeral)
        let sessionSecret = SecureBuffer(utf8String: "session-only-token")
        try manager.setCredential(sessionSecret, for: PublishTargets.standardSite, rememberInKeychain: false)
        XCTAssertFalse(manager.isRemembered(for: PublishTargets.standardSite))
        XCTAssertTrue(mockEphemeral.hasSecret(for: PublishTargets.standardSite))

        let standardResolved = manager.provideSecret(for: PublishTargets.standardSite)
        XCTAssertNotNil(standardResolved)
        XCTAssertEqual(standardResolved?.copyBytes(), Array("session-only-token".utf8))

        // 3. Clear credential
        try manager.clearCredential(for: PublishTargets.nostr)
        XCTAssertFalse(manager.isRemembered(for: PublishTargets.nostr))
        XCTAssertNil(manager.provideSecret(for: PublishTargets.nostr))

        // 4. Wipe all ephemeral
        manager.wipeAllEphemeral()
        XCTAssertNil(manager.provideSecret(for: PublishTargets.standardSite))
    }
}
