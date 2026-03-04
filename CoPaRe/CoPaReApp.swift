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
        _settings = StateObject(wrappedValue: settingsStore)
        _manager = StateObject(wrappedValue: ClipboardManager(settings: settingsStore))
        _updates = StateObject(wrappedValue: AppUpdateChecker())
        _hotKeyService = StateObject(wrappedValue: GlobalHotKeyService())
        _windowCoordinator = StateObject(wrappedValue: WindowCoordinator())
    }

    var body: some Scene {
        WindowGroup("CoPaRe", id: "main") {
            MainWindowContainerView()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(updates)
                .environmentObject(hotKeyService)
                .environmentObject(windowCoordinator)
        }
        .defaultSize(width: 1_120, height: 740)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Open CoPaRe") {
                    windowCoordinator.openMainWindow(focusSearch: true)
                }
                .keyboardShortcut("v", modifiers: [.command, .option])

                Divider()

                Button(updates.isSessionInProgress ? "Update Session In Progress" : "Check for Updates…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)

                if settings.lockProtectionEnabled {
                    Divider()

                    if manager.isLocked {
                        Button("Unlock CoPaRe") {
                            Task {
                                await manager.unlock()
                            }
                        }
                    } else {
                        Button("Lock CoPaRe") {
                            manager.lock()
                        }
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
                .environmentObject(windowCoordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}
