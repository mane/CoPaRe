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

    var isEmpty: Bool {
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

    init(version: Int, keyService: String?, nonce: Data, ciphertext: Data, tag: Data) {
        self.version = version
        self.keyService = keyService
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        keyService = try container.decodeIfPresent(String.self, forKey: .keyService)
        nonce = try container.decode(Data.self, forKey: .nonce)
        ciphertext = try container.decode(Data.self, forKey: .ciphertext)
        tag = try container.decode(Data.self, forKey: .tag)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(keyService, forKey: .keyService)
        try container.encode(nonce, forKey: .nonce)
        try container.encode(ciphertext, forKey: .ciphertext)
        try container.encode(tag, forKey: .tag)
    }

    static func seal(_ payload: ClipboardItemPayload) throws -> EncryptedClipboardPayload {
        try ClipboardPayloadProtector.sealInSession(payload)
    }

    func open() throws -> ClipboardItemPayload {
        try ClipboardPayloadProtector.open(self)
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
    let searchIndex: String?
    let thumbnailPNGData: Data?
    let encryptedPayload: EncryptedClipboardPayload?
    let digest: String
    let byteSize: Int
    let origin: ClipboardItemOrigin
    var captureCount: Int
    let sourceBundleIdentifier: String?

    var isPinned: Bool {
        pinnedAt != nil
    }

    var isSnippet: Bool {
        origin == .snippet
    }

    init(
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

    func decryptedPayload() -> ClipboardItemPayload? {
        guard let encryptedPayload else {
            return nil
        }
        return try? encryptedPayload.open()
    }

    static func makeThumbnailPNGData(from imageData: Data?) -> Data? {
        guard let imageData, let image = NSImage(data: imageData) else {
            return nil
        }

        return image.copareThumbnailPNGData(maxDimension: 96)
    }

    static func makeSearchIndex(for type: ClipboardItemType, preview: String) -> String? {
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
    private nonisolated(unsafe) static let sessionKey = SymmetricKey(size: .bits256)

    static func sealInSession(_ payload: ClipboardItemPayload) throws -> EncryptedClipboardPayload {
        let data = try JSONEncoder().encode(payload)
        let sealedBox = try AES.GCM.seal(data, using: sessionKey)

        return EncryptedClipboardPayload(
            version: 1,
            keyService: nil,
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    static func open(_ encryptedPayload: EncryptedClipboardPayload) throws -> ClipboardItemPayload {
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
            decryptedData = try AES.GCM.open(sealedBox, using: sessionKey)
        }
        return try JSONDecoder().decode(ClipboardItemPayload.self, from: decryptedData)
    }
}

private extension NSImage {
    func copareThumbnailPNGData(maxDimension: CGFloat) -> Data? {
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
