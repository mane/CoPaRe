import AppKit
import SwiftUI

struct ClipboardRowView: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leadingVisual

            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview.isEmpty ? "(empty)" : item.preview)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(item.createdAt, style: .time)
                        .foregroundStyle(.secondary)

                    Text("\(item.byteSize) B")
                        .foregroundStyle(.secondary)

                    if item.isPinned {
                        Label("Pinned", systemImage: "pin.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy again")

                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin" : "Pin")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        )
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
           let data = item.imagePNGData,
           let image = NSImage(data: data)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        } else {
            Image(systemName: item.type.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
        }
    }
}
