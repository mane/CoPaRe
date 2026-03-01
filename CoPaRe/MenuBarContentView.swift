import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var manager: ClipboardManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open CoPaRe") {
            openWindow(id: "main")
        }

        if manager.settings.lockProtectionEnabled {
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

        Button(manager.isMonitoringEnabled ? "Pause monitoring" : "Resume monitoring") {
            manager.toggleMonitoring()
        }
        .disabled(manager.isLocked)

        Button("Clear unpinned history", role: .destructive) {
            manager.clearHistory(keepPinned: true)
        }
        .disabled(manager.isLocked)

        Divider()

        if manager.menuItems.isEmpty {
            Text(manager.isLocked ? "CoPaRe is locked" : "No clipboard history yet")
        } else {
            ForEach(manager.menuItems) { item in
                Menu {
                    Button("Copy") {
                        manager.copyToClipboard(item)
                    }

                    Button(item.isPinned ? "Unpin" : "Pin") {
                        manager.togglePin(itemID: item.id)
                    }

                    if item.type == .file {
                        Button("Reveal in Finder") {
                            manager.revealFiles(of: item)
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

            Text(item.preview)
                .lineLimit(1)
        }
    }
}
