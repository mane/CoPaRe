import Foundation

enum SensitiveContentDetector {
    private static let keywords = [
        "password",
        "passwd",
        "otp",
        "2fa",
        "totp",
        "api key",
        "secret",
        "private key",
        "bearer ",
        "session token",
    ]

    static func shouldBlock(text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 6 else {
            return false
        }

        let lowercased = normalized.lowercased()
        if keywords.contains(where: { lowercased.contains($0) }) {
            return true
        }

        if normalized.range(
            of: #"^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if normalized.range(
            of: #"(?i)(sk_live|ghp_|xox[baprs]-|AKIA)[A-Za-z0-9_\-]{10,}"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if normalized.range(
            of: #"(?i)-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if normalized.range(
            of: #"^[A-Za-z0-9+/_\-]{32,}={0,2}$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if normalized.range(of: #"^\d{6}$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}
