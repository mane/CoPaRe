import Foundation

extension String {
    func condensingWhitespace() -> String {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
    }

    func previewSnippet(maxLength: Int = 140) -> String {
        let normalized = condensingWhitespace()
        guard normalized.count > maxLength else {
            return normalized
        }
        let prefixText = normalized.prefix(maxLength)
        return "\(prefixText)…"
    }
}
