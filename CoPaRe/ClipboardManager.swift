import AppKit
import Foundation
import Combine
import LocalAuthentication
import CryptoKit
import OSLog

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
    var privacyPauses = 0

    var totalBlocked: Int {
        sensitiveContentBlocked + excludedApplicationSkips
    }
}

private struct LockedClipboardSnapshot: Codable {
    let version: Int
    let lockedAt: Date
    let items: [LockedClipboardSnapshotItem]
}

private struct LockedClipboardSnapshotItem: Codable {
    let id: UUID
    let type: ClipboardItemType
    let createdAt: Date
    let updatedAt: Date
    let pinnedAt: Date?
    let expiresAt: Date?
    let preview: String
    let searchIndex: String?
    let thumbnailPNGData: Data?
    let payload: ClipboardItemPayload?
    let digest: String
    let byteSize: Int
    let origin: ClipboardItemOrigin
    let captureCount: Int
    let sourceBundleIdentifier: String?
    let tags: [String]
}

private struct LockedClipboardEnvelope {
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

private struct SnippetExportDocument: Codable {
    let version: Int
    let exportedAt: Date
    let snippets: [SnippetExportItem]
}

private struct SnippetExportItem: Codable {
    let title: String
    let body: String
    let tags: [String]
    let createdAt: Date
    let updatedAt: Date
    let pinned: Bool
}

@MainActor
final class ClipboardManager: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published var searchText = ""
    @Published var activeFilter: ClipboardFilter = .all
    @Published var isMonitoringEnabled = true {
        didSet {
            syncCaptureServiceMonitoringState()
        }
    }
    @Published private(set) var securityCounters = SecurityEventCounters()
    @Published private(set) var isLocked: Bool
    @Published private(set) var hasSavedSnippetsAvailable = false
    @Published private(set) var savedSnippetsLoaded = true
    @Published private(set) var secureWipeMessage: String?
    @Published private(set) var secureWipeFailed = false
    @Published private(set) var privacyPauseUntil: Date?

    let settings: SettingsStore

    private let snippetStore: SnippetStore
    private let captureService: ClipboardCaptureService
    private let logger = Logger(subsystem: "io.copare.app", category: "lock")
    private let lockSnapshotKeyProvider = KeychainKeyProvider(
        service: "io.copare.app.lock-snapshot",
        requiresUserPresence: true,
        cacheInMemory: false
    )

    private var persistTask: Task<Void, Never>?
    private var expirationTimer: Timer?
    private var privacyPauseTimer: Timer?
    private var lockedSnapshotEnvelope: LockedClipboardEnvelope?

    init(
        settings: SettingsStore,
        snippetStore: SnippetStore = SnippetStore()
    ) {
        self.settings = settings
        self.snippetStore = snippetStore
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

        syncCaptureServiceMonitoringState()
        captureService.start()
        configureExpirationTimer()

        Task {
            await loadInitialState()
        }
    }

    deinit {
        persistTask?.cancel()
        expirationTimer?.invalidate()
        privacyPauseTimer?.invalidate()
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
            if item.tags.contains(where: { $0.contains(query) || "#\($0)".contains(query) }) {
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

    var isPrivacyPaused: Bool {
        guard let privacyPauseUntil else {
            return false
        }
        return privacyPauseUntil > Date()
    }

    var privacyPauseStatus: String? {
        guard let privacyPauseUntil, privacyPauseUntil > Date() else {
            return nil
        }

        let remaining = max(0, Int(privacyPauseUntil.timeIntervalSinceNow.rounded(.up)))
        if remaining >= 60 {
            return "\(Int(ceil(Double(remaining) / 60.0)))m"
        }
        return "\(remaining)s"
    }

    func item(with id: UUID?) -> ClipboardHistoryItem? {
        guard let id else {
            return nil
        }
        return items.first(where: { $0.id == id })
    }

    func sourceApplicationName(for item: ClipboardHistoryItem) -> String? {
        SourceApplicationResolver.displayName(for: item.sourceBundleIdentifier)
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

    func copyAsPlainText(_ item: ClipboardHistoryItem) {
        guard !isLocked else {
            return
        }

        guard captureService.writePlainTextToPasteboard(item: item) else {
            return
        }

        if settings.oneTimeCopyEnabled, !item.isPinned, !item.isSnippet {
            remove(itemID: item.id, immediatelyPersist: true)
        }
    }

    func copyCleanText(_ item: ClipboardHistoryItem) {
        guard !isLocked, let text = plainTextRepresentation(for: item)?.condensingWhitespace(), !text.isEmpty else {
            return
        }

        captureService.writeString(text)
        if settings.oneTimeCopyEnabled, !item.isPinned, !item.isSnippet {
            remove(itemID: item.id, immediatelyPersist: true)
        }
    }

    func copyAsMarkdown(_ item: ClipboardHistoryItem) {
        guard !isLocked, let markdown = markdownRepresentation(for: item) else {
            return
        }

        captureService.writeString(markdown)
        if settings.oneTimeCopyEnabled, !item.isPinned, !item.isSnippet {
            remove(itemID: item.id, immediatelyPersist: true)
        }
    }

    func openURL(_ item: ClipboardHistoryItem) {
        guard !isLocked, let url = urlRepresentation(for: item) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func searchWeb(for item: ClipboardHistoryItem) {
        guard !isLocked,
              let query = plainTextRepresentation(for: item)?.previewSnippet(maxLength: 300),
              !query.isEmpty
        else {
            return
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func qrCodeText(for item: ClipboardHistoryItem) -> String? {
        guard !isLocked else {
            return nil
        }

        if let url = urlRepresentation(for: item)?.absoluteString {
            return url
        }
        return plainTextRepresentation(for: item)
    }

    func toggleMonitoring() {
        isMonitoringEnabled.toggle()
    }

    func pauseCapture(for duration: TimeInterval) {
        guard duration > 0 else {
            return
        }

        privacyPauseUntil = Date().addingTimeInterval(duration)
        mutateSecurityCounters { $0.privacyPauses += 1 }
        configurePrivacyPauseTimer()
        syncCaptureServiceMonitoringState()
    }

    func resumeCapture() {
        privacyPauseUntil = nil
        privacyPauseTimer?.invalidate()
        privacyPauseTimer = nil
        syncCaptureServiceMonitoringState()
    }

    func lock() {
        guard settings.lockProtectionEnabled, !isLocked else {
            return
        }

        guard prepareLockedSnapshot() else {
            logger.error("Lock aborted: unable to prepare encrypted snapshot")
            return
        }

        items = []
        EncryptedClipboardPayload.rotateSessionProtectionKey()
        isLocked = true
        syncCaptureServiceMonitoringState()
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
                guard await restoreAfterUnlock(using: context) else {
                    return
                }

                isLocked = false
                syncCaptureServiceMonitoringState()
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
            items[index].expiresAt = expirationDate(
                for: items[index].origin,
                from: Date(),
                sourceBundleIdentifier: items[index].sourceBundleIdentifier,
                preview: items[index].preview
            )
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
        lockedSnapshotEnvelope = nil
        EncryptedClipboardPayload.rotateSessionProtectionKey()
        mutateSecurityCounters { $0.secureWipes += 1 }
        secureWipeMessage = nil
        secureWipeFailed = false

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let wipeSucceeded = await snippetStore.clearSnippetsFile()
            if wipeSucceeded {
                secureWipeMessage = "Secure wipe completed. History and vault keys were removed."
                secureWipeFailed = false
            } else {
                secureWipeMessage = "Secure wipe completed with warnings. At least one vault key could not be removed (authentication may have been canceled). Run wipe again and approve the macOS prompt."
                secureWipeFailed = true
            }
        }
        hasSavedSnippetsAvailable = false
        savedSnippetsLoaded = true
    }

    func addSnippet(title: String, body: String, tags: [String] = []) {
        guard !isLocked else {
            return
        }

        let now = Date()
        guard let item = makeSnippet(title: title, body: body, tags: tags, createdAt: now, updatedAt: now) else {
            return
        }

        items.insert(item, at: 0)
        sortAndTrim()
        scheduleSnippetPersist(immediately: true)
    }

    func exportSnippets(to url: URL) -> Bool {
        let exportItems = items
            .filter(\.isSnippet)
            .compactMap { item -> SnippetExportItem? in
                guard let plainText = item.decryptedPayload()?.plainText else {
                    return nil
                }

                return SnippetExportItem(
                    title: item.preview,
                    body: plainText,
                    tags: item.tags,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    pinned: item.isPinned
                )
            }

        let document = SnippetExportDocument(
            version: 1,
            exportedAt: Date(),
            snippets: exportItems
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(document)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func importSnippets(from url: URL) -> Int {
        guard !isLocked else {
            return 0
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(SnippetExportDocument.self, from: data)

            let existingDigests = Set(items.filter(\.isSnippet).map(\.digest))
            var imported = [ClipboardHistoryItem]()
            var importedDigests = Set<String>()

            for snippet in document.snippets {
                guard let item = makeSnippet(
                    title: snippet.title,
                    body: snippet.body,
                    tags: snippet.tags,
                    createdAt: snippet.createdAt,
                    updatedAt: snippet.updatedAt
                ) else {
                    continue
                }

                guard !existingDigests.contains(item.digest),
                      importedDigests.insert(item.digest).inserted
                else {
                    continue
                }

                var mutableItem = item
                if snippet.pinned {
                    mutableItem.pinnedAt = snippet.updatedAt
                }
                imported.append(mutableItem)
            }

            guard !imported.isEmpty else {
                return 0
            }

            items.insert(contentsOf: imported, at: 0)
            sortAndTrim()
            scheduleSnippetPersist(immediately: true)
            return imported.count
        } catch {
            return 0
        }
    }

    private func makeSnippet(
        title: String,
        body: String,
        tags: [String],
        createdAt: Date,
        updatedAt: Date
    ) -> ClipboardHistoryItem? {
        let normalizedBody = body
            .replacingOccurrences(of: "\u{0000}", with: "")

        guard !normalizedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .previewSnippet(maxLength: 80)
        let normalizedTags = ClipboardHistoryItem.normalizedTags(tags)

        let preview: String
        if normalizedTitle.isEmpty {
            if SensitiveContentDetector.shouldMaskPreview(text: normalizedBody) {
                preview = "Sensitive snippet hidden"
            } else {
                preview = normalizedBody.previewSnippet(maxLength: 80)
            }
        } else {
            preview = normalizedTitle
        }
        let payload = ClipboardItemPayload(
            plainText: normalizedBody,
            imagePNGData: nil,
            filePaths: nil
        )

        guard let encryptedPayload = try? EncryptedClipboardPayload.seal(payload) else {
            return nil
        }

        let searchTerms = ([preview] + normalizedTags.map { "#\($0)" })
            .joined(separator: " ")
            .condensingWhitespace()

        return ClipboardHistoryItem(
            type: .text,
            createdAt: createdAt,
            updatedAt: updatedAt,
            pinnedAt: nil,
            expiresAt: nil,
            preview: preview,
            searchIndex: String(searchTerms.prefix(160)),
            thumbnailPNGData: nil,
            encryptedPayload: encryptedPayload,
            digest: digest(for: "snippet:\(preview)\n\(normalizedBody)\n\(normalizedTags.joined(separator: ","))"),
            byteSize: Data(normalizedBody.utf8).count,
            origin: .snippet,
            captureCount: 1,
            sourceBundleIdentifier: nil,
            tags: normalizedTags
        )
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
        guard !isLocked else {
            return
        }

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
        guard !isLocked else {
            return
        }

        let now = capture.capturedAt
        let expirationDate = expirationDate(
            for: .captured,
            from: now,
            sourceBundleIdentifier: capture.sourceBundleIdentifier,
            preview: capture.preview
        )

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
            items[index].expiresAt = expirationDate(
                for: items[index].origin,
                from: items[index].updatedAt,
                sourceBundleIdentifier: items[index].sourceBundleIdentifier,
                preview: items[index].preview
            )
        }

        if settings.lockProtectionEnabled {
            if !isLocked {
                lock()
            } else {
                syncCaptureServiceMonitoringState()
            }
        } else {
            isLocked = false
            syncCaptureServiceMonitoringState()
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

        var candidateIntervals = [
            settings.itemTTL.interval,
            settings.maskedContentTTL.interval,
        ].compactMap { $0 }
        candidateIntervals.append(contentsOf: settings.appCaptureRules.values.compactMap { $0.ttl?.interval })

        guard let ttl = candidateIntervals.min(), ttl > 0 else {
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

    private func configurePrivacyPauseTimer() {
        privacyPauseTimer?.invalidate()
        privacyPauseTimer = nil

        guard let privacyPauseUntil else {
            return
        }

        let remaining = max(0.25, privacyPauseUntil.timeIntervalSinceNow)
        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumeCapture()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        privacyPauseTimer = timer
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

        let regularCandidates = items
            .filter { !$0.isPinned && !$0.isSnippet }
            .sorted { $0.updatedAt > $1.updatedAt }

        var perAppCounts: [String: Int] = [:]
        let perAppLimit = max(1, settings.perAppHistoryLimit)
        let regular = regularCandidates.filter { item in
            let key = item.sourceBundleIdentifier ?? "__unknown__"
            let count = perAppCounts[key, default: 0]
            guard count < perAppLimit else {
                return false
            }
            perAppCounts[key] = count + 1
            return true
        }

        items = snippets + pinned + Array(regular.prefix(settings.historyLimit))
    }

    private func expirationDate(
        for origin: ClipboardItemOrigin,
        from date: Date,
        sourceBundleIdentifier: String?,
        preview: String
    ) -> Date? {
        guard origin == .captured else {
            return nil
        }

        let baseTTL = settings.appCaptureRule(for: sourceBundleIdentifier)?.ttl ?? settings.itemTTL
        var interval = baseTTL.interval
        if (preview.localizedCaseInsensitiveContains("sensitive") || SensitiveContentDetector.shouldMaskPreview(text: preview)),
           let sensitiveInterval = settings.maskedContentTTL.interval
        {
            interval = min(interval ?? sensitiveInterval, sensitiveInterval)
        }

        guard let interval else {
            return nil
        }

        return date.addingTimeInterval(interval)
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
                var snippetsToPersist = currentSnapshot
                var keepSavedSnippetsUnloaded = false

                if hasStoredSnippets && !areStoredSnippetsLoaded {
                    guard let storedSnippets = await snippetStore.loadSnippets() else {
                        self.hasSavedSnippetsAvailable = true
                        self.savedSnippetsLoaded = false
                        return
                    }

                    snippetsToPersist = self.mergedSnippetsForPersistence(
                        currentSnippets: currentSnapshot,
                        storedSnippets: storedSnippets
                    )
                    keepSavedSnippetsUnloaded = !storedSnippets.isEmpty
                }

                await snippetStore.saveSnippets(snippetsToPersist, requireUserPresence: requireUserPresence)
                self.hasSavedSnippetsAvailable = !snippetsToPersist.isEmpty
                self.savedSnippetsLoaded = keepSavedSnippetsUnloaded ? false : true
            } else {
                self.hasSavedSnippetsAvailable = false
                self.savedSnippetsLoaded = true
            }
        }
    }

    private func mergedSnippetsForPersistence(
        currentSnippets: [ClipboardHistoryItem],
        storedSnippets: [ClipboardHistoryItem]
    ) -> [ClipboardHistoryItem] {
        let currentIDs = Set(currentSnippets.map(\.id))
        let currentDigests = Set(currentSnippets.map(\.digest))
        let uniqueStoredSnippets = storedSnippets.filter { snippet in
            !currentIDs.contains(snippet.id) && !currentDigests.contains(snippet.digest)
        }

        return currentSnippets + uniqueStoredSnippets
    }

    private func plainTextRepresentation(for item: ClipboardHistoryItem) -> String? {
        let payload = item.decryptedPayload()
        switch item.type {
        case .text, .url:
            return payload?.plainText
        case .file:
            guard let filePaths = payload?.filePaths, !filePaths.isEmpty else {
                return nil
            }
            return filePaths.joined(separator: "\n")
        case .image:
            return nil
        }
    }

    private func urlRepresentation(for item: ClipboardHistoryItem) -> URL? {
        guard item.type == .url,
              let rawText = item.decryptedPayload()?.plainText?.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }
        return URL(string: rawText)
    }

    private func markdownRepresentation(for item: ClipboardHistoryItem) -> String? {
        switch item.type {
        case .url:
            guard let url = urlRepresentation(for: item) else {
                return nil
            }
            let title = item.preview.isEmpty || item.preview.hasPrefix("Sensitive") ? url.absoluteString : item.preview
            return "[\(title)](\(url.absoluteString))"
        case .text:
            return item.decryptedPayload()?.plainText
        case .file:
            guard let filePaths = item.decryptedPayload()?.filePaths, !filePaths.isEmpty else {
                return nil
            }
            return filePaths.map { path in
                let url = URL(fileURLWithPath: path)
                return "- [\(url.lastPathComponent)](\(url.absoluteString))"
            }
            .joined(separator: "\n")
        case .image:
            return nil
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

    private func syncCaptureServiceMonitoringState() {
        if let privacyPauseUntil, privacyPauseUntil <= Date() {
            self.privacyPauseUntil = nil
            privacyPauseTimer?.invalidate()
            privacyPauseTimer = nil
        }

        captureService.isMonitoringEnabled = isMonitoringEnabled && !isLocked && privacyPauseUntil == nil
    }

    private func prepareLockedSnapshot() -> Bool {
        guard !items.isEmpty else {
            lockedSnapshotEnvelope = nil
            return true
        }

        let snapshot = LockedClipboardSnapshot(
            version: 1,
            lockedAt: Date(),
            items: items.map { item in
                LockedClipboardSnapshotItem(
                    id: item.id,
                    type: item.type,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    pinnedAt: item.pinnedAt,
                    expiresAt: item.expiresAt,
                    preview: item.preview,
                    searchIndex: item.searchIndex,
                    thumbnailPNGData: item.thumbnailPNGData,
                    payload: item.decryptedPayload(),
                    digest: item.digest,
                    byteSize: item.byteSize,
                    origin: item.origin,
                    captureCount: item.captureCount,
                    sourceBundleIdentifier: item.sourceBundleIdentifier,
                    tags: item.tags
                )
            }
        )

        let encryptionKey: SymmetricKey
        do {
            encryptionKey = try lockSnapshotKeyProvider.loadOrCreateKey()
        } catch {
            logger.error("Unable to load lock snapshot key: \(String(describing: error), privacy: .public)")
            return false
        }

        guard let envelope = try? sealLockedSnapshot(snapshot, using: encryptionKey) else {
            return false
        }

        lockedSnapshotEnvelope = envelope
        return true
    }

    private func sealLockedSnapshot(
        _ snapshot: LockedClipboardSnapshot,
        using key: SymmetricKey
    ) throws -> LockedClipboardEnvelope {
        let data = try JSONEncoder().encode(snapshot)
        let sealed = try AES.GCM.seal(data, using: key)

        return LockedClipboardEnvelope(
            nonce: sealed.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
    }

    private func restoreAfterUnlock(using context: LAContext) async -> Bool {
        guard let envelope = lockedSnapshotEnvelope else {
            return true
        }

        let persistentKey: SymmetricKey

        do {
            persistentKey = try lockSnapshotKeyProvider.loadOrCreateKey(authenticationContext: context)
        } catch {
            logger.error("Unable to access lock snapshot key after unlock: \(String(describing: error), privacy: .public)")
            return false
        }

        guard let restoredItems = try? openLockedSnapshot(envelope, using: persistentKey) else {
            logger.error("Unable to decrypt lock snapshot envelope")
            return false
        }

        items = restoredItems
        sortAndTrim()
        lockedSnapshotEnvelope = nil
        return true
    }

    private func openLockedSnapshot(
        _ envelope: LockedClipboardEnvelope,
        using key: SymmetricKey
    ) throws -> [ClipboardHistoryItem] {
        let nonce = try AES.GCM.Nonce(data: envelope.nonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: envelope.ciphertext,
            tag: envelope.tag
        )
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        let snapshot = try JSONDecoder().decode(LockedClipboardSnapshot.self, from: decryptedData)

        return snapshot.items.map { item in
            let runtimePayload: EncryptedClipboardPayload?
            if let payload = item.payload {
                runtimePayload = try? EncryptedClipboardPayload.seal(payload)
            } else {
                runtimePayload = nil
            }

            return ClipboardHistoryItem(
                id: item.id,
                type: item.type,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                pinnedAt: item.pinnedAt,
                expiresAt: item.expiresAt,
                preview: item.preview,
                searchIndex: item.searchIndex,
                thumbnailPNGData: item.thumbnailPNGData,
                encryptedPayload: runtimePayload,
                digest: item.digest,
                byteSize: item.byteSize,
                origin: item.origin,
                captureCount: item.captureCount,
                sourceBundleIdentifier: item.sourceBundleIdentifier,
                tags: item.tags
            )
        }
    }
}
