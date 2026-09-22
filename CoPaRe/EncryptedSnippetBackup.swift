import CommonCrypto
import CryptoKit
import Foundation
import Security

nonisolated enum EncryptedSnippetBackupError: LocalizedError, Equatable {
    case passwordTooShort
    case passwordTooLong
    case invalidBackup
    case unsupportedVersion(Int)
    case authenticationFailed
    case fileTooLarge
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            return "Use a backup password with at least 12 characters."
        case .passwordTooLong:
            return "The backup password is too long. Use 4,096 UTF-8 bytes or fewer."
        case .invalidBackup:
            return "This file is not a supported encrypted CoPaRe backup."
        case let .unsupportedVersion(version):
            return "Encrypted backup version \(version) is not supported by this version of CoPaRe."
        case .authenticationFailed:
            return "The password is incorrect or the backup has been modified or damaged."
        case .fileTooLarge:
            return "Encrypted backup files must be 14 MB or smaller, containing at most 10 MB of snippet data."
        case .encryptionFailed:
            return "The encrypted backup could not be created. Please try again."
        }
    }
}

/// A portable password-derived vault. Only encrypted bytes ever go to disk;
/// the password and derived key are never stored in preferences or Keychain.
nonisolated enum EncryptedSnippetBackup {
    static let maximumFileBytes = 14_000_000
    static let minimumPasswordCharacters = 12
    static let maximumPasswordBytes = 4_096
    static let iterations = 600_000
    static let maximumIterations = 2_000_000

    private static let format = "CoPaRe encrypted snippets"
    private static let kdf = "PBKDF2-HMAC-SHA256"
    private static let cipher = "AES-256-GCM"

    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    fileprivate struct Envelope: Codable, Sendable {
        let format: String
        let version: Int
        let kdf: String
        let cipher: String
        let iterations: Int
        let salt: Data
        let sealed: Data

        var authenticatedMetadata: Data {
            Data("\(format)\n\(version)\n\(kdf)\n\(cipher)\n\(iterations)\n\(salt.base64EncodedString())".utf8)
        }
    }

    struct EncryptionContext: Sendable {
        fileprivate let key: SymmetricKey
        fileprivate let metadata: Envelope
    }

    struct DecryptionContext: Sendable {
        fileprivate let key: SymmetricKey
        fileprivate let envelope: Envelope
    }

    static func encrypt(document: SnippetTransferDocument, password: String) throws -> Data {
        try encrypt(document: document, using: prepareEncryption(password: password))
    }

    /// Only password derivation runs in the background. Callers can validate
    /// lock/wipe state before exposing snippet plaintext to the short final step.
    static func prepareEncryption(password: String) throws -> EncryptionContext {
        guard password.count >= minimumPasswordCharacters else {
            throw EncryptedSnippetBackupError.passwordTooShort
        }
        try validatePasswordSize(password)
        try Task.checkCancellation()
        var salt = Data(count: 32)
        let randomStatus = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            throw EncryptedSnippetBackupError.encryptionFailed
        }

        let metadata = Envelope(format: format, version: 1, kdf: kdf, cipher: cipher, iterations: iterations, salt: salt, sealed: Data())
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        try Task.checkCancellation()
        return EncryptionContext(key: key, metadata: metadata)
    }

    static func encrypt(document: SnippetTransferDocument, using context: EncryptionContext) throws -> Data {
        try Task.checkCancellation()
        let plaintext = try SnippetTransfer.encode(document)
        let sealedBox = try AES.GCM.seal(plaintext, using: context.key, authenticating: context.metadata.authenticatedMetadata)
        guard let sealed = sealedBox.combined else {
            throw EncryptedSnippetBackupError.encryptionFailed
        }
        let envelope = Envelope(format: format, version: 1, kdf: kdf, cipher: cipher, iterations: iterations, salt: context.metadata.salt, sealed: sealed)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard data.count <= maximumFileBytes else {
            throw EncryptedSnippetBackupError.fileTooLarge
        }
        return data
    }

    static func decrypt(data: Data, password: String) throws -> SnippetTransferDocument {
        try decrypt(using: prepareDecryption(data: data, password: password))
    }

    /// The context retains only ciphertext and its derived key, never plaintext.
    static func prepareDecryption(data: Data, password: String) throws -> DecryptionContext {
        guard data.count <= maximumFileBytes else {
            throw EncryptedSnippetBackupError.fileTooLarge
        }
        try validatePasswordSize(password)
        try Task.checkCancellation()
        let envelope: Envelope
        do {
            let decoder = JSONDecoder()
            let header = try decoder.decode(Header.self, from: data)
            guard header.format == format else {
                throw EncryptedSnippetBackupError.invalidBackup
            }
            guard header.version == 1 else {
                throw EncryptedSnippetBackupError.unsupportedVersion(header.version)
            }
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch let error as EncryptedSnippetBackupError {
            throw error
        } catch {
            throw EncryptedSnippetBackupError.invalidBackup
        }

        // Validate untrusted parameters before entering the deliberately expensive KDF.
        guard envelope.kdf == kdf,
              envelope.cipher == cipher,
              (iterations...maximumIterations).contains(envelope.iterations),
              envelope.salt.count == 32,
              envelope.sealed.count >= 28,
              envelope.sealed.count <= SnippetTransfer.maximumFileBytes + 28
        else {
            throw EncryptedSnippetBackupError.invalidBackup
        }

        let key = try deriveKey(password: password, salt: envelope.salt, iterations: envelope.iterations)
        try Task.checkCancellation()
        return DecryptionContext(key: key, envelope: envelope)
    }

    static func decrypt(using context: DecryptionContext) throws -> SnippetTransferDocument {
        try Task.checkCancellation()
        let plaintext: Data
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: context.envelope.sealed)
            plaintext = try AES.GCM.open(sealedBox, using: context.key, authenticating: context.envelope.authenticatedMetadata)
        } catch {
            // Do not distinguish an incorrect password from authenticated-data corruption.
            throw EncryptedSnippetBackupError.authenticationFailed
        }
        return try SnippetTransfer.decode(plaintext)
    }

    static func read(from url: URL) throws -> Data {
        do {
            return try SnippetTransfer.readData(from: url, maximumBytes: maximumFileBytes)
        } catch SnippetTransferError.fileTooLarge {
            throw EncryptedSnippetBackupError.fileTooLarge
        }
    }

    static func write(data: Data, to url: URL) throws {
        guard data.count <= maximumFileBytes else {
            throw EncryptedSnippetBackupError.fileTooLarge
        }
        try SnippetTransfer.writeData(data, to: url)
    }

    private static func validatePasswordSize(_ password: String) throws {
        guard password.utf8.count <= maximumPasswordBytes else {
            throw EncryptedSnippetBackupError.passwordTooLong
        }
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        var passwordBytes = Array(password.utf8)
        // A non-null buffer also accommodates an empty password during restore.
        let passwordLength = passwordBytes.count
        passwordBytes.append(0)
        var derivedBytes = [UInt8](repeating: 0, count: 32)
        defer {
            passwordBytes.withUnsafeMutableBytes { _ = memset_s($0.baseAddress!, $0.count, 0, $0.count) }
            derivedBytes.withUnsafeMutableBytes { _ = memset_s($0.baseAddress!, $0.count, 0, $0.count) }
        }
        let status = passwordBytes.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                derivedBytes.withUnsafeMutableBytes { derivedBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress!.assumingMemoryBound(to: Int8.self),
                        passwordLength,
                        saltBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        derivedBuffer.count
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw EncryptedSnippetBackupError.encryptionFailed
        }
        return SymmetricKey(data: derivedBytes)
    }
}
