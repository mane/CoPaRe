import AppKit
import Foundation
import Combine

enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case text
    case image
    case file

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "All"
        case .pinned:
            return "Pinned"
        case .text:
            return "Text"
        case .image:
            return "Images"
        case .file:
            return "Files"
        }
    }
}

@MainActor
final class ClipboardManager: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published var searchText = ""
    @Published var activeFilter: ClipboardFilter = .all
    @Published var isMonitoringEnabled = true {
        didSet {
            captureService.isMonitoringEnabled = isMonitoringEnabled
        }
    }
    @Published private(set) var blockedSensitiveCaptureCount = 0

    let settings: SettingsStore

    private let storage: EncryptedHistoryStore
    private let captureService: ClipboardCaptureService

    private var persistTask: Task<Void, Never>?

    init(settings: SettingsStore, storage: EncryptedHistoryStore = EncryptedHistoryStore()) {
        self.settings = settings
        self.storage = storage
        captureService = ClipboardCaptureService(settings: settings)

        captureService.onCapture = { [weak self] capture in
            self?.handleCapture(capture)
        }

        captureService.onSensitiveContentSkipped = { [weak self] in
            self?.blockedSensitiveCaptureCount += 1
        }

        settings.onChange = { [weak self] in
            self?.applySettingsChanges()
        }

        captureService.start()

        Task {
            await loadInitialHistory()
        }
    }

    deinit {
        persistTask?.cancel()
    }

    var filteredItems: [ClipboardHistoryItem] {
        let filtered = items.filter { item in
            switch activeFilter {
            case .all:
                return true
            case .pinned:
                return item.isPinned
            case .text:
                return item.type == .text || item.type == .url
            case .image:
                return item.type == .image
            case .file:
                return item.type == .file
            }
        }

        let query = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !query.isEmpty else {
            return filtered
        }

        return filtered.filter { item in
            if item.preview.lowercased().contains(query) {
                return true
            }
            if let plainText = item.plainText?.lowercased(), plainText.contains(query) {
                return true
            }
            if let paths = item.filePaths?.joined(separator: " ").lowercased(), paths.contains(query) {
                return true
            }
            return false
        }
    }

    var menuItems: [ClipboardHistoryItem] {
        Array(items.prefix(8))
    }

    func item(with id: UUID?) -> ClipboardHistoryItem? {
        guard let id else {
            return nil
        }
        return items.first(where: { $0.id == id })
    }

    func copyToClipboard(_ item: ClipboardHistoryItem) {
        captureService.writeToPasteboard(item: item)
    }

    func toggleMonitoring() {
        isMonitoringEnabled.toggle()
    }

    func togglePin(itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        if items[index].isPinned {
            items[index].pinnedAt = nil
        } else {
            items[index].pinnedAt = Date()
        }

        reorderAndTrim()
        schedulePersist()
    }

    func remove(itemID: UUID) {
        items.removeAll(where: { $0.id == itemID })
        reorderAndTrim()
        schedulePersist()
    }

    func clearHistory(keepPinned: Bool) {
        if keepPinned {
            items = items.filter(\.isPinned)
        } else {
            items = []
        }
        reorderAndTrim()
        schedulePersist()
    }

    func revealFiles(of item: ClipboardHistoryItem) {
        guard let paths = item.filePaths, !paths.isEmpty else {
            return
        }

        let urls = paths.map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func handleCapture(_ capture: CapturedClipboardItem) {
        if let existingIndex = items.firstIndex(where: { $0.digest == capture.digest && $0.type == capture.type }) {
            guard existingIndex != 0 else {
                return
            }

            let existingItem = items.remove(at: existingIndex)
            items.insert(existingItem, at: 0)
            reorderAndTrim()
            schedulePersist()
            return
        }

        let item = ClipboardHistoryItem(
            type: capture.type,
            preview: capture.preview,
            plainText: capture.plainText,
            imagePNGData: capture.imagePNGData,
            filePaths: capture.filePaths,
            digest: capture.digest,
            byteSize: capture.byteSize,
            sourceBundleIdentifier: capture.sourceBundleIdentifier
        )

        items.insert(item, at: 0)
        reorderAndTrim()
        schedulePersist()
    }

    private func applySettingsChanges() {
        captureService.applySettings()
        reorderAndTrim()

        if settings.persistHistory {
            schedulePersist()
        } else {
            Task {
                await storage.clearHistoryFile()
            }
        }
    }

    private func loadInitialHistory() async {
        if settings.persistHistory {
            let stored = await storage.loadHistory()
            items = stored
            reorderAndTrim()
        } else {
            await storage.clearHistoryFile()
        }
    }

    private func reorderAndTrim() {
        let pinned = items
            .filter(\.isPinned)
            .sorted { lhs, rhs in
                (lhs.pinnedAt ?? lhs.createdAt) > (rhs.pinnedAt ?? rhs.createdAt)
            }

        let unpinned = items
            .filter { !$0.isPinned }
            .sorted { $0.createdAt > $1.createdAt }

        items = pinned + Array(unpinned.prefix(settings.historyLimit))
    }

    private func schedulePersist() {
        persistTask?.cancel()

        guard settings.persistHistory else {
            Task {
                await storage.clearHistoryFile()
            }
            return
        }

        let snapshot = items
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else {
                return
            }
            await storage.saveHistory(snapshot)
        }
    }
}
