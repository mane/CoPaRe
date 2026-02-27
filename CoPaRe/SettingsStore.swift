import Foundation
import OSLog
import ServiceManagement
import Combine

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
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "io.copare.app", category: "settings")

    var onChange: (() -> Void)?

    @Published var historyLimit: Int {
        didSet {
            let normalized = historyLimit.clamped(to: 20...1_000)
            if normalized != historyLimit {
                historyLimit = normalized
                return
            }
            persist(historyLimit, key: Keys.historyLimit, oldValue: oldValue)
        }
    }

    @Published var pollInterval: Double {
        didSet {
            let normalized = pollInterval.clamped(to: 0.25...2.0)
            if normalized != pollInterval {
                pollInterval = normalized
                return
            }
            persist(pollInterval, key: Keys.pollInterval, oldValue: oldValue)
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

    @Published var launchAtLogin: Bool {
        didSet {
            persist(launchAtLogin, key: Keys.launchAtLogin, oldValue: oldValue)
            updateLaunchAtLogin(launchAtLogin)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        historyLimit = defaults.object(forKey: Keys.historyLimit) as? Int ?? 250
        pollInterval = defaults.object(forKey: Keys.pollInterval) as? Double ?? 0.65
        persistHistory = defaults.object(forKey: Keys.persistHistory) as? Bool ?? true
        captureImages = defaults.object(forKey: Keys.captureImages) as? Bool ?? true
        captureFiles = defaults.object(forKey: Keys.captureFiles) as? Bool ?? true
        filterSensitiveContent = defaults.object(forKey: Keys.filterSensitiveContent) as? Bool ?? true

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
    }

    private func persist<T: Equatable>(_ value: T, key: String, oldValue: T) {
        guard value != oldValue else {
            return
        }

        defaults.set(value, forKey: key)
        onChange?()
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
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
