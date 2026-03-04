import CryptoKit
import Foundation
import OSLog

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

        init(
            id: UUID,
            preview: String,
            body: String,
            createdAt: Date,
            updatedAt: Date,
            pinnedAt: Date?
        ) {
            self.id = id
            self.preview = preview
            self.body = body
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.pinnedAt = pinnedAt
        }
    }

    private static let snippetKeyService = "io.copare.app.snippets"
    private static let protectedSnippetKeyService = "io.copare.app.snippets.protected"

    private let fileManager: FileManager
    private let fileURL: URL
    private let logger = Logger(subsystem: "io.copare.app", category: "snippets")

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
        do {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return []
            }

            let storedData = try Data(contentsOf: fileURL)
            guard let envelope = try? JSONDecoder().decode(Envelope.self, from: storedData) else {
                logger.error("Rejected unencrypted or malformed legacy snippet store at \(self.fileURL.path, privacy: .public)")
                return nil
            }

            let nonce = try AES.GCM.Nonce(data: envelope.nonce)
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: envelope.ciphertext,
                tag: envelope.tag
            )
            let keyService = envelope.keyService ?? Self.snippetKeyService
            let key = try keyProvider(for: keyService).loadOrCreateKey()
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let snippets = try JSONDecoder().decode([PersistedSnippet].self, from: decryptedData)

            return snippets.compactMap(makeHistoryItem)
        } catch {
            logger.error("Failed to load snippets: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveSnippets(_ items: [ClipboardHistoryItem], requireUserPresence: Bool) {
        do {
            try ensureStorageDirectory()

            let snippets = items
                .filter { $0.isSnippet }
                .compactMap(makePersistedSnippet)

            if snippets.isEmpty {
                try removeSnippetFileIfPresent()
                deleteAllSnippetKeys()
                return
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
        } catch {
            logger.error("Failed to save snippets: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearSnippetsFile() {
        do {
            defer {
                deleteAllSnippetKeys()
            }

            guard fileManager.fileExists(atPath: fileURL.path) else {
                return
            }

            try fileManager.removeItem(at: fileURL)
        } catch {
            logger.error("Failed to clear snippets file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeHistoryItem(from snippet: PersistedSnippet) -> ClipboardHistoryItem? {
        let payload = ClipboardItemPayload(
            plainText: snippet.body,
            imagePNGData: nil,
            filePaths: nil
        )

        guard let runtimePayload = try? EncryptedClipboardPayload.seal(payload) else {
            return nil
        }

        return ClipboardHistoryItem(
            id: snippet.id,
            type: .text,
            createdAt: snippet.createdAt,
            updatedAt: snippet.updatedAt,
            pinnedAt: snippet.pinnedAt,
            expiresAt: nil,
            preview: snippet.preview,
            searchIndex: String(snippet.preview.prefix(120)),
            thumbnailPNGData: nil,
            encryptedPayload: runtimePayload,
            digest: digest(for: "snippet:\(snippet.preview)\n\(snippet.body)"),
            byteSize: Data(snippet.body.utf8).count,
            origin: .snippet,
            captureCount: 1,
            sourceBundleIdentifier: nil
        )
    }

    private func makePersistedSnippet(from item: ClipboardHistoryItem) -> PersistedSnippet? {
        guard let payload = item.decryptedPayload(),
              let plainText = payload.plainText
        else {
            return nil
        }

        return PersistedSnippet(
            id: item.id,
            preview: item.preview,
            body: plainText,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            pinnedAt: item.pinnedAt
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

    private func digest(for text: String) -> String {
        let hash = SHA256.hash(data: Data(text.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
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

    private func deleteAllSnippetKeys() {
        deleteSnippetKeyIfPresent(service: Self.snippetKeyService)
        deleteSnippetKeyIfPresent(service: Self.protectedSnippetKeyService)
    }

    private func deleteSnippetKeyIfPresent(service: String) {
        do {
            try keyProvider(for: service).deleteKey()
        } catch {
            logger.error("Failed to delete snippet encryption key for \(service, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
