import SwiftUI

@main
struct CoPaReApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var manager: ClipboardManager
    @StateObject private var updates: AppUpdateChecker
    @StateObject private var hotKeyService: GlobalHotKeyService
    @StateObject private var windowCoordinator: WindowCoordinator

    init() {
        let settingsStore = SettingsStore()
        let hotKeyService = GlobalHotKeyService()
        let windowCoordinator = WindowCoordinator()
        hotKeyService.configure(settings: settingsStore, windowCoordinator: windowCoordinator)

        _settings = StateObject(wrappedValue: settingsStore)
        _manager = StateObject(wrappedValue: ClipboardManager(settings: settingsStore))
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
        }
        .defaultSize(width: 1_120, height: 740)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Open CoPaRe") {
                    windowCoordinator.openMainWindow(focusSearch: true)
                }
                .keyboardShortcut("v", modifiers: [.command, .option])

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
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(updates)
        }

        MenuBarExtra("CoPaRe", systemImage: "paperclip.circle.fill") {
            MenuBarContentView()
                .environmentObject(manager)
                .environmentObject(updates)
                .environmentObject(windowCoordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}
