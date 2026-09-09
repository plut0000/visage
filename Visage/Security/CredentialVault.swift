import Foundation
import CryptoKit
import LocalAuthentication

enum CredentialError: LocalizedError {
    case emptyPassword
    case sessionLocked
    case encryptionFailed
    case decryptionFailed
    case sessionKeyUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyPassword: return "Password cannot be empty."
        case .sessionLocked: return "Session is locked. Authenticate with Touch ID first."
        case .encryptionFailed: return "Encryption failed."
        case .decryptionFailed: return "Decryption failed. Stored data may be corrupted."
        case .sessionKeyUnavailable:
            return "The session key is missing, but encrypted data still exists. Remove the stored password in Settings to start over."
        }
    }
}

extension Notification.Name {
    static let visageSessionDidChange = Notification.Name("Visage.sessionDidChange")
}

enum CredentialVault {
    nonisolated private static let sessionKeyAccount = "sessionKey"
    nonisolated private static let passwordBlobAccount = "encryptedPassword"
    nonisolated private static let sessionLock = NSLock()
    nonisolated(unsafe) private static var _cachedKey: SymmetricKey?
    nonisolated(unsafe) private static var _lastActivityAt: Date?

    nonisolated static var isSessionUnlocked: Bool {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _cachedKey != nil
    }

    nonisolated static var lastActivityAt: Date? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _lastActivityAt
    }

    nonisolated private static func cachedKey() -> SymmetricKey? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _cachedKey
    }

    nonisolated private static func setCachedKey(_ key: SymmetricKey?) {
        sessionLock.lock()
        let changed = (key != nil) != (_cachedKey != nil)
        _cachedKey = key
        _lastActivityAt = key == nil ? nil : Date()
        sessionLock.unlock()
        guard changed else { return }
        NotificationCenter.default.post(name: .visageSessionDidChange, object: nil)
    }

    nonisolated private static func recordActivity() {
        sessionLock.lock()
        if _cachedKey != nil { _lastActivityAt = Date() }
        sessionLock.unlock()
    }

    nonisolated static func encrypt(_ plaintext: Data) throws -> Data {
        guard let key = cachedKey() else { throw CredentialError.sessionLocked }
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else { throw CredentialError.encryptionFailed }
            return combined
        } catch {
            throw CredentialError.encryptionFailed
        }
    }

    nonisolated static func decrypt(_ ciphertext: Data) throws -> Data {
        guard let key = cachedKey() else { throw CredentialError.sessionLocked }
        do {
            let sealed = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealed, using: key)
        } catch {
            throw CredentialError.decryptionFailed
        }
    }

    nonisolated static func hasStoredPassword() -> Bool {
        KeychainStore.exists(account: passwordBlobAccount)
    }

    nonisolated static var hasSessionEncryptedData: Bool {
        KeychainStore.exists(account: passwordBlobAccount) || FaceVault.exists
    }

    nonisolated static func unlockSession(reason: String) throws {
        if cachedKey() != nil { return }

        if KeychainStore.exists(account: sessionKeyAccount) {
            let context = LAContext()
            context.localizedReason = reason
            let data = try KeychainStore.read(account: sessionKeyAccount, context: context)
            setCachedKey(SymmetricKey(data: data))
            return
        }

        guard !hasSessionEncryptedData else {
            throw CredentialError.sessionKeyUnavailable
        }

        let key = SymmetricKey(size: .bits256)
        let access = try KeychainStore.makeUserPresenceAccessControl()
        try KeychainStore.save(
            account: sessionKeyAccount,
            data: key.withUnsafeBytes { Data($0) },
            accessControl: access
        )
        let readBack = LAContext()
        readBack.localizedReason = reason
        let data = try KeychainStore.read(account: sessionKeyAccount, context: readBack)
        setCachedKey(SymmetricKey(data: data))
    }

    nonisolated static func lockSession() {
        setCachedKey(nil)
    }

    nonisolated static func savePassword(_ passwordBytes: Data) throws {
        guard !passwordBytes.isEmpty else { throw CredentialError.emptyPassword }
        let combined = try encrypt(passwordBytes)
        try KeychainStore.save(account: passwordBlobAccount, data: combined)
    }

    nonisolated static func readPassword() throws -> Data {
        guard cachedKey() != nil else { throw CredentialError.sessionLocked }
        let ciphertext = try KeychainStore.read(account: passwordBlobAccount)
        let plaintext = try decrypt(ciphertext)
        recordActivity()
        return plaintext
    }

    nonisolated static func deletePassword() throws {
        try KeychainStore.delete(account: passwordBlobAccount)
        try KeychainStore.delete(account: sessionKeyAccount)
        setCachedKey(nil)
    }
}
