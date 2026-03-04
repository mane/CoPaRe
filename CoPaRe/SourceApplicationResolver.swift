import AppKit
import Foundation

@MainActor
enum SourceApplicationResolver {
    private static var cache: [String: String] = [:]

    static func displayName(for bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return nil
        }

        if let cached = cache[bundleIdentifier] {
            return cached
        }

        let resolved = resolve(bundleIdentifier: bundleIdentifier)
        cache[bundleIdentifier] = resolved
        return resolved
    }

    private static func resolve(bundleIdentifier: String) -> String {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let bundle = Bundle(url: appURL)
        {
            let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            let fallbackName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            let normalized = (displayName ?? fallbackName)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let normalized, !normalized.isEmpty {
                return normalized
            }
        }

        if let lastComponent = bundleIdentifier.split(separator: ".").last {
            return lastComponent.replacingOccurrences(of: "-", with: " ")
        }
        return bundleIdentifier
    }
}
