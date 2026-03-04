import AppKit
import CryptoKit
import Foundation

enum ClipboardItemType: String, Codable, CaseIterable, Identifiable {
    case text
    case url
    case image
    case file

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text:
            return "Text"
        case .url:
            return "URL"
        case .image:
            return "Image"
        case .file:
            return "File"
        }
    }

    var symbolName: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .url:
            return "link"
        case .image:
            return "photo"
        case .file:
            return "doc"
        }
    }
}

enum ClipboardItemOrigin: String, Codable {
    case captured
    case snippet

    var label: String {
        switch self {
        case .captured:
            return "History"
        case .snippet:
            return "Snippet"
        }
    }
}

struct ClipboardItemPayload: Codable, Hashable {
    let plainText: String?
    let imagePNGData: Data?
    let filePaths: [String]?

    private enum CodingKeys: String, CodingKey {
        case plainText
        case imagePNGData
        case filePaths
    }

    nonisolated init(plainText: String?, imagePNGData: Data?, filePaths: [String]?) {
        self.plainText = plainText
        self.imagePNGData = imagePNGData
        self.filePaths = filePaths
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plainText = try container.decodeIfPresent(String.self, forKey: .plainText)
        imagePNGData = try container.decodeIfPresent(Data.self, forKey: .imagePNGData)
        filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(plainText, forKey: .plainText)
        try container.encodeIfPresent(imagePNGData, forKey: .imagePNGData)
        try container.encodeIfPresent(filePaths, forKey: .filePaths)
    }

    nonisolated var isEmpty: Bool {
        plainText == nil && imagePNGData == nil && (filePaths?.isEmpty ?? true)
    }
}

struct EncryptedClipboardPayload: Codable, Hashable {
    let version: Int
    let keyService: String?
    let nonce: Data
    let ciphertext: Data
    let tag: Data

    private enum CodingKeys: String, CodingKey {
        case version
        case keyService
        case nonce
        case ciphertext
        case tag
    }

    nonisolated init(version: Int, keyService: String?, nonce: Data, ciphertext: Data, tag: Data) {
        self.version = version
        self.keyService = keyService
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        keyService = try container.decodeIfPresent(String.self, forKey: .keyService)
        nonce = try container.decode(Data.self, forKey: .nonce)
        ciphertext = try container.decode(Data.self, forKey: .ciphertext)
        tag = try container.decode(Data.self, forKey: .tag)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(keyService, forKey: .keyService)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(ciphertext, forKey: .ciphertext)
        try container.encode(tag, forKey: .tag)
    }

    nonisolated static func seal(_ payload: ClipboardItemPayload) throws -> EncryptedClipboardPayload {
        try ClipboardPayloadProtector.sealInSession(payload)
    }

    nonisolated func open() throws -> ClipboardItemPayload {
        try ClipboardPayloadProtector.open(self)
    }

    nonisolated static func rotateSessionProtectionKey() {
        ClipboardPayloadProtector.rotateSessionKey()
    }
}

struct ClipboardHistoryItem: Identifiable, Hashable {
    let id: UUID
    let type: ClipboardItemType
    let createdAt: Date
    var updatedAt: Date
    var pinnedAt: Date?
    var expiresAt: Date?
    let preview: String
    var searchIndex: String?
    let thumbnailPNGData: Data?
    let encryptedPayload: EncryptedClipboardPayload?
    let digest: String
    let byteSize: Int
    let origin: ClipboardItemOrigin
    var captureCount: Int
    let sourceBundleIdentifier: String?

    nonisolated var isPinned: Bool {
        pinnedAt != nil
    }

    nonisolated var isSnippet: Bool {
        origin == .snippet
    }

    nonisolated init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pinnedAt: Date? = nil,
        expiresAt: Date? = nil,
        preview: String,
        searchIndex: String? = nil,
        thumbnailPNGData: Data? = nil,
        encryptedPayload: EncryptedClipboardPayload? = nil,
        digest: String,
        byteSize: Int,
        origin: ClipboardItemOrigin = .captured,
        captureCount: Int = 1,
        sourceBundleIdentifier: String?
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinnedAt = pinnedAt
        self.expiresAt = expiresAt
        self.preview = preview
        self.searchIndex = searchIndex
        self.thumbnailPNGData = thumbnailPNGData
        self.encryptedPayload = encryptedPayload
        self.digest = digest
        self.byteSize = byteSize
        self.origin = origin
        self.captureCount = captureCount
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    nonisolated func decryptedPayload() -> ClipboardItemPayload? {
        guard let encryptedPayload else {
            return nil
        }
        return try? encryptedPayload.open()
    }

    nonisolated static func makeThumbnailPNGData(from imageData: Data?) -> Data? {
        guard let imageData, let image = NSImage(data: imageData) else {
            return nil
        }

        return image.copareThumbnailPNGData(maxDimension: 96)
    }

    nonisolated static func makeSearchIndex(for type: ClipboardItemType, preview: String) -> String? {
        guard type == .file else {
            return nil
        }

        let trimmed = preview.condensingWhitespace()
        guard !trimmed.isEmpty else {
            return nil
        }

        return String(trimmed.prefix(120))
    }
}

private enum ClipboardPayloadProtector {
    private nonisolated static let sessionKeyLock = NSLock()
    private nonisolated(unsafe) static var sessionKey = SymmetricKey(size: .bits256)

    nonisolated static func sealInSession(_ payload: ClipboardItemPayload) throws -> EncryptedClipboardPayload {
        let data = try JSONEncoder().encode(payload)
        let sealedBox = try AES.GCM.seal(data, using: currentSessionKey())

        return EncryptedClipboardPayload(
            version: 1,
            keyService: nil,
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    nonisolated static func open(_ encryptedPayload: EncryptedClipboardPayload) throws -> ClipboardItemPayload {
        let nonce = try AES.GCM.Nonce(data: encryptedPayload.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encryptedPayload.ciphertext,
            tag: encryptedPayload.tag
        )
        let decryptedData: Data
        if let keyService = encryptedPayload.keyService {
            let key = try KeychainKeyProvider(service: keyService).loadOrCreateKey()
            decryptedData = try AES.GCM.open(sealedBox, using: key)
        } else {
            decryptedData = try AES.GCM.open(sealedBox, using: currentSessionKey())
        }
        return try JSONDecoder().decode(ClipboardItemPayload.self, from: decryptedData)
    }

    nonisolated static func rotateSessionKey() {
        sessionKeyLock.lock()
        defer { sessionKeyLock.unlock() }
        sessionKey = SymmetricKey(size: .bits256)
    }

    private nonisolated static func currentSessionKey() -> SymmetricKey {
        sessionKeyLock.lock()
        defer { sessionKeyLock.unlock() }
        return sessionKey
    }
}

private extension NSImage {
    nonisolated func copareThumbnailPNGData(maxDimension: CGFloat) -> Data? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let ratio = min(maxDimension / size.width, maxDimension / size.height, 1)
        let targetSize = NSSize(
            width: max(1, size.width * ratio),
            height: max(1, size.height * ratio)
        )

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width.rounded(.up)),
            pixelsHigh: Int(targetSize.height.rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }
}
