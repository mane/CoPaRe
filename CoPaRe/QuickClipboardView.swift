import AppKit
import SwiftUI

/// The quick picker searches only the metadata already shown by CoPaRe. Opening it
/// never decrypts payloads or changes the search/filter in the main window.
enum QuickClipboardSearch {
    nonisolated static func matches(
        _ item: ClipboardHistoryItem,
        query: String,
        sourceApplicationName: String?
    ) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return item.preview.lowercased().contains(query)
            || item.searchIndex?.lowercased().contains(query) == true
            || item.tags.contains { $0.contains(query) || "#\($0)".contains(query) }
            || sourceApplicationName?.lowercased().contains(query) == true
            || item.sourceBundleIdentifier?.lowercased().contains(query) == true
    }
}

enum QuickClipboardSelection {
    nonisolated static func reconciled(_ current: UUID?, in identifiers: [UUID]) -> UUID? {
        if let current, identifiers.contains(current) { return current }
        return identifiers.first
    }

    nonisolated static func moved(_ current: UUID?, in identifiers: [UUID], by offset: Int) -> UUID? {
        guard !identifiers.isEmpty else { return nil }
        guard let current, let index = identifiers.firstIndex(of: current) else {
            return offset < 0 ? identifiers.last : identifiers.first
        }
        return identifiers[min(max(index + offset, 0), identifiers.count - 1)]
    }
}

struct QuickClipboardView: View {
    @ObservedObject var manager: ClipboardManager
    let onCopied: () -> Void
    let onDismiss: () -> Void
    let onOpenMainWindow: () -> Void
    let onUnlock: () -> Void

    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var copyFailed = false

    private var results: [ClipboardHistoryItem] {
        guard !manager.isLocked, !manager.isVaultTransitioning else { return [] }
        return manager.items.filter {
            QuickClipboardSearch.matches(
                $0,
                query: query,
                sourceApplicationName: manager.sourceApplicationName(for: $0)
            )
        }
    }

    private var resultIDs: [UUID] { results.map(\.id) }

    var body: some View {
        VStack(spacing: 0) {
            if manager.isLocked || manager.isVaultTransitioning {
                lockedContent
            } else {
                searchField
                Divider()
                resultsContent
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 420)
        .background(.regularMaterial)
        .onAppear { reconcileSelection() }
        .onChange(of: query) { _, _ in
            selectedID = resultIDs.first
            copyFailed = false
        }
        .onChange(of: resultIDs) { _, _ in reconcileSelection() }
        .onChange(of: manager.isLocked) { _, _ in
            query = ""
            copyFailed = false
            reconcileSelection()
        }
        .onExitCommand(perform: onDismiss)
    }

    private var searchField: some View {
        QuickClipboardSearchField(
            text: $query,
            onMove: { offset in
                selectedID = QuickClipboardSelection.moved(selectedID, in: resultIDs, by: offset)
            },
            onSubmit: copySelection,
            onCancel: onDismiss
        )
        .frame(height: 30)
        .padding(16)
    }

    private var resultsContent: some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No clipboard history yet" : "No matching items",
                    systemImage: query.isEmpty ? "clipboard" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Copy something to see it here." : "Try a title, tag or source app.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(results) { item in
                                Button { copy(item) } label: {
                                    resultRow(item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Copy \(item.preview)")
                                .accessibilityAddTraits(selectedID == item.id ? .isSelected : [])
                                .id(item.id)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedID) { _, identifier in
                        if let identifier { proxy.scrollTo(identifier, anchor: .center) }
                    }
                }
            }
            if copyFailed {
                Text("This item could not be copied. Please try another item.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("QuickClipboardCopyError")
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func resultRow(_ item: ClipboardHistoryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.isSnippet ? "text.badge.star" : item.type.symbolName)
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview.isEmpty ? "(empty)" : item.preview)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.isSnippet ? "Snippet" : (manager.sourceApplicationName(for: item) ?? item.type.label))
                    ForEach(item.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if selectedID == item.id {
                Image(systemName: "return")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedID == item.id ? Color.accentColor.opacity(0.16) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var lockedContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(manager.isVaultTransitioning ? "Securing your clipboard…" : "CoPaRe is locked")
                .font(.headline)
            if manager.isVaultTransitioning {
                ProgressView().controlSize(.small)
            } else {
                Button("Unlock CoPaRe", action: onUnlock)
                    .keyboardShortcut(.defaultAction)
                Text("Authenticate in the main window to access your items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !manager.isLocked, !manager.isVaultTransitioning {
                Text("↑↓ Select  ·  ↩ Copy  ·  esc Close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("esc Close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open CoPaRe", action: onOpenMainWindow)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func reconcileSelection() {
        selectedID = QuickClipboardSelection.reconciled(selectedID, in: resultIDs)
    }

    private func copySelection() {
        guard let identifier = QuickClipboardSelection.reconciled(selectedID, in: resultIDs),
              let item = results.first(where: { $0.id == identifier }) else { return }
        copy(item)
    }

    private func copy(_ item: ClipboardHistoryItem) {
        // Re-resolve the item: capture expiry, a wipe or a lock may have removed it
        // after the row was rendered. Never copy from a stale view snapshot.
        guard let currentItem = manager.item(with: item.id), manager.copyToClipboard(currentItem) else {
            copyFailed = true
            NSSound.beep()
            return
        }
        onCopied()
    }
}

private struct QuickClipboardSearchField: NSViewRepresentable {
    @Binding var text: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusedSearchField()
        field.placeholderString = "Search history, snippets, tags or apps"
        field.font = .systemFont(ofSize: 16)
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("QuickClipboardSearch")
        field.setAccessibilityLabel("Search clipboard history")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: QuickClipboardSearchField
        init(_ parent: QuickClipboardSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Leave marked text to the input method so Return/arrows never copy a
            // different item while the user is composing an accented/CJK query.
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
            default:
                return false
            }
            return true
        }
    }

    @MainActor
    private final class FocusedSearchField: NSSearchField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.initialFirstResponder = self
            window.makeFirstResponder(self)
        }
    }
}
