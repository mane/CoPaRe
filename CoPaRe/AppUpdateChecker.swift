import Combine
import Foundation
#if !APP_STORE
import OSLog
import Sparkle
#endif

#if APP_STORE
@MainActor
final class AppUpdateChecker: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var isSessionInProgress = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    var currentVersionDisplay: String {
        "\(currentVersion) (\(currentBuildNumber))"
    }

    var supportsInAppUpdates: Bool {
        false
    }

    var statusSummary: String {
        "Updates are delivered through the Mac App Store for this build."
    }

    func checkForUpdates() {}
    func setAutomaticallyChecks(_ enabled: Bool) {}
    func setAutomaticallyDownloads(_ enabled: Bool) {}
}
#else
@MainActor
final class AppUpdateChecker: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = true
    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var isSessionInProgress = false

    private let logger = Logger(subsystem: "io.copare.app", category: "updates")
    private let updaterController: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()

    override init() {
        let controller = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil)
        self.updaterController = controller
        super.init()

        bind(to: controller.updater)

        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    var currentVersionDisplay: String {
        "\(currentVersion) (\(currentBuildNumber))"
    }

    var supportsInAppUpdates: Bool {
        return true
    }

    var statusSummary: String {
        if isSessionInProgress {
            return "Sparkle is processing the current update session."
        }

        if automaticallyChecksForUpdates {
            return "Automatic update checks are enabled. Releases are validated with a signed appcast, EdDSA signatures, and code signing before installation."
        }

        return "Automatic update checks are disabled. You can still run a manual, verified update check at any time."
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        if !enabled {
            updaterController.updater.automaticallyDownloadsUpdates = false
        }
    }

    func setAutomaticallyDownloads(_ enabled: Bool) {
        guard allowsAutomaticUpdates else {
            return
        }

        updaterController.updater.automaticallyDownloadsUpdates = enabled
    }

    private func bind(to updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates, options: [.initial, .new])
            .sink { [weak self] value in
                self?.automaticallyChecksForUpdates = value
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates, options: [.initial, .new])
            .sink { [weak self] value in
                self?.automaticallyDownloadsUpdates = value
            }
            .store(in: &cancellables)

        updater.publisher(for: \.allowsAutomaticUpdates, options: [.initial, .new])
            .sink { [weak self] value in
                self?.allowsAutomaticUpdates = value
            }
            .store(in: &cancellables)

        updater.publisher(for: \.sessionInProgress, options: [.initial, .new])
            .sink { [weak self] value in
                self?.isSessionInProgress = value
            }
            .store(in: &cancellables)

        if let previousFeedURL = updater.clearFeedURLFromUserDefaults() {
            logger.info("Cleared legacy Sparkle feed URL override from user defaults: \(previousFeedURL.absoluteString, privacy: .public)")
        }
    }
}
#endif
