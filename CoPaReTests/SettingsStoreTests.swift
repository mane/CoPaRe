import Foundation
import Testing
@testable import CoPaRe

@MainActor
struct SettingsStoreTests {
    @Test func loadsNormalizedCaptureSettingsFromDefaults() {
        withDefaults { defaults in
            defaults.set(" COM.EXAMPLE.SECRET \r\ncom.example.secret\ncom.example.other\n", forKey: "excludedAppsRawText")
            defaults.set("""
                # Ignored comment
                COM.EXAMPLE.EDITOR = text-only ttl:15m
                com.example.editor ignore
                com.example.chat ttl=1h
                """, forKey: "appCaptureRulesRawText")

            let settings = SettingsStore(defaults: defaults)

            #expect(settings.excludedAppsRawText == "com.example.secret\ncom.example.other")
            #expect(settings.excludedBundleIdentifiers == Set(["com.example.secret", "com.example.other"]))
            #expect(settings.appCaptureRules.count == 2)
            #expect(settings.appCaptureRule(for: "COM.EXAMPLE.EDITOR") == AppCaptureRule(
                bundleIdentifier: "com.example.editor",
                ignoresCapture: false,
                textOnly: true,
                ttl: .fifteenMinutes
            ))
            #expect(settings.appCaptureRule(for: "com.example.chat")?.ttl == .oneHour)
            #expect(settings.appCaptureRule(for: nil) == nil)
            #expect(settings.appCaptureRule(for: "com.example.missing") == nil)
        }
    }

    @Test func excludedAppsReflectEditsBeforeNotifyingObservers() {
        withDefaults { defaults in
            defaults.set("com.example.old", forKey: "excludedAppsRawText")
            let settings = SettingsStore(defaults: defaults)
            let original = settings.excludedBundleIdentifiers
            var observedIdentifiers = [Set<String>]()
            settings.onChange = {
                observedIdentifiers.append(settings.excludedBundleIdentifiers)
            }
            defer { settings.onChange = nil }

            settings.excludedAppsRawText = " COM.EXAMPLE.NEW \ncom.example.new\n com.example.other "

            let expected = Set(["com.example.new", "com.example.other"])
            #expect(settings.excludedBundleIdentifiers == expected)
            #expect(original == Set(["com.example.old"]))
            #expect(observedIdentifiers == [expected])
            #expect(defaults.string(forKey: "excludedAppsRawText") == "com.example.new\ncom.example.other")

            settings.excludedAppsRawText = "com.example.new\ncom.example.other"
            #expect(observedIdentifiers.count == 1)

            settings.excludedAppsRawText = ""
            #expect(settings.excludedBundleIdentifiers.isEmpty)
            #expect(observedIdentifiers == [expected, Set<String>()])
            #expect(defaults.string(forKey: "excludedAppsRawText") == "")
        }
    }

    @Test func captureRulesReflectEditsBeforeNotifyingObservers() {
        withDefaults { defaults in
            defaults.set("com.example.old ignore", forKey: "appCaptureRulesRawText")
            let settings = SettingsStore(defaults: defaults)
            let original = settings.appCaptureRules
            var observedRules = [[String: AppCaptureRule]]()
            settings.onChange = {
                observedRules.append(settings.appCaptureRules)
            }
            defer { settings.onChange = nil }

            settings.appCaptureRulesRawText = " COM.EXAMPLE.NEW text-only ttl:1h \n# Comment\n"

            let expected = ["com.example.new": AppCaptureRule(
                bundleIdentifier: "com.example.new",
                ignoresCapture: false,
                textOnly: true,
                ttl: .oneHour
            )]
            #expect(settings.appCaptureRules == expected)
            #expect(settings.appCaptureRule(for: "com.example.old") == nil)
            #expect(original["com.example.old"]?.ignoresCapture == true)
            #expect(observedRules == [expected])
            #expect(defaults.string(forKey: "appCaptureRulesRawText") == "com.example.new text-only ttl:1h")

            settings.appCaptureRulesRawText = "com.example.new text-only ttl:1h"
            #expect(observedRules.count == 1)

            settings.appCaptureRulesRawText = "# No remaining rules\n   "
            #expect(settings.appCaptureRules.isEmpty)
            #expect(settings.appCaptureRule(for: "com.example.new") == nil)
            #expect(observedRules == [expected, [:]])
            #expect(defaults.string(forKey: "appCaptureRulesRawText") == "")
        }
    }

    @Test(arguments: [" ", "=", ",", ";"])
    func duplicateRulesKeepTheFirstRuleAcrossSeparators(separator: String) {
        withDefaults { defaults in
            let settings = SettingsStore(defaults: defaults)
            settings.appCaptureRulesRawText = """
                # Rules accept several separators
                COM.EXAMPLE.EDITOR\(separator)text-only,ttl:30s
                com.example.editor ignore;ttl:1d
                """

            #expect(settings.appCaptureRules.count == 1)
            #expect(settings.appCaptureRule(for: "com.example.editor") == AppCaptureRule(
                bundleIdentifier: "com.example.editor",
                ignoresCapture: false,
                textOnly: true,
                ttl: .thirtySeconds
            ))
            #expect(settings.appCaptureRulesRawText.components(separatedBy: .newlines).count == 1)
        }
    }

    @Test func editingOneCaptureSettingPreservesTheOther() {
        withDefaults { defaults in
            defaults.set("com.example.secret", forKey: "excludedAppsRawText")
            defaults.set("com.example.editor text-only ttl:5m", forKey: "appCaptureRulesRawText")
            let settings = SettingsStore(defaults: defaults)
            let originalIdentifiers = settings.excludedBundleIdentifiers
            let originalRules = settings.appCaptureRules

            settings.excludedAppsRawText = "com.example.other"
            #expect(settings.appCaptureRules == originalRules)

            settings.appCaptureRulesRawText = "com.example.chat skip"
            #expect(settings.excludedBundleIdentifiers == Set(["com.example.other"]))
            #expect(settings.appCaptureRule(for: "com.example.chat")?.ignoresCapture == true)
            #expect(originalIdentifiers == Set(["com.example.secret"]))
            #expect(originalRules["com.example.editor"]?.ttl == .fiveMinutes)
        }
    }

    private func withDefaults(_ operation: (UserDefaults) -> Void) {
        let suiteName = "io.copare.settings-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        operation(defaults)
    }
}
