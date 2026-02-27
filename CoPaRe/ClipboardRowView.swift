import AppKit
import SwiftUI

struct ClipboardRowView: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var rowFill: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isHovering {
            return Color.primary.opacity(0.06)
        }
        return Color(nsColor: NSColor.textBackgroundColor).opacity(0.72)
    }

    private var rowStroke: Color {
        if isSelected {
            return Color.accentColor.opacity(0.55)
        }
        if isHovering {
            return Color(nsColor: NSColor.separatorColor).opacity(0.9)
        }
        return Color(nsColor: NSColor.separatorColor).opacity(0.62)
    }

    var body: some View {
        HStack(spacing: 10) {
            leadingVisual

            VStack(alignment: .leading, spacing: 5) {
                Text(item.preview.isEmpty ? "(empty)" : item.preview)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(item.type.label)
                    Text(item.createdAt, style: .time)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file))

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                actionButton(systemName: "doc.on.doc", help: "Copy again", action: onCopy)
                actionButton(systemName: item.isPinned ? "pin.slash" : "pin", help: item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
                actionButton(systemName: "trash", help: "Delete", role: .destructive, action: onDelete)
            }
            .opacity(isHovering || isSelected ? 1 : 0.45)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(rowStroke, lineWidth: 0.9)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Copy") { onCopy() }
            Button(item.isPinned ? "Unpin" : "Pin") { onTogglePin() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if item.type == .image,
           let data = item.thumbnailPNGData,
           let image = NSImage(data: data)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        } else {
            Image(systemName: item.type.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func actionButton(systemName: String, help: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .padding(4)
                .background(Color.secondary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
