import Combine
import Foundation

/// Owns only the request state. Recognized text is handed directly to the
/// explicit copy action and is never retained as searchable history or UI state.
@MainActor
final class ImageTextExtractionController: ObservableObject {
    enum Status: Equatable {
        case idle
        case recognizing
        case copied
        case noText
        case failed
    }

    typealias Recognizer = @Sendable (Data) async throws -> String

    @Published private(set) var status: Status = .idle
    private let recognize: Recognizer
    private var requestID: UUID?
    private var extractionTask: Task<Void, Never>?

    init(recognize: @escaping Recognizer = { data in
        try await ImageOCRService().extractText(fromPNGData: data)
    }) {
        self.recognize = recognize
    }

    @discardableResult
    func extractAndCopy(imageData: Data, copy: @escaping @MainActor (String) -> Bool) -> Task<Void, Never> {
        cancel()
        let id = UUID()
        requestID = id
        status = .recognizing
        let recognize = recognize
        let task = Task { @MainActor [weak self] in
            do {
                let text = try await recognize(imageData)
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.status = copy(text) ? .copied : .idle
                self.requestID = nil
                self.extractionTask = nil
            } catch {
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.status = (error as? ImageTextExtractionError) == .noText ? .noText : .failed
                self.requestID = nil
                self.extractionTask = nil
            }
        }
        extractionTask = task
        return task
    }

    func cancel() {
        requestID = nil
        extractionTask?.cancel()
        extractionTask = nil
        status = .idle
    }
}
