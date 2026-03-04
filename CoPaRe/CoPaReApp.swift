import SwiftUI

@main
struct CoPaReApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var manager: ClipboardManager
    @StateObject private var updates: AppUpdateChecker

    init() {
        let settingsStore = SettingsStore()
        _settings = StateObject(wrappedValue: settingsStore)
        _manager = StateObject(wrappedValue: ClipboardManager(settings: settingsStore))
        _updates = StateObject(wrappedValue: AppUpdateChecker())
    }

    var body: some Scene {
        WindowGroup("CoPaRe", id: "main") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(updates)
        }
        .defaultSize(width: 1_120, height: 740)
        .commands {
            CommandGroup(after: .appInfo) {
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
        }
        .menuBarExtraStyle(.menu)
    }
}
