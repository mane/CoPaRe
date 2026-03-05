import Combine
import Foundation
import OSLog
#if !APP_STORE
import Sparkle
#endif

@MainActor
final class AppUpdateChecker: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = true
    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var isSessionInProgress = false

#if !APP_STORE
    private let logger = Logger(subsystem: "io.copare.app", category: "updates")
    private let updaterController: SPUStandardUpdaterController
    private var cancellables = Set<AnyCancellable>()
#endif

    override init() {
#if !APP_STORE
        let controller = SPUStandardUpdaterController(updaterDelegate: nil, userDriverDelegate: nil)
        self.updaterController = controller
#endif
        super.init()

#if !APP_STORE
        bind(to: controller.updater)

        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
#else
        canCheckForUpdates = false
        automaticallyChecksForUpdates = false
        automaticallyDownloadsUpdates = false
        allowsAutomaticUpdates = false
        isSessionInProgress = false
#endif
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var supportsInAppUpdates: Bool {
#if APP_STORE
        return false
#else
        return true
#endif
    }

    var statusSummary: String {
#if APP_STORE
        return "This App Store build receives updates through the Mac App Store. In-app updater controls are disabled."
#else
        if isSessionInProgress {
            return "Sparkle is processing the current update session."
        }

        if automaticallyChecksForUpdates {
            return "Automatic update checks are enabled. Releases are validated with a signed appcast, EdDSA signatures, and code signing before installation."
        }

        return "Automatic update checks are disabled. You can still run a manual, verified update check at any time."
#endif
    }

    func checkForUpdates() {
#if !APP_STORE
        updaterController.checkForUpdates(nil)
#endif
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
#if !APP_STORE
        updaterController.updater.automaticallyChecksForUpdates = enabled
        if !enabled {
            updaterController.updater.automaticallyDownloadsUpdates = false
        }
#else
        _ = enabled
#endif
    }

    func setAutomaticallyDownloads(_ enabled: Bool) {
#if !APP_STORE
        guard allowsAutomaticUpdates else {
            return
        }

        updaterController.updater.automaticallyDownloadsUpdates = enabled
#else
        _ = enabled
#endif
    }

#if !APP_STORE
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
#endif
}
