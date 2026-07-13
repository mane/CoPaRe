import Foundation
import OSLog
import ServiceManagement
import Combine

enum ClipboardItemTTL: String, CaseIterable, Identifiable {
    case never
    case thirtySeconds
    case fiveMinutes
    case fifteenMinutes
    case oneHour
    case oneDay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never:
            return "Never"
        case .thirtySeconds:
            return "30 seconds"
        case .fiveMinutes:
            return "5 minutes"
        case .fifteenMinutes:
            return "15 minutes"
        case .oneHour:
            return "1 hour"
        case .oneDay:
            return "1 day"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .never:
            return nil
        case .thirtySeconds:
            return 30
        case .fiveMinutes:
            return 5 * 60
        case .fifteenMinutes:
            return 15 * 60
        case .oneHour:
            return 60 * 60
        case .oneDay:
            return 24 * 60 * 60
        }
    }
}

enum SecurityPreset: String, CaseIterable, Identifiable {
    case balanced
    case strict

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .strict:
            return "Strict"
        }
    }

    var summary: String {
        switch self {
        case .balanced:
            return "Keeps full clipboard features with sensitive-content filtering enabled."
        case .strict:
            return "Minimizes retention and capture surface for high-security environments."
        }
    }
}

struct AppCaptureRule: Equatable {
    let bundleIdentifier: String
    let ignoresCapture: Bool
    let textOnly: Bool
    let ttl: ClipboardItemTTL?
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let historyLimit = "historyLimit"
        static let pollInterval = "pollInterval"
        static let persistHistory = "persistHistory"
        static let captureImages = "captureImages"
        static let captureFiles = "captureFiles"
        static let filterSensitiveContent = "filterSensitiveContent"
        static let launchAtLogin = "launchAtLogin"
        static let excludedAppsRawText = "excludedAppsRawText"
        static let itemTTL = "itemTTL"
        static let oneTimeCopyEnabled = "oneTimeCopyEnabled"
        static let lockProtectionEnabled = "lockProtectionEnabled"
        static let imageOCRIndexingEnabled = "imageOCRIndexingEnabled"
        static let globalShortcutEnabled = "globalShortcutEnabled"
        static let securityPreset = "securityPreset"
        static let onboardingCompleted = "onboardingCompleted"
        static let appCaptureRulesRawText = "appCaptureRulesRawText"
        static let perAppHistoryLimit = "perAppHistoryLimit"
        static let maskedContentTTL = "maskedContentTTL"
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "io.copare.app", category: "settings")
    private var isApplyingPreset = false

    private static let defaultExcludedApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
        "com.bitwarden.desktop",
        "com.bitwarden.desktop.helper",
        "org.keepassxc.keepassxc",
    ].joined(separator: "\n")

    var onChange: (() -> Void)?

    @Published var historyLimit: Int {
        didSet {
            let normalized = historyLimit.clamped(to: 20...1_000)
            if normalized != historyLimit {
                historyLimit = normalized
                return
            }
            persist(normalized, key: Keys.historyLimit, oldValue: oldValue)
        }
    }

    @Published var pollInterval: Double {
        didSet {
            let normalized = pollInterval.isFinite
                ? pollInterval.clamped(to: 0.25...2.0)
                : 0.65
            if !pollInterval.isFinite || normalized != pollInterval {
                pollInterval = normalized
                return
            }
            persist(normalized, key: Keys.pollInterval, oldValue: oldValue)
        }
    }

    @Published var persistHistory: Bool {
        didSet {
            persist(persistHistory, key: Keys.persistHistory, oldValue: oldValue)
        }
    }

    @Published var captureImages: Bool {
        didSet {
            persist(captureImages, key: Keys.captureImages, oldValue: oldValue)
        }
    }

    @Published var captureFiles: Bool {
        didSet {
            persist(captureFiles, key: Keys.captureFiles, oldValue: oldValue)
        }
    }

    @Published var filterSensitiveContent: Bool {
        didSet {
            persist(filterSensitiveContent, key: Keys.filterSensitiveContent, oldValue: oldValue)
        }
    }

    @Published var excludedAppsRawText: String {
        didSet {
            let normalized = Self.normalizeExcludedAppsText(excludedAppsRawText)
            if normalized != excludedAppsRawText {
                excludedAppsRawText = normalized
                return
            }
            persist(normalized, key: Keys.excludedAppsRawText, oldValue: oldValue)
        }
    }

    @Published var appCaptureRulesRawText: String {
        didSet {
            let normalized = Self.normalizeRulesText(appCaptureRulesRawText)
            if normalized != appCaptureRulesRawText {
                appCaptureRulesRawText = normalized
                return
            }
            persist(normalized, key: Keys.appCaptureRulesRawText, oldValue: oldValue)
        }
    }

    @Published var itemTTL: ClipboardItemTTL {
        didSet {
            guard itemTTL != oldValue else {
                return
            }
            defaults.set(itemTTL.rawValue, forKey: Keys.itemTTL)
            if !isApplyingPreset {
                onChange?()
            }
        }
    }

    @Published var maskedContentTTL: ClipboardItemTTL {
        didSet {
            guard maskedContentTTL != oldValue else {
                return
            }
            defaults.set(maskedContentTTL.rawValue, forKey: Keys.maskedContentTTL)
            if !isApplyingPreset {
                onChange?()
            }
        }
    }

    @Published var perAppHistoryLimit: Int {
        didSet {
            let normalized = perAppHistoryLimit.clamped(to: 5...500)
            if normalized != perAppHistoryLimit {
                perAppHistoryLimit = normalized
                return
            }
            persist(normalized, key: Keys.perAppHistoryLimit, oldValue: oldValue)
        }
    }

    @Published var oneTimeCopyEnabled: Bool {
        didSet {
            persist(oneTimeCopyEnabled, key: Keys.oneTimeCopyEnabled, oldValue: oldValue)
        }
    }

    @Published var lockProtectionEnabled: Bool {
        didSet {
            persist(lockProtectionEnabled, key: Keys.lockProtectionEnabled, oldValue: oldValue)
        }
    }

    @Published var imageOCRIndexingEnabled: Bool {
        didSet {
            persist(imageOCRIndexingEnabled, key: Keys.imageOCRIndexingEnabled, oldValue: oldValue)
        }
    }

    @Published var globalShortcutEnabled: Bool {
        didSet {
            persist(globalShortcutEnabled, key: Keys.globalShortcutEnabled, oldValue: oldValue)
        }
    }

    @Published var securityPreset: SecurityPreset {
        didSet {
            guard securityPreset != oldValue else {
                return
            }

            defaults.set(securityPreset.rawValue, forKey: Keys.securityPreset)
            if !isApplyingPreset {
                onChange?()
            }
        }
    }

    @Published var onboardingCompleted: Bool {
        didSet {
            persist(onboardingCompleted, key: Keys.onboardingCompleted, oldValue: oldValue)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            persist(launchAtLogin, key: Keys.launchAtLogin, oldValue: oldValue)
            updateLaunchAtLogin(launchAtLogin)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedHistoryLimit = defaults.object(forKey: Keys.historyLimit) as? Int ?? 250
        historyLimit = storedHistoryLimit.clamped(to: 20...1_000)

        let storedPollInterval = defaults.object(forKey: Keys.pollInterval) as? Double ?? 0.65
        pollInterval = storedPollInterval.isFinite
            ? storedPollInterval.clamped(to: 0.25...2.0)
            : 0.65
        persistHistory = defaults.object(forKey: Keys.persistHistory) as? Bool ?? true
        captureImages = defaults.object(forKey: Keys.captureImages) as? Bool ?? true
        captureFiles = defaults.object(forKey: Keys.captureFiles) as? Bool ?? true
        filterSensitiveContent = defaults.object(forKey: Keys.filterSensitiveContent) as? Bool ?? true
        excludedAppsRawText = Self.normalizeExcludedAppsText(
            defaults.string(forKey: Keys.excludedAppsRawText) ?? Self.defaultExcludedApps
        )
        appCaptureRulesRawText = Self.normalizeRulesText(defaults.string(forKey: Keys.appCaptureRulesRawText) ?? "")
        itemTTL = ClipboardItemTTL(rawValue: defaults.string(forKey: Keys.itemTTL) ?? "") ?? .never
        maskedContentTTL = ClipboardItemTTL(rawValue: defaults.string(forKey: Keys.maskedContentTTL) ?? "") ?? .fiveMinutes
        let storedPerAppHistoryLimit = defaults.object(forKey: Keys.perAppHistoryLimit) as? Int ?? 80
        perAppHistoryLimit = storedPerAppHistoryLimit.clamped(to: 5...500)
        oneTimeCopyEnabled = defaults.object(forKey: Keys.oneTimeCopyEnabled) as? Bool ?? false
        lockProtectionEnabled = defaults.object(forKey: Keys.lockProtectionEnabled) as? Bool ?? false
        imageOCRIndexingEnabled = defaults.object(forKey: Keys.imageOCRIndexingEnabled) as? Bool ?? false
        globalShortcutEnabled = defaults.object(forKey: Keys.globalShortcutEnabled) as? Bool ?? true
        securityPreset = SecurityPreset(rawValue: defaults.string(forKey: Keys.securityPreset) ?? "") ?? .balanced
        onboardingCompleted = defaults.object(forKey: Keys.onboardingCompleted) as? Bool ?? false

        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled {
                launchAtLogin = true
            } else {
                launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
            }
        } else {
            launchAtLogin = false
        }

        if storedHistoryLimit != historyLimit {
            defaults.set(historyLimit, forKey: Keys.historyLimit)
        }
        if !storedPollInterval.isFinite || storedPollInterval != pollInterval {
            defaults.set(pollInterval, forKey: Keys.pollInterval)
        }
        if storedPerAppHistoryLimit != perAppHistoryLimit {
            defaults.set(perAppHistoryLimit, forKey: Keys.perAppHistoryLimit)
        }
    }

    private func persist<T: Equatable>(_ value: T, key: String, oldValue: T) {
        guard value != oldValue else {
            return
        }

        defaults.set(value, forKey: key)
        if !isApplyingPreset {
            onChange?()
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Unable to update launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func normalizeExcludedAppsText(_ text: String) -> String {
        let normalizedLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        let unique = normalizedLines.filter { seen.insert($0).inserted }
        return unique.joined(separator: "\n")
    }

    private static func normalizeRulesText(_ text: String) -> String {
        let normalizedLines = text
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: " = ", with: " ")
                    .replacingOccurrences(of: "=", with: " ")
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        var seenBundles = Set<String>()
        return normalizedLines.compactMap { line in
            guard let bundle = line.split(whereSeparator: { $0.isWhitespace }).first.map(String.init),
                  seenBundles.insert(bundle).inserted
            else {
                return nil
            }
            return line
        }
        .joined(separator: "\n")
    }

    var excludedBundleIdentifiers: Set<String> {
        Set(
            excludedAppsRawText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    var appCaptureRules: [String: AppCaptureRule] {
        var rules: [String: AppCaptureRule] = [:]

        for line in appCaptureRulesRawText.components(separatedBy: .newlines) {
            let normalizedLine = line
                .replacingOccurrences(of: "=", with: " ")
                .replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: ";", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let tokens = normalizedLine
                .split(whereSeparator: { $0.isWhitespace })
                .map { $0.lowercased() }

            guard let bundleIdentifier = tokens.first, !bundleIdentifier.isEmpty else {
                continue
            }

            var ignoresCapture = false
            var textOnly = false
            var ttl: ClipboardItemTTL?

            for token in tokens.dropFirst() {
                switch token {
                case "ignore", "block", "off", "skip":
                    ignoresCapture = true
                case "text-only", "textonly", "text":
                    textOnly = true
                case "never":
                    ttl = .never
                case "30s", "30sec", "30seconds":
                    ttl = .thirtySeconds
                case "5m", "5min", "5minutes":
                    ttl = .fiveMinutes
                case "15m", "15min", "15minutes":
                    ttl = .fifteenMinutes
                case "1h", "1hour":
                    ttl = .oneHour
                case "1d", "1day":
                    ttl = .oneDay
                default:
                    if token.hasPrefix("ttl:") || token.hasPrefix("ttl-") {
                        ttl = Self.ttl(fromRuleToken: String(token.dropFirst(4)))
                    } else if token.hasPrefix("ttl") {
                        ttl = Self.ttl(fromRuleToken: String(token.dropFirst(3)))
                    }
                }
            }

            rules[bundleIdentifier] = AppCaptureRule(
                bundleIdentifier: bundleIdentifier,
                ignoresCapture: ignoresCapture,
                textOnly: textOnly,
                ttl: ttl
            )
        }

        return rules
    }

    func appCaptureRule(for bundleIdentifier: String?) -> AppCaptureRule? {
        guard let bundleIdentifier = bundleIdentifier?.lowercased() else {
            return nil
        }
        return appCaptureRules[bundleIdentifier]
    }

    private static func ttl(fromRuleToken rawToken: String) -> ClipboardItemTTL? {
        switch rawToken.trimmingCharacters(in: CharacterSet(charactersIn: ":=- ")) {
        case "never":
            return .never
        case "30s", "30sec", "30seconds":
            return .thirtySeconds
        case "5m", "5min", "5minutes":
            return .fiveMinutes
        case "15m", "15min", "15minutes":
            return .fifteenMinutes
        case "1h", "1hour":
            return .oneHour
        case "1d", "1day":
            return .oneDay
        default:
            return nil
        }
    }

    func applySecurityPreset(_ preset: SecurityPreset, markOnboardingCompleted: Bool = false) {
        isApplyingPreset = true
        defer {
            isApplyingPreset = false
            onChange?()
        }

        securityPreset = preset
        switch preset {
        case .balanced:
            filterSensitiveContent = true
            persistHistory = true
            captureImages = true
            captureFiles = true
            imageOCRIndexingEnabled = true
            oneTimeCopyEnabled = false
            lockProtectionEnabled = false
            itemTTL = .never
            maskedContentTTL = .fiveMinutes
            perAppHistoryLimit = 80
        case .strict:
            filterSensitiveContent = true
            persistHistory = true
            captureImages = false
            captureFiles = false
            imageOCRIndexingEnabled = false
            oneTimeCopyEnabled = true
            lockProtectionEnabled = true
            itemTTL = .fiveMinutes
            maskedContentTTL = .thirtySeconds
            perAppHistoryLimit = 25
        }

        if markOnboardingCompleted {
            onboardingCompleted = true
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
