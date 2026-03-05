import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum KeychainKeyProviderError: Error {
    case invalidKeyData
    case keychainFailure(OSStatus)
    case accessControlCreationFailed
}

struct KeychainKeyProvider {
    private nonisolated static let cacheLock = NSLock()
    private nonisolated(unsafe) static var cachedKeyDataByService: [String: Data] = [:]

    private let service: String
    private let requiresUserPresence: Bool
    private let cacheInMemory: Bool
    private let account = "clipboard-history-encryption-key"
    private let operationPrompt = "Authenticate to access saved CoPaRe snippets"

    nonisolated init(
        service: String = "io.copare.app",
        requiresUserPresence: Bool = false,
        cacheInMemory: Bool = true
    ) {
        self.service = service
        self.requiresUserPresence = requiresUserPresence
        self.cacheInMemory = cacheInMemory
    }

    nonisolated func loadOrCreateKey(authenticationContext: LAContext? = nil) throws -> SymmetricKey {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }

        if cacheInMemory, !requiresUserPresence, let cachedData = Self.cachedKeyDataByService[service] {
            guard cachedData.count == 32 else {
                Self.cachedKeyDataByService[service] = nil
                throw KeychainKeyProviderError.invalidKeyData
            }

            return SymmetricKey(data: cachedData)
        }

        if migrationCompleted {
            if let existingData = try readKeyData(
                useDataProtectionKeychain: true,
                authenticationContext: authenticationContext
            ) {
                guard existingData.count == 32 else {
                    throw KeychainKeyProviderError.invalidKeyData
                }

                if cacheInMemory, !requiresUserPresence {
                    Self.cachedKeyDataByService[service] = existingData
                }
                return SymmetricKey(data: existingData)
            }
        } else {
            if let legacyData = try readKeyData(
                useDataProtectionKeychain: false,
                authenticationContext: authenticationContext
            ) {
                guard legacyData.count == 32 else {
                    throw KeychainKeyProviderError.invalidKeyData
                }

                try saveKeyData(
                    legacyData,
                    useDataProtectionKeychain: true,
                    authenticationContext: authenticationContext
                )
                markMigrationCompleted()
                if cacheInMemory, !requiresUserPresence {
                    Self.cachedKeyDataByService[service] = legacyData
                }
                return SymmetricKey(data: legacyData)
            }

            if let existingData = try readKeyData(
                useDataProtectionKeychain: true,
                authenticationContext: authenticationContext
            ) {
                guard existingData.count == 32 else {
                    throw KeychainKeyProviderError.invalidKeyData
                }

                markMigrationCompleted()
                if cacheInMemory, !requiresUserPresence {
                    Self.cachedKeyDataByService[service] = existingData
                }
                return SymmetricKey(data: existingData)
            }
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try saveKeyData(
            keyData,
            useDataProtectionKeychain: true,
            authenticationContext: authenticationContext
        )
        markMigrationCompleted()
        if cacheInMemory, !requiresUserPresence {
            Self.cachedKeyDataByService[service] = keyData
        }
        return newKey
    }

    nonisolated func deleteKey() throws {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if requiresUserPresence {
            query[kSecUseAuthenticationContext as String] = authenticationContext()
        }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainKeyProviderError.keychainFailure(status)
        }

        markMigrationCompleted()
        Self.cachedKeyDataByService[service] = nil
    }

    private nonisolated var migrationCompleted: Bool {
        UserDefaults.standard.bool(forKey: migrationDefaultsKey)
    }

    private nonisolated var migrationDefaultsKey: String {
        "KeychainKeyProvider.DataProtectionMigrated.\(service)"
    }

    private nonisolated func markMigrationCompleted() {
        UserDefaults.standard.set(true, forKey: migrationDefaultsKey)
    }

    private nonisolated func readKeyData(
        useDataProtectionKeychain: Bool,
        authenticationContext: LAContext?
    ) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: useDataProtectionKeychain,
        ]

        if requiresUserPresence {
            query[kSecUseAuthenticationContext as String] = resolvedAuthenticationContext(authenticationContext)
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainKeyProviderError.keychainFailure(status)
        }
    }

    private nonisolated func saveKeyData(
        _ data: Data,
        useDataProtectionKeychain: Bool,
        authenticationContext: LAContext?
    ) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecUseDataProtectionKeychain as String: useDataProtectionKeychain,
        ]

        if requiresUserPresence {
            guard let accessControl = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .userPresence,
                nil
            ) else {
                throw KeychainKeyProviderError.accessControlCreationFailed
            }

            query[kSecAttrAccessControl as String] = accessControl
            query[kSecUseAuthenticationContext as String] = resolvedAuthenticationContext(authenticationContext)
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            var updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecUseDataProtectionKeychain as String: useDataProtectionKeychain,
            ]
            if requiresUserPresence {
                updateQuery[kSecUseAuthenticationContext as String] = resolvedAuthenticationContext(authenticationContext)
            }
            let attributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            status = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        }

        guard status == errSecSuccess else {
            query[kSecValueData as String] = nil
            throw KeychainKeyProviderError.keychainFailure(status)
        }
    }

    private nonisolated func resolvedAuthenticationContext(_ context: LAContext?) -> LAContext {
        context ?? authenticationContext()
    }

    private nonisolated func authenticationContext() -> LAContext {
        let context = LAContext()
        context.localizedReason = operationPrompt
        return context
    }
}
