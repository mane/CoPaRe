import AppKit
import SwiftUI

struct SnippetEditorDraft: Identifiable {
    enum Mode {
        case create
        case edit(UUID)
        case duplicate(UUID)
        case promote(UUID)

        var sourceItemID: UUID? {
            switch self {
            case .create: nil
            case .edit(let id), .duplicate(let id), .promote(let id): id
            }
        }

        var heading: String {
            switch self {
            case .create: "New Snippet"
            case .edit: "Edit Snippet"
            case .duplicate: "Duplicate Snippet"
            case .promote: "Save as Snippet"
            }
        }
    }

    let id = UUID()
    let mode: Mode
    var title = ""
    var body = ""
    var tags = ""

    var canSave: Bool {
        !body.replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.count <= 80
    }
}

struct SnippetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: SnippetEditorDraft
    let persistsSnippets: Bool
    let onSave: (SnippetEditorDraft) -> Bool
    @State private var saveFailed = false
    @State private var isApplicationActive = NSApp.isActive
    @FocusState private var titleFocused: Bool

    var body: some View {
        Group {
            if isApplicationActive {
                editorContent
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.title)
                    Text("Snippet editing is hidden while CoPaRe is inactive.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(width: 520, height: 450)
            }
        }
        .onAppear { titleFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            isApplicationActive = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isApplicationActive = true
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.mode.heading)
                .font(.title3.bold())

            TextField("Title (optional, up to 80 characters)", text: $draft.title)
                .focused($titleFocused)
                .accessibilityIdentifier("snippetTitle")

            TextField("Tags, separated by commas or spaces", text: $draft.tags)
                .accessibilityIdentifier("snippetTags")

            Text("Snippet body")
                .font(.subheadline.weight(.semibold))

            TextEditor(text: $draft.body)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .frame(minHeight: 180)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.9)
                )
                .accessibilityIdentifier("snippetBody")

            Text(persistsSnippets
                 ? "Saving keeps this snippet in your encrypted local vault until you delete it. Its title and tags appear in the list."
                 : "Snippet saving to disk is off. This snippet will remain available only during this session. Its title and tags appear in the list.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if draft.title.count > 80 {
                Text("Shorten the title to 80 characters or fewer.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if saveFailed {
                Text("The snippet could not be saved. Its source may no longer be available.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Snippet") {
                    if onSave(draft) {
                        dismiss()
                    } else {
                        saveFailed = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave)
                .accessibilityIdentifier("saveSnippet")
            }
        }
        .padding(18)
        .frame(width: 520, height: 450)
    }
}
