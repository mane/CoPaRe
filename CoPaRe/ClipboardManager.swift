import AppKit
import Foundation
import Combine
import LocalAuthentication
import CryptoKit

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

struct SecurityEventCounters: Equatable {
    var sensitiveContentBlocked = 0
    var excludedApplicationSkips = 0
    var expiredEntriesRemoved = 0
    var secureWipes = 0
    var unlockEvents = 0

    var totalBlocked: Int {
        sensitiveContentBlocked + excludedApplicationSkips
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
    @Published private(set) var securityCounters = SecurityEventCounters()
    @Published private(set) var isLocked: Bool
    @Published private(set) var hasSavedSnippetsAvailable = false
    @Published private(set) var savedSnippetsLoaded = true

    let settings: SettingsStore

    private let snippetStore: SnippetStore
    private let legacyStorage: EncryptedHistoryStore
    private let captureService: ClipboardCaptureService

    private var persistTask: Task<Void, Never>?
    private var expirationTimer: Timer?

    init(
        settings: SettingsStore,
        snippetStore: SnippetStore = SnippetStore(),
        legacyStorage: EncryptedHistoryStore = EncryptedHistoryStore()
    ) {
        self.settings = settings
        self.snippetStore = snippetStore
        self.legacyStorage = legacyStorage
        captureService = ClipboardCaptureService(settings: settings)
        isLocked = settings.lockProtectionEnabled

        captureService.onCapture = { [weak self] capture in
            self?.handleCapture(capture)
        }

        captureService.onSensitiveContentSkipped = { [weak self] in
            self?.mutateSecurityCounters { $0.sensitiveContentBlocked += 1 }
        }

        captureService.onExcludedApplicationSkipped = { [weak self] in
            self?.mutateSecurityCounters { $0.excludedApplicationSkips += 1 }
        }

        settings.onChange = { [weak self] in
            self?.applySettingsChanges()
        }

        captureService.start()
        configureExpirationTimer()

        Task {
            await loadInitialState()
        }
    }

    deinit {
        persistTask?.cancel()
        expirationTimer?.invalidate()
    }

    var filteredItems: [ClipboardHistoryItem] {
        guard !isLocked else {
            return []
        }

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
            if let searchIndex = item.searchIndex?.lowercased(), searchIndex.contains(query) {
                return true
            }
            return false
        }
    }

    var menuItems: [ClipboardHistoryItem] {
        guard !isLocked else {
            return []
        }
        return Array(items.prefix(8))
    }

    func item(with id: UUID?) -> ClipboardHistoryItem? {
        guard let id else {
            return nil
        }
        return items.first(where: { $0.id == id })
    }

    func copyToClipboard(_ item: ClipboardHistoryItem) {
        guard !isLocked else {
            return
        }

        guard captureService.writeToPasteboard(item: item) else {
            return
        }

        if settings.oneTimeCopyEnabled, !item.isPinned, !item.isSnippet {
            remove(itemID: item.id, immediatelyPersist: true)
        }
    }

    func toggleMonitoring() {
        isMonitoringEnabled.toggle()
    }

    func lock() {
        guard settings.lockProtectionEnabled else {
            return
        }
        isLocked = true
    }

    func unlock() async {
        guard settings.lockProtectionEnabled, isLocked else {
            return
        }

        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            return
        }

        do {
            let success = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock CoPaRe to view clipboard history") { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            }

            if success {
                isLocked = false
                mutateSecurityCounters { $0.unlockEvents += 1 }
            }
        } catch {
            return
        }
    }

    func togglePin(itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        let isSnippetItem = items[index].isSnippet

        if items[index].isPinned {
            items[index].pinnedAt = nil
            items[index].expiresAt = expirationDate(for: items[index].origin, from: Date())
        } else {
            items[index].pinnedAt = Date()
            items[index].expiresAt = nil
        }

        sortAndTrim()
        if isSnippetItem {
            scheduleSnippetPersist(immediately: true)
        }
    }

    func remove(itemID: UUID, immediatelyPersist: Bool = true) {
        let originalCount = items.count
        let removedSnippet = items.first(where: { $0.id == itemID })?.isSnippet ?? false
        items.removeAll(where: { $0.id == itemID })
        guard items.count != originalCount else {
            return
        }

        sortAndTrim()

        guard removedSnippet else {
            return
        }

        if immediatelyPersist {
            scheduleSnippetPersist(immediately: true)
        } else {
            scheduleSnippetPersist(immediately: false)
        }
    }

    func clearHistory(keepPinned: Bool) {
        if keepPinned {
            items = items.filter { $0.isPinned || $0.isSnippet }
            sortAndTrim()
            if items.contains(where: \.isSnippet) {
                scheduleSnippetPersist(immediately: true)
            }
        } else {
            secureWipeEntireHistory()
        }
    }

    func secureWipeEntireHistory() {
        items = []
        persistTask?.cancel()
        mutateSecurityCounters { $0.secureWipes += 1 }

        Task {
            await snippetStore.clearSnippetsFile()
            await legacyStorage.clearHistoryFile()
        }
        hasSavedSnippetsAvailable = false
        savedSnippetsLoaded = true
    }

    func addSnippet(title: String, body: String) {
        let normalizedBody = body
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedBody.isEmpty else {
            return
        }

        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .previewSnippet(maxLength: 80)

        let preview = normalizedTitle.isEmpty ? normalizedBody.previewSnippet(maxLength: 80) : normalizedTitle
        let payload = ClipboardItemPayload(
            plainText: normalizedBody,
            imagePNGData: nil,
            filePaths: nil
        )

        guard let encryptedPayload = try? EncryptedClipboardPayload.seal(payload) else {
            return
        }

        let now = Date()
        let item = ClipboardHistoryItem(
            type: .text,
            createdAt: now,
            updatedAt: now,
            pinnedAt: nil,
            expiresAt: nil,
            preview: preview,
            searchIndex: String(preview.prefix(120)),
            thumbnailPNGData: nil,
            encryptedPayload: encryptedPayload,
            digest: digest(for: "snippet:\(preview)\n\(normalizedBody)"),
            byteSize: Data(normalizedBody.utf8).count,
            origin: .snippet,
            captureCount: 1,
            sourceBundleIdentifier: nil
        )

        items.insert(item, at: 0)
        sortAndTrim()
        scheduleSnippetPersist(immediately: true)
    }

    func revealFiles(of item: ClipboardHistoryItem) {
        guard !isLocked else {
            return
        }

        guard let paths = item.decryptedPayload()?.filePaths, !paths.isEmpty else {
            return
        }

        let urls = paths.map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func loadSavedSnippets() async {
        guard settings.persistHistory else {
            hasSavedSnippetsAvailable = false
            savedSnippetsLoaded = true
            return
        }

        guard let stored = await snippetStore.loadSnippets() else {
            return
        }
        let currentSnippets = items.filter(\.isSnippet)
        let currentSnippetIDs = Set(currentSnippets.map(\.id))
        let mergedSnippets = currentSnippets + stored.filter { !currentSnippetIDs.contains($0.id) }

        items = items.filter { !$0.isSnippet } + mergedSnippets
        sortAndTrim()
        hasSavedSnippetsAvailable = !mergedSnippets.isEmpty
        savedSnippetsLoaded = true
    }

    private func handleCapture(_ capture: CapturedClipboardItem) {
        let now = Date()
        let expirationDate = expirationDate(for: .captured, from: now)

        if let existingIndex = items.firstIndex(where: { $0.digest == capture.digest && $0.type == capture.type }) {
            items[existingIndex].updatedAt = now
            items[existingIndex].expiresAt = items[existingIndex].isPinned
                ? nil
                : expirationDate
            items[existingIndex].captureCount += 1
            sortAndTrim()
            return
        }

        let item = ClipboardHistoryItem(
            type: capture.type,
            createdAt: now,
            updatedAt: now,
            pinnedAt: nil,
            expiresAt: expirationDate,
            preview: capture.preview,
            searchIndex: capture.searchIndex,
            thumbnailPNGData: capture.thumbnailPNGData,
            encryptedPayload: capture.encryptedPayload,
            digest: capture.digest,
            byteSize: capture.byteSize,
            origin: .captured,
            captureCount: 1,
            sourceBundleIdentifier: capture.sourceBundleIdentifier
        )

        items.insert(item, at: 0)
        sortAndTrim()
    }

    private func applySettingsChanges() {
        captureService.applySettings()
        configureExpirationTimer()

        for index in items.indices where !items[index].isSnippet && !items[index].isPinned {
            items[index].expiresAt = expirationDate(for: items[index].origin, from: items[index].updatedAt)
        }

        if settings.lockProtectionEnabled {
            isLocked = true
        } else {
            isLocked = false
        }

        _ = pruneExpiredItems()
        sortAndTrim()

        if settings.persistHistory {
            if items.contains(where: \.isSnippet) {
                scheduleSnippetPersist()
            } else {
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    self.hasSavedSnippetsAvailable = await self.snippetStore.hasSavedSnippets()
                    self.savedSnippetsLoaded = !self.hasSavedSnippetsAvailable
                }
            }
        } else {
            hasSavedSnippetsAvailable = false
            savedSnippetsLoaded = true
            Task {
                await snippetStore.clearSnippetsFile()
            }
        }

    }

    private func loadInitialState() async {
        await legacyStorage.clearHistoryFile()

        if settings.persistHistory {
            hasSavedSnippetsAvailable = await snippetStore.hasSavedSnippets()
            savedSnippetsLoaded = !hasSavedSnippetsAvailable
        } else {
            hasSavedSnippetsAvailable = false
            savedSnippetsLoaded = true
        }
    }

    private func configureExpirationTimer() {
        expirationTimer?.invalidate()
        expirationTimer = nil

        guard let ttl = settings.itemTTL.interval, ttl > 0 else {
            return
        }

        let interval = max(5.0, min(60.0, ttl / 2))
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleExpirationSweep()
            }
        }
        timer.tolerance = min(5.0, interval * 0.25)
        RunLoop.main.add(timer, forMode: .common)
        expirationTimer = timer
    }

    private func handleExpirationSweep() {
        guard pruneExpiredItems() else {
            return
        }

        sortAndTrim()
    }

    @discardableResult
    private func pruneExpiredItems(now: Date = Date()) -> Bool {
        let originalCount = items.count
        items.removeAll { item in
            guard !item.isPinned, !item.isSnippet, let expiresAt = item.expiresAt else {
                return false
            }
            return expiresAt <= now
        }

        let removed = originalCount - items.count
        if removed > 0 {
            mutateSecurityCounters { $0.expiredEntriesRemoved += removed }
            return true
        }
        return false
    }

    private func sortAndTrim() {
        let snippets = items
            .filter(\.isSnippet)
            .sorted { $0.updatedAt > $1.updatedAt }

        let pinned = items
            .filter { $0.isPinned && !$0.isSnippet }
            .sorted { lhs, rhs in
                (lhs.pinnedAt ?? lhs.updatedAt) > (rhs.pinnedAt ?? rhs.updatedAt)
            }

        let regular = items
            .filter { !$0.isPinned && !$0.isSnippet }
            .sorted { $0.updatedAt > $1.updatedAt }

        items = snippets + pinned + Array(regular.prefix(settings.historyLimit))
    }

    private func expirationDate(for origin: ClipboardItemOrigin, from date: Date) -> Date? {
        guard origin == .captured, let ttl = settings.itemTTL.interval else {
            return nil
        }

        return date.addingTimeInterval(ttl)
    }

    private func scheduleSnippetPersist(immediately: Bool = false) {
        persistTask?.cancel()

        let currentSnapshot = items.filter(\.isSnippet)
        let persistSnippets = settings.persistHistory
        let hasStoredSnippets = hasSavedSnippetsAvailable
        let areStoredSnippetsLoaded = savedSnippetsLoaded
        let requireUserPresence = settings.lockProtectionEnabled
        persistTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if !immediately {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            guard !Task.isCancelled else {
                return
            }

            if persistSnippets {
                var snapshot = currentSnapshot
                if hasStoredSnippets && !areStoredSnippetsLoaded {
                    guard let stored = await snippetStore.loadSnippets() else {
                        return
                    }
                    let currentIDs = Set(snapshot.map(\.id))
                    snapshot.append(contentsOf: stored.filter { !currentIDs.contains($0.id) })
                }

                await snippetStore.saveSnippets(snapshot, requireUserPresence: requireUserPresence)
                self.hasSavedSnippetsAvailable = !snapshot.isEmpty
                self.savedSnippetsLoaded = true
            } else {
                self.hasSavedSnippetsAvailable = false
                self.savedSnippetsLoaded = true
            }
        }
    }

    private func digest(for text: String) -> String {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func mutateSecurityCounters(_ update: (inout SecurityEventCounters) -> Void) {
        var counters = securityCounters
        update(&counters)
        securityCounters = counters
    }
}
