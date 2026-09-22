import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SnippetBackupAction: String, Identifiable {
    case export, restore

    var id: String { rawValue }
}

struct SnippetBackupView: View {
    @EnvironmentObject private var manager: ClipboardManager
    @Environment(\.dismiss) private var dismiss
    let action: SnippetBackupAction
    let onComplete: (String) -> Void
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var operation: Task<Void, Never>?

    private var isExport: Bool { action == .export }
    private var canContinue: Bool {
        !isWorking && !manager.isLocked && !manager.isVaultTransitioning
            && !password.isEmpty
            && password.utf8.count <= EncryptedSnippetBackup.maximumPasswordBytes
            && (!isExport || (password.count >= EncryptedSnippetBackup.minimumPasswordCharacters && password == confirmation))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isExport ? "Create Encrypted Backup" : "Restore Encrypted Backup")
                .font(.title2.bold())
            Text(isExport
                 ? "Back up your loaded snippets with a password you can use on any Mac. The password is not saved and cannot be recovered."
                 : "Choose a CoPaRe encrypted backup and enter its password. Snippets are merged with your loaded collection; existing duplicates are skipped.")
                .foregroundStyle(.secondary)

            SecureField("Backup password", text: $password)
                .textContentType(isExport ? .newPassword : .password)
                .disabled(isWorking)
            if isExport {
                SecureField("Repeat password", text: $confirmation)
                    .textContentType(.newPassword)
                    .disabled(isWorking)
                Text("Use at least 12 characters. A long, unique passphrase is recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !confirmation.isEmpty, confirmation != password {
                    Text("The passwords do not match.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("backupError")
            }

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                    Text(isExport ? "Encrypting snippets…" : "Decrypting backup…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { cancelAndDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isExport ? "Save Backup…" : "Choose Backup…") { chooseFileAndTransfer() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canContinue)
            }
        }
        .padding(24)
        .frame(width: 470)
        .onChange(of: manager.isLocked) { _, locked in
            if locked { cancelAndDismiss() }
        }
        .onChange(of: manager.isVaultTransitioning) { _, transitioning in
            if transitioning { cancelAndDismiss() }
        }
        .onDisappear {
            operation?.cancel()
            password = ""
            confirmation = ""
        }
    }

    private func chooseFileAndTransfer() {
        guard canContinue else { return }
        let url: URL
        if isExport {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "CoPaRe Snippets.encrypted.json"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
            url = selectedURL
        } else {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
            url = selectedURL
        }

        let transferPassword = password
        password = ""
        confirmation = ""
        errorMessage = nil
        isWorking = true
        operation = Task { @MainActor in
            defer { isWorking = false }
            do {
                let message: String
                if isExport {
                    try await manager.exportEncryptedSnippets(to: url, password: transferPassword)
                    message = "Encrypted backup saved. Keep its password in a safe place."
                } else {
                    let count = try await manager.importEncryptedSnippets(from: url, password: transferPassword)
                    message = count == 0 ? "No new snippets to restore." : "Restored \(count) snippet\(count == 1 ? "" : "s") from the encrypted backup."
                }
                try Task.checkCancellation()
                onComplete(message)
                dismiss()
            } catch is CancellationError {
                // Dismissal, locking, or cancellation intentionally ends the operation.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelAndDismiss() {
        operation?.cancel()
        password = ""
        confirmation = ""
        dismiss()
    }
}
