import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var manager: ClipboardManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open CoPaRe") {
            openWindow(id: "main")
        }

        Button(manager.isMonitoringEnabled ? "Pause monitoring" : "Resume monitoring") {
            manager.toggleMonitoring()
        }

        Button("Clear unpinned history", role: .destructive) {
            manager.clearHistory(keepPinned: true)
        }

        Divider()

        if manager.menuItems.isEmpty {
            Text("No clipboard history yet")
        } else {
            ForEach(manager.menuItems) { item in
                Button {
                    manager.copyToClipboard(item)
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
               let data = item.imagePNGData,
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
