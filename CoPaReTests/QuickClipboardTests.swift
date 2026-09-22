import Foundation
import Testing
@testable import CoPaRe

struct QuickClipboardTests {
    @Test func searchUsesOnlyVisibleMetadataAndNeverPayloadContents() throws {
        let payload = ClipboardItemPayload(plainText: "secret body that must not be searched", imagePNGData: nil, filePaths: nil)
        let item = ClipboardHistoryItem(
            type: .text,
            preview: "Deployment checklist",
            encryptedPayload: try EncryptedClipboardPayload.seal(payload),
            digest: "test",
            byteSize: 50,
            origin: .snippet,
            sourceBundleIdentifier: nil,
            tags: ["work"]
        )
        #expect(QuickClipboardSearch.matches(item, query: "  CHECKLIST\n", sourceApplicationName: nil))
        #expect(QuickClipboardSearch.matches(item, query: "#work", sourceApplicationName: nil))
        #expect(QuickClipboardSearch.matches(item, query: "", sourceApplicationName: nil))
        #expect(!QuickClipboardSearch.matches(item, query: "secret body", sourceApplicationName: nil))
    }

    @Test func searchMatchesSourceAppAndFileMetadata() {
        let item = ClipboardHistoryItem(
            type: .file,
            preview: "2 files",
            searchIndex: "proposal.pdf, notes.md",
            digest: "test",
            byteSize: 20,
            sourceBundleIdentifier: "com.example.editor"
        )
        #expect(QuickClipboardSearch.matches(item, query: "proposal", sourceApplicationName: "Example Editor"))
        #expect(QuickClipboardSearch.matches(item, query: "EXAMPLE EDITOR", sourceApplicationName: "Example Editor"))
        #expect(QuickClipboardSearch.matches(item, query: "com.example", sourceApplicationName: nil))
        #expect(!QuickClipboardSearch.matches(item, query: "unrelated", sourceApplicationName: "Example Editor"))
    }

    @Test func selectionSurvivesCaptureChangesAndFallsBackAfterExpiry() {
        let first = UUID(), second = UUID(), inserted = UUID()
        #expect(QuickClipboardSelection.reconciled(nil, in: [first, second]) == first)
        #expect(QuickClipboardSelection.reconciled(second, in: [inserted, first, second]) == second)
        #expect(QuickClipboardSelection.reconciled(second, in: [inserted, first]) == inserted)
        #expect(QuickClipboardSelection.reconciled(first, in: []) == nil)
    }

    @Test func keyboardSelectionClampsAtEdgesAndHandlesNoResults() {
        let first = UUID(), second = UUID(), third = UUID()
        let identifiers = [first, second, third]
        #expect(QuickClipboardSelection.moved(first, in: identifiers, by: 1) == second)
        #expect(QuickClipboardSelection.moved(second, in: identifiers, by: -1) == first)
        #expect(QuickClipboardSelection.moved(first, in: identifiers, by: -1) == first)
        #expect(QuickClipboardSelection.moved(third, in: identifiers, by: 1) == third)
        #expect(QuickClipboardSelection.moved(nil, in: identifiers, by: 1) == first)
        #expect(QuickClipboardSelection.moved(nil, in: identifiers, by: -1) == third)
        #expect(QuickClipboardSelection.moved(first, in: [], by: 1) == nil)
    }
}
