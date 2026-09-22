import SwiftUI
#if DEBUG
import CryptoKit
#endif

@main
enum CoPaReEntryPoint {
    @MainActor
    static func main() {
#if DEBUG
        // Hosted unit tests must not construct the production dependency graph.
        let environment = ProcessInfo.processInfo.environment
        if environment["COPARE_UI_TESTS"] == "1" {
#if !APP_STORE
            fatalError("UI tests require the isolated CoPaRe App Store test scheme")
#endif
        } else if environment["COPARE_UNIT_TESTS"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
        {
            CoPaReUnitTestHost.main()
            return
        }
#endif
        CoPaReApp.main()
    }
}

#if DEBUG
private struct CoPaReUnitTestHost: App {
    var body: some Scene {
        Window("CoPaRe Unit Tests", id: "unit-tests") {
            Text("Isolated unit test host")
        }
    }
}
#endif

struct CoPaReApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var manager: ClipboardManager
    @StateObject private var updates: AppUpdateChecker
    @StateObject private var hotKeyService: GlobalHotKeyService
    @StateObject private var windowCoordinator: WindowCoordinator
    private let appDefaults: UserDefaults
    private let cleanupTestEnvironment: (() -> Void)?

    init() {
        let hotKeyService = GlobalHotKeyService()
        let windowCoordinator = WindowCoordinator()
        let settingsStore: SettingsStore
        let clipboardManager: ClipboardManager

#if DEBUG && APP_STORE
        // UI tests exercise the real views with an entirely separate data environment.
        // The App Store updater is inert, so no network updater is constructed here.
        if ProcessInfo.processInfo.environment["COPARE_UI_TESTS"] == "1" {
            let identifier = "io.copare.ui-tests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: identifier)!
            defaults.set(false, forKey: "persistHistory")
            defaults.set(false, forKey: "lockProtectionEnabled")
            defaults.set(false, forKey: "globalShortcutEnabled")
            defaults.set(true, forKey: "onboardingCompleted")
            defaults.set(Int.max, forKey: "onboardingTourVersion")
            appDefaults = defaults
            settingsStore = SettingsStore(defaults: defaults)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(identifier, isDirectory: true)
                .appendingPathComponent("snippets.json")
            let sessionKey = SymmetricKey(size: .bits256)
            let keyOperations = SnippetKeyOperations(
                loadOrCreate: { _, _, _ in sessionKey },
                delete: { _, _ in }
            )
            let store = SnippetStore(fileURL: fileURL, keyOperations: keyOperations)
            let privatePasteboard = NSPasteboard(name: .init(identifier))
            let captureService = ClipboardCaptureService(
                pasteboard: privatePasteboard,
                settings: settingsStore,
                sourceBundleIdentifierProvider: { nil }
            )
            clipboardManager = ClipboardManager(
                settings: settingsStore,
                snippetStore: store,
                checkpointStore: SnippetCheckpointStore(fileURL: fileURL.deletingLastPathComponent().appendingPathComponent("snippets-pending.json")),
                captureService: captureService,
                startsAutomatically: false,
                lockSnapshotKeyLoader: { _ in sessionKey },
                lockSnapshotKeyDeleter: {}
            )
            cleanupTestEnvironment = {
                privatePasteboard.clearContents()
                defaults.removePersistentDomain(forName: identifier)
                try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            }
        } else {
            appDefaults = .standard
            cleanupTestEnvironment = nil
            settingsStore = SettingsStore()
            clipboardManager = ClipboardManager(settings: settingsStore)
            hotKeyService.configure(settings: settingsStore, windowCoordinator: windowCoordinator)
        }
#else
        appDefaults = .standard
        cleanupTestEnvironment = nil
        settingsStore = SettingsStore()
        clipboardManager = ClipboardManager(settings: settingsStore)
        hotKeyService.configure(settings: settingsStore, windowCoordinator: windowCoordinator)
#endif

        windowCoordinator.configureQuickPanel(manager: clipboardManager)

        _settings = StateObject(wrappedValue: settingsStore)
        _manager = StateObject(wrappedValue: clipboardManager)
        _updates = StateObject(wrappedValue: AppUpdateChecker())
        _hotKeyService = StateObject(wrappedValue: hotKeyService)
        _windowCoordinator = StateObject(wrappedValue: windowCoordinator)
    }

    var body: some Scene {
        Window("CoPaRe", id: "main") {
            MainWindowContainerView()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(updates)
                .environmentObject(windowCoordinator)
                .defaultAppStorage(appDefaults)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    cleanupTestEnvironment?()
                }
        }
        .defaultSize(width: 1_120, height: 740)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Quick Copy…") {
                    windowCoordinator.toggleQuickPanel()
                }
                .keyboardShortcut("v", modifiers: [.command, .option])

                Button("Open CoPaRe") {
                    windowCoordinator.openMainWindow(focusSearch: true)
                }

                Button("Interactive How To…") {
                    windowCoordinator.openMainWindow(focusSearch: false)
                    NotificationCenter.default.post(name: .copareOpenOnboardingRequested, object: nil)
                }

                Divider()

                if updates.supportsInAppUpdates {
                    Button(updates.isSessionInProgress ? "Update Session In Progress" : "Check for Updates…") {
                        updates.checkForUpdates()
                    }
                    .disabled(!updates.canCheckForUpdates)
                }

                if settings.lockProtectionEnabled {
                    Divider()

                    if manager.isLocked {
                        Button("Unlock CoPaRe") {
                            windowCoordinator.openMainWindow(focusSearch: true)
                            Task {
                                await manager.unlock()
                            }
                        }
                        .disabled(manager.isVaultTransitioning)
                    } else {
                        Button("Lock CoPaRe") {
                            Task {
                                await manager.lock()
                            }
                        }
                        .disabled(manager.isVaultTransitioning)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .defaultAppStorage(appDefaults)
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(updates)
        }

        MenuBarExtra("CoPaRe", systemImage: "paperclip.circle.fill") {
            MenuBarContentView()
                .defaultAppStorage(appDefaults)
                .environmentObject(manager)
                .environmentObject(updates)
                .environmentObject(windowCoordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}
