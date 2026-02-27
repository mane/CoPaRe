import CryptoKit
import Foundation
import Security

enum KeychainKeyProviderError: Error {
    case invalidKeyData
    case keychainFailure(OSStatus)
}

struct KeychainKeyProvider {
    private let service: String
    private let account = "clipboard-history-encryption-key"

    nonisolated init(service: String = "io.copare.app") {
        self.service = service
    }

    nonisolated func loadOrCreateKey() throws -> SymmetricKey {
        if let existingData = try readKeyData() {
            guard existingData.count == 32 else {
                throw KeychainKeyProviderError.invalidKeyData
            }
            return SymmetricKey(data: existingData)
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try saveKeyData(keyData)
        return newKey
    }

    private nonisolated func readKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

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

    private nonisolated func saveKeyData(_ data: Data) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        var status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
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
}
