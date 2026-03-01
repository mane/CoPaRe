import CryptoKit
import Foundation
import OSLog

actor EncryptedHistoryStore {
    private struct Envelope: Codable {
        let version: Int
        let nonce: Data
        let ciphertext: Data
        let tag: Data
        let savedAt: Date
    }

    private let fileManager: FileManager
    private let fileURL: URL
    private let keyProvider: KeychainKeyProvider
    private let logger = Logger(subsystem: "io.copare.app", category: "storage")

    init(fileManager: FileManager = .default, keyProvider: KeychainKeyProvider = KeychainKeyProvider()) {
        self.fileManager = fileManager
        self.keyProvider = keyProvider

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("CoPaRe", isDirectory: true)
        fileURL = directory.appendingPathComponent("clipboard-history.enc", isDirectory: false)
    }

    func loadHistory() -> [ClipboardHistoryItem] {
        do {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return []
            }

            let encryptedData = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder().decode(Envelope.self, from: encryptedData)
            let nonce = try AES.GCM.Nonce(data: envelope.nonce)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: envelope.ciphertext, tag: envelope.tag)
            let key = try keyProvider.loadOrCreateKey()
            let decrypted = try AES.GCM.open(box, using: key)

            return try JSONDecoder().decode([ClipboardHistoryItem].self, from: decrypted)
        } catch {
            logger.error("Failed to load encrypted history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func saveHistory(_ items: [ClipboardHistoryItem]) {
        do {
            try ensureStorageDirectory()

            let payload = try JSONEncoder().encode(items)
            let key = try keyProvider.loadOrCreateKey()
            let sealed = try AES.GCM.seal(payload, using: key)

            let nonceData = sealed.nonce.withUnsafeBytes { Data($0) }
            let envelope = Envelope(
                version: 1,
                nonce: nonceData,
                ciphertext: sealed.ciphertext,
                tag: sealed.tag,
                savedAt: Date()
            )

            let data = try JSONEncoder().encode(envelope)
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            logger.error("Failed to save encrypted history: \(error.localizedDescription, privacy: .public)")
        }
    }

    func replaceHistory(_ items: [ClipboardHistoryItem], rotateKey: Bool = false) {
        if rotateKey {
            clearHistoryFile(resetKey: true)
        }

        guard !items.isEmpty else {
            return
        }

        saveHistory(items)
    }

    func clearHistoryFile(resetKey: Bool = false) {
        do {
            guard fileManager.fileExists(atPath: fileURL.path) else {
                if resetKey {
                    try keyProvider.deleteKey()
                }
                return
            }

            let fileSize = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
            if fileSize > 0 {
                let zeroes = Data(repeating: 0, count: fileSize)
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    try handle.truncate(atOffset: 0)
                    try handle.write(contentsOf: zeroes)
                    if #available(macOS 10.15.4, *) {
                        try handle.synchronize()
                    } else {
                        handle.synchronizeFile()
                    }
                    try handle.close()
                }
            }

            try fileManager.removeItem(at: fileURL)

            if resetKey {
                try keyProvider.deleteKey()
            }
        } catch {
            logger.error("Failed to clear encrypted history file: \(error.localizedDescription, privacy: .public)")
        }
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
}
