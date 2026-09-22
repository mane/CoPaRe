import CryptoKit
import Foundation

nonisolated enum SnippetCheckpointError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidCheckpoint
    case unsupportedVersion(Int)
    case authenticationFailed
    case readFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "Pending snippet changes exceed the 64 MB recovery-file limit."
        case .invalidCheckpoint:
            return "The pending snippet recovery file is damaged."
        case let .unsupportedVersion(version):
            return "Pending snippet recovery version \(version) is not supported."
        case .authenticationFailed:
            return "Pending snippet changes could not be decrypted. The recovery file was kept."
        case .readFailed:
            return "Pending snippet changes could not be read."
        case .writeFailed:
            return "Pending snippet changes could not be saved safely."
        }
    }
}

/// Stores only pending user-authored snippets and deletion markers. The caller
/// supplies its authenticated lock key; captured clipboard history is excluded
/// by the record type and is never written to this recovery file.
nonisolated struct SnippetCheckpointStore: Sendable {
    struct Checkpoint: Codable, Equatable, Sendable {
        let records: [SnippetPersistenceRecord]
        let deletedIDs: Set<UUID>
    }

    private struct Header: Decodable {
        let version: Int
    }

    private struct Envelope: Codable {
        let version: Int
        let sealed: Data
    }

    static let maximumFileBytes = 64_000_000
    private static let authenticatedMetadata = Data("CoPaRe pending user snippets\n1".utf8)
    let fileURL: URL

    init(fileURL: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileURL = fileURL ?? appSupport
            .appendingPathComponent("CoPaRe", isDirectory: true)
            .appendingPathComponent("snippets-pending.json", isDirectory: false)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    func save(records: [SnippetPersistenceRecord], deletedIDs: Set<UUID>, using key: SymmetricKey) throws {
        do {
            let checkpoint = Checkpoint(records: records, deletedIDs: deletedIDs)
            let plaintext = try JSONEncoder().encode(checkpoint)
            guard plaintext.count <= Self.maximumFileBytes else {
                throw SnippetCheckpointError.fileTooLarge
            }
            let sealedBox = try AES.GCM.seal(plaintext, using: key, authenticating: Self.authenticatedMetadata)
            guard let sealed = sealedBox.combined else {
                throw SnippetCheckpointError.writeFailed
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let data = try encoder.encode(Envelope(version: 1, sealed: sealed))
            guard data.count <= Self.maximumFileBytes else {
                throw SnippetCheckpointError.fileTooLarge
            }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch let error as SnippetCheckpointError {
            throw error
        } catch {
            throw SnippetCheckpointError.writeFailed
        }
    }

    func load(using key: SymmetricKey) throws -> Checkpoint? {
        guard exists else { return nil }
        let data: Data
        do {
            data = try SnippetTransfer.readData(from: fileURL, maximumBytes: Self.maximumFileBytes)
        } catch SnippetTransferError.fileTooLarge {
            throw SnippetCheckpointError.fileTooLarge
        } catch {
            throw SnippetCheckpointError.readFailed
        }

        let envelope: Envelope
        do {
            let decoder = JSONDecoder()
            let header = try decoder.decode(Header.self, from: data)
            guard header.version == 1 else {
                throw SnippetCheckpointError.unsupportedVersion(header.version)
            }
            envelope = try decoder.decode(Envelope.self, from: data)
            guard envelope.sealed.count >= 28 else {
                throw SnippetCheckpointError.invalidCheckpoint
            }
        } catch let error as SnippetCheckpointError {
            throw error
        } catch {
            throw SnippetCheckpointError.invalidCheckpoint
        }

        let plaintext: Data
        do {
            let sealed = try AES.GCM.SealedBox(combined: envelope.sealed)
            plaintext = try AES.GCM.open(sealed, using: key, authenticating: Self.authenticatedMetadata)
        } catch {
            throw SnippetCheckpointError.authenticationFailed
        }
        do {
            return try JSONDecoder().decode(Checkpoint.self, from: plaintext)
        } catch {
            throw SnippetCheckpointError.invalidCheckpoint
        }
    }

    func clear() throws {
        guard exists else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
