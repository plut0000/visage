import Foundation

enum FaceVaultError: LocalizedError {
    case sessionLocked

    var errorDescription: String? {
        switch self {
        case .sessionLocked:
            return "Session is locked. Authenticate with Touch ID to access enrolled faces."
        }
    }
}

nonisolated enum FaceVault {
    private static let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("Visage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("face-identities.enc")
    }()

    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func load() throws -> [FaceIdentity] {
        guard CredentialVault.isSessionUnlocked else { throw FaceVaultError.sessionLocked }
        guard let ciphertext = try? Data(contentsOf: fileURL) else { return [] }
        let plaintext = try CredentialVault.decrypt(ciphertext)
        return try JSONDecoder().decode([FaceIdentity].self, from: plaintext)
    }

    static func save(_ identities: [FaceIdentity]) throws {
        guard CredentialVault.isSessionUnlocked else { throw FaceVaultError.sessionLocked }
        let plaintext = try JSONEncoder().encode(identities)
        let ciphertext = try CredentialVault.encrypt(plaintext)
        try ciphertext.write(to: fileURL, options: .atomic)
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
