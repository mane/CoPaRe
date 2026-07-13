import CryptoKit
import Foundation
import OSLog

struct SnippetPersistenceRecord: Equatable, Sendable {
    let id: UUID
    let preview: String
    let body: String
    let createdAt: Date
    let updatedAt: Date
    let pinnedAt: Date?
    let tags: [String]

    nonisolated var digest: String {
        let normalizedTags = ClipboardHistoryItem.normalizedTags(tags)
        let value = "snippet:\(preview)\n\(body)\n\(normalizedTags.joined(separator: ","))"
        let hash = SHA256.hash(data: Data(value.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

actor SnippetStore {
    private struct Envelope: Codable {
        let version: Int
        let keyService: String?
        let nonce: Data
        let ciphertext: Data
        let tag: Data
        let savedAt: Date
    }

    private struct PersistedSnippet: Codable {
        let id: UUID
        let preview: String
        let body: String
        let createdAt: Date
        let updatedAt: Date
        let pinnedAt: Date?
        let tags: [String]

        private enum CodingKeys: String, CodingKey {
            case id
            case preview
            case body
            case createdAt
            case updatedAt
            case pinnedAt
            case tags
        }

        init(
            id: UUID,
            preview: String,
            body: String,
            createdAt: Date,
            updatedAt: Date,
            pinnedAt: Date?,
            tags: [String]
        ) {
            self.id = id
            self.preview = preview
            self.body = body
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.pinnedAt = pinnedAt
            self.tags = ClipboardHistoryItem.normalizedTags(tags)
        }

        init(record: SnippetPersistenceRecord) {
            self.init(
                id: record.id,
                preview: record.preview,
                body: record.body,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                pinnedAt: record.pinnedAt,
                tags: record.tags
            )
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            preview = try container.decode(String.self, forKey: .preview)
            body = try container.decode(String.self, forKey: .body)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
            tags = ClipboardHistoryItem.normalizedTags(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        }

        var record: SnippetPersistenceRecord {
            SnippetPersistenceRecord(
                id: id,
                preview: preview,
                body: body,
                createdAt: createdAt,
                updatedAt: updatedAt,
                pinnedAt: pinnedAt,
                tags: tags
            )
        }
    }

    private static let snippetKeyService = "io.copare.app.snippets"
    private static let protectedSnippetKeyService = "io.copare.app.snippets.protected"

    private let fileManager: FileManager
    private let fileURL: URL
    private let logger = Logger(subsystem: "io.copare.app", category: "snippets")
    private var operationGeneration = 0

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("CoPaRe", isDirectory: true)
        fileURL = directory.appendingPathComponent("snippets.json", isDirectory: false)
    }

    func hasSavedSnippets() -> Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    func loadSnippets() -> [ClipboardHistoryItem]? {
        guard let records = loadSnippetRecords() else {
            return nil
        }

        var items: [ClipboardHistoryItem] = []
        items.reserveCapacity(records.count)
        for record in records {
            guard let item = makeHistoryItem(from: record) else {
                logger.error("Failed to convert a persisted snippet into encrypted runtime state")
                return nil
            }
            items.append(item)
        }
        return items
    }

    func loadSnippetRecords() -> [SnippetPersistenceRecord]? {
        do {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return []
            }

            let storedData = try Data(contentsOf: fileURL)
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: storedData) else {
                logger.error("Rejected unencrypted or malformed legacy snippet store at \(self.fileURL.path, privacy: .public)")
                return nil
            }

            guard envelope.version == 1 else {
                logger.error("Rejected unsupported snippet store version \(envelope.version, privacy: .public)")
                return nil
            }

            let nonce = try AES.GCM.Nonce(data: envelope.nonce)
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: envelope.ciphertext,
                tag: envelope.tag
            )
            let keyService = envelope.keyService ?? Self.snippetKeyService
            guard keyService == Self.snippetKeyService || keyService == Self.protectedSnippetKeyService else {
                logger.error("Rejected snippet store with an unknown key service")
                return nil
            }
            let key = try keyProvider(for: keyService).loadOrCreateKey()
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let snippets = try JSONDecoder().decode([PersistedSnippet].self, from: decryptedData)

            return snippets.map(\.record)
        } catch {
            logger.error("Failed to load snippets: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func saveSnippets(
        _ records: [SnippetPersistenceRecord],
        requireUserPresence: Bool,
        generation: Int
    ) -> Bool {
        guard generation > operationGeneration else {
            return false
        }
        operationGeneration = generation

        do {
            try ensureStorageDirectory()

            let snippets = records.map(PersistedSnippet.init(record:))

            if snippets.isEmpty {
                try removeSnippetFileIfPresent()
                let keysDeleted = deleteAllSnippetKeys()
                if !keysDeleted {
                    logger.error("Snippet key cleanup reported failures after removing empty snippet file")
                }
                return keysDeleted
            }

            let payload = try JSONEncoder().encode(snippets)
            let keyService = snippetKeyService(for: requireUserPresence)
            let key = try keyProvider(for: keyService).loadOrCreateKey()
            let sealed = try AES.GCM.seal(payload, using: key)
            let envelope = Envelope(
                version: 1,
                keyService: keyService,
                nonce: sealed.nonce.withUnsafeBytes { Data($0) },
                ciphertext: sealed.ciphertext,
                tag: sealed.tag,
                savedAt: Date()
            )

            let data = try JSONEncoder().encode(envelope)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            logger.error("Failed to save snippets: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    func clearSnippetsFile(generation: Int) -> Bool {
        guard generation > operationGeneration else {
            return false
        }
        operationGeneration = generation

        var succeeded = true

        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            logger.error("Failed to clear snippets file: \(error.localizedDescription, privacy: .public)")
            succeeded = false
        }

        let keysDeleted = deleteAllSnippetKeys()
        return succeeded && keysDeleted
    }

    private func makeHistoryItem(from snippet: SnippetPersistenceRecord) -> ClipboardHistoryItem? {
        let payload = ClipboardItemPayload(
            plainText: snippet.body,
            imagePNGData: nil,
            filePaths: nil
        )

        guard let runtimePayload = try? EncryptedClipboardPayload.seal(payload) else {
            return nil
        }

        let searchTerms = ([snippet.preview] + snippet.tags.map { "#\($0)" })
            .joined(separator: " ")
            .condensingWhitespace()

        return ClipboardHistoryItem(
            id: snippet.id,
            type: .text,
            createdAt: snippet.createdAt,
            updatedAt: snippet.updatedAt,
            pinnedAt: snippet.pinnedAt,
            expiresAt: nil,
            preview: snippet.preview,
            searchIndex: String(searchTerms.prefix(160)),
            thumbnailPNGData: nil,
            encryptedPayload: runtimePayload,
            digest: snippet.digest,
            byteSize: Data(snippet.body.utf8).count,
            origin: .snippet,
            captureCount: 1,
            sourceBundleIdentifier: nil,
            tags: snippet.tags
        )
    }

    private func ensureStorageDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    private func removeSnippetFileIfPresent() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }

    private func snippetKeyService(for requireUserPresence: Bool) -> String {
        requireUserPresence ? Self.protectedSnippetKeyService : Self.snippetKeyService
    }

    private func keyProvider(for service: String) -> KeychainKeyProvider {
        KeychainKeyProvider(
            service: service,
            requiresUserPresence: service == Self.protectedSnippetKeyService
        )
    }

    private func deleteAllSnippetKeys() -> Bool {
        let regularDeleted = deleteSnippetKeyIfPresent(service: Self.snippetKeyService)
        let protectedDeleted = deleteSnippetKeyIfPresent(service: Self.protectedSnippetKeyService)
        return regularDeleted && protectedDeleted
    }

    private func deleteSnippetKeyIfPresent(service: String) -> Bool {
        do {
            try keyProvider(for: service).deleteKey()
            return true
        } catch {
            logger.error("Failed to delete snippet encryption key for \(service, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
