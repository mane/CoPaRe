import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var manager: ClipboardManager
    @EnvironmentObject private var updates: AppUpdateChecker
    @EnvironmentObject private var windowCoordinator: WindowCoordinator

    var body: some View {
        Button("Quick Copy…") {
            windowCoordinator.toggleQuickPanel()
        }

        Button("Open CoPaRe") {
            windowCoordinator.openMainWindow(focusSearch: false)
        }

        if manager.settings.lockProtectionEnabled {
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

        Button(manager.isMonitoringEnabled ? "Pause monitoring" : "Resume monitoring") {
            manager.toggleMonitoring()
        }
        .disabled(manager.isLocked || manager.isVaultTransitioning)

        Menu("Privacy Pause") {
            Button("5 Minutes") {
                manager.pauseCapture(for: 5 * 60)
            }
            Button("15 Minutes") {
                manager.pauseCapture(for: 15 * 60)
            }
            Button("30 Minutes") {
                manager.pauseCapture(for: 30 * 60)
            }
            if manager.isPrivacyPaused {
                Divider()
                Button("Resume Now") {
                    manager.resumeCapture()
                }
            }
        }
        .disabled(manager.isLocked || manager.isVaultTransitioning)

        Button("Clear unpinned history", role: .destructive) {
            manager.clearHistory(keepPinned: true)
        }
        .disabled(manager.isLocked || manager.isVaultTransitioning)

        if manager.menuItems.isEmpty {
            Text(manager.isLocked ? "CoPaRe is locked" : "No clipboard history yet")
        } else {
            ForEach(manager.menuItems) { item in
                Menu {
                    Button("Copy") {
                        manager.copyToClipboard(item)
                    }

                    if item.type != .image {
                        Button("Copy as Plain Text") {
                            manager.copyAsPlainText(item)
                        }

                        Button("Copy Clean Text") {
                            manager.copyCleanText(item)
                        }

                        Button("Copy as Markdown") {
                            manager.copyAsMarkdown(item)
                        }

                        Button("Search Web") {
                            manager.searchWeb(for: item)
                        }
                    }

                    Button(item.isPinned ? "Unpin" : "Pin") {
                        manager.togglePin(itemID: item.id)
                    }

                    if item.type == .file {
                        Button("Reveal in Finder") {
                            manager.revealFiles(of: item)
                        }
                    }

                    if item.type == .url {
                        Button("Open URL") {
                            manager.openURL(item)
                        }
                    }

                    Divider()

                    Button("Secure delete", role: .destructive) {
                        manager.remove(itemID: item.id)
                    }
                } label: {
                    menuItemLabel(for: item)
                }
            }
        }

        Divider()

        if updates.supportsInAppUpdates {
            Button(updates.isSessionInProgress ? "Update Session In Progress" : "Check for Updates…") {
                updates.checkForUpdates()
            }
            .disabled(!updates.canCheckForUpdates)

            Divider()
        }

        Text("Version \(updates.currentVersionDisplay)")
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit CoPaRe", role: .destructive) {
            NSApplication.shared.terminate(nil)
        }
    }

    @ViewBuilder
    private func menuItemLabel(for item: ClipboardHistoryItem) -> some View {
        HStack(spacing: 8) {
            if item.type == .image,
               let data = item.thumbnailPNGData,
               let image = NSImage(data: data)
            {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
            } else {
                Image(systemName: item.type.symbolName)
                    .frame(width: 18, height: 18)
            }

            Text(compactMenuText(item.preview, maximumWidth: 240))
                .lineLimit(1)
                .truncationMode(.tail)

            if let sourceAppName = manager.sourceApplicationName(for: item), !item.isSnippet {
                Text(compactMenuText("· \(sourceAppName)", maximumWidth: 80))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func compactMenuText(_ text: String, maximumWidth: CGFloat) -> String {
        // Native menus size themselves from their titles, ignoring SwiftUI's
        // line/frame limits. Shorten only the displayed, already-masked preview.
        let normalized = text.condensingWhitespace()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0)]
        guard (normalized as NSString).size(withAttributes: attributes).width > maximumWidth else {
            return normalized
        }

        var prefix = ""
        for character in normalized {
            let candidate = prefix + String(character)
            guard ((candidate + "…") as NSString).size(withAttributes: attributes).width <= maximumWidth else {
                break
            }
            prefix = candidate
        }
        return prefix + "…"
    }
}
