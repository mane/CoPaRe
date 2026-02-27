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

struct ClipboardHistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    let type: ClipboardItemType
    let createdAt: Date
    var pinnedAt: Date?
    let preview: String
    let plainText: String?
    let imagePNGData: Data?
    let filePaths: [String]?
    let digest: String
    let byteSize: Int
    let sourceBundleIdentifier: String?

    var isPinned: Bool {
        pinnedAt != nil
    }

    init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        createdAt: Date = Date(),
        pinnedAt: Date? = nil,
        preview: String,
        plainText: String? = nil,
        imagePNGData: Data? = nil,
        filePaths: [String]? = nil,
        digest: String,
        byteSize: Int,
        sourceBundleIdentifier: String?
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.pinnedAt = pinnedAt
        self.preview = preview
        self.plainText = plainText
        self.imagePNGData = imagePNGData
        self.filePaths = filePaths
        self.digest = digest
        self.byteSize = byteSize
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }
}
