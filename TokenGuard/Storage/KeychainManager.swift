import Foundation
import Security
import LocalAuthentication

protocol KeychainBackingStore: Sendable {
    func add(query: [String: Any]) -> OSStatus
    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus
    func copyMatching(query: [String: Any], result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func delete(query: [String: Any]) -> OSStatus
}

struct SecurityKeychainBackingStore: KeychainBackingStore {
    func add(query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func copyMatching(query: [String: Any], result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query as CFDictionary, result)
    }

    func delete(query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            return "Keychain operation failed with status \(status)."
        case .invalidData:
            return "Credential data was not valid UTF-8."
        }
    }
}

struct KeychainManager: Sendable {
    private let serviceName: String
    private let legacyServiceNames: [String]
    private let accessGroup: String?
    private let backingStore: KeychainBackingStore

    init(
        serviceName: String = "com.palba.TokenGuard.credentials",
        legacyServiceNames: [String] = ["com.palba.UsageTool.credentials"],
        accessGroup: String? = nil,
        backingStore: KeychainBackingStore = SecurityKeychainBackingStore()
    ) {
        self.serviceName = serviceName
        self.legacyServiceNames = legacyServiceNames.filter { $0 != serviceName }
        self.accessGroup = accessGroup
        self.backingStore = backingStore
    }

    func saveSecret(_ secret: String, reference: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(reference: reference)
        let attributes = [
            kSecValueData as String: data
        ]

        let status = backingStore.add(query: query.merging(attributes, uniquingKeysWith: { _, new in new }))
        if status == errSecDuplicateItem {
            let updateStatus = backingStore.update(query: query, attributes: attributes)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func readSecret(reference: String, allowUserInteraction: Bool = true) throws -> String? {
        if let secret = try readSecret(
            reference: reference,
            serviceName: serviceName,
            allowUserInteraction: allowUserInteraction
        ) {
            return secret
        }

        for legacyServiceName in legacyServiceNames {
            guard let legacySecret = try readSecret(
                reference: reference,
                serviceName: legacyServiceName,
                allowUserInteraction: allowUserInteraction
            ) else {
                continue
            }

            try? saveSecret(legacySecret, reference: reference)
            return legacySecret
        }

        return nil
    }

    func deleteSecret(reference: String) throws {
        try deleteSecret(reference: reference, serviceName: serviceName)
        for legacyServiceName in legacyServiceNames {
            try deleteSecret(reference: reference, serviceName: legacyServiceName)
        }
    }

    private func readSecret(reference: String, serviceName: String, allowUserInteraction: Bool) throws -> String? {
        var query = baseQuery(reference: reference)
        query[kSecAttrService as String] = serviceName
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowUserInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: CFTypeRef?
        let status = backingStore.copyMatching(query: query, result: &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.invalidData
            }
            guard let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func deleteSecret(reference: String, serviceName: String) throws {
        var query = baseQuery(reference: reference)
        query[kSecAttrService as String] = serviceName
        let status = backingStore.delete(query: query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(reference: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: reference
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}
