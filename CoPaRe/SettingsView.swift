import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var manager: ClipboardManager
    @EnvironmentObject private var updates: AppUpdateChecker
    @State private var isShowingSecureWipeConfirmation = false

    private var panelColor: Color {
        Color(nsColor: NSColor.controlBackgroundColor)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionCard(title: "Security") {
                    Picker(
                        "Preset",
                        selection: Binding(
                            get: { settings.securityPreset },
                            set: { settings.applySecurityPreset($0) }
                        )
                    ) {
                        ForEach(SecurityPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }

                    Text(settings.securityPreset.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle("Filter potentially sensitive content", isOn: $settings.filterSensitiveContent)
                    Toggle("Persist saved snippets on disk", isOn: $settings.persistHistory)
                    Toggle("One-time copy for unpinned history items", isOn: $settings.oneTimeCopyEnabled)
                    Toggle("Require unlock to view history", isOn: $settings.lockProtectionEnabled)
                        .disabled(manager.isLocked)
                    Toggle("Enable global shortcut (\(GlobalHotKeyService.shortcutDisplayName))", isOn: $settings.globalShortcutEnabled)
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)

                    Text("Clipboard captures are always session-only and are deleted when CoPaRe quits. Locking CoPaRe now removes the live history from the normal in-memory view path and pauses capture until you unlock again. This toggle controls whether manually saved snippets are stored in an encrypted vault and can be loaded on demand after restart. If app lock is enabled, macOS may require system authentication when saving or loading that vault.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !settings.persistHistory {
                        Text("Saved snippets are currently memory-only for this session.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                sectionCard(title: "Capture") {
                    Toggle("Capture images", isOn: $settings.captureImages)
                    Toggle("Capture copied files/folders", isOn: $settings.captureFiles)
                    Toggle("OCR scan copied images for sensitive text", isOn: $settings.imageOCRIndexingEnabled)
                        .disabled(!settings.captureImages)

                    HStack {
                        Text("Polling interval")
                        Spacer()
                        Text("\(settings.pollInterval, specifier: "%.2f")s")
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $settings.pollInterval, in: 0.25...2.0, step: 0.05)
                }

                sectionCard(title: "Retention") {
                    Picker("Entry time-to-live", selection: $settings.itemTTL) {
                        ForEach(ClipboardItemTTL.allCases) { ttl in
                            Text(ttl.label).tag(ttl)
                        }
                    }

                    Text("TTL applies only to captured, unpinned history items. Pinned items and snippets do not expire automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Stepper(value: $settings.historyLimit, in: 20...1_000, step: 10) {
                        Text("Unpinned history limit: \(settings.historyLimit)")
                    }
                }

                sectionCard(title: "Per-App Exclusions") {
                    Text("Bundle identifiers listed here are ignored during clipboard capture. One per line.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $settings.excludedAppsRawText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .frame(minHeight: 110)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                }

                sectionCard(title: "Security Events") {
                    counterRow(title: "Sensitive content blocked", value: manager.securityCounters.sensitiveContentBlocked)
                    counterRow(title: "Excluded app skips", value: manager.securityCounters.excludedApplicationSkips)
                    counterRow(title: "Expired entries removed", value: manager.securityCounters.expiredEntriesRemoved)
                    counterRow(title: "Secure wipes", value: manager.securityCounters.secureWipes)
                    counterRow(title: "Unlock events", value: manager.securityCounters.unlockEvents)
                }

                sectionCard(title: "Updates") {
                    counterRow(title: "Current version", value: updates.currentVersion)

                    Text(updates.statusSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Check automatically",
                        isOn: Binding(
                            get: { updates.automaticallyChecksForUpdates },
                            set: { updates.setAutomaticallyChecks($0) }
                        )
                    )

                    Toggle(
                        "Download updates automatically",
                        isOn: Binding(
                            get: { updates.automaticallyDownloadsUpdates },
                            set: { updates.setAutomaticallyDownloads($0) }
                        )
                    )
                    .disabled(!updates.allowsAutomaticUpdates || !updates.automaticallyChecksForUpdates)
                }

                sectionCard(title: "Danger Zone") {
                    Button("Secure wipe entire history", role: .destructive) {
                        isShowingSecureWipeConfirmation = true
                    }
                    .buttonStyle(.bordered)

                    if let secureWipeMessage = manager.secureWipeMessage {
                        Text(secureWipeMessage)
                            .font(.footnote)
                            .foregroundStyle(manager.secureWipeFailed ? .red : .secondary)
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 620, height: 760)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .alert("Secure wipe entire history?", isPresented: $isShowingSecureWipeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Secure Wipe", role: .destructive) {
                manager.secureWipeEntireHistory()
            }
        } message: {
            Text("This removes clipboard history and deletes snippet-vault keys (crypto-shredding). If app lock is enabled, macOS may request system authentication to remove protected keys.")
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func counterRow(title: String, value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
        }
    }

    private func counterRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
