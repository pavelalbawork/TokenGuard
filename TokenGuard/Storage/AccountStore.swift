import Foundation
import Observation

@MainActor
@Observable
final class AccountStore {
    private static let storageDirectoryName = "TokenGuard"
    private static let legacyStorageDirectoryName = "UsageTool"

    private struct StoragePayload: Codable {
        var accounts: [Account]
        var activeConsumerAccountIDs: [String: UUID]
    }

    private let storageURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    var accounts: [Account]
    private(set) var activeConsumerAccountIDs: [String: UUID]

    init(
        storageURL: URL? = nil,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.storageURL = storageURL ?? AccountStore.defaultStorageURL(fileManager: fileManager)
        self.accounts = []
        self.activeConsumerAccountIDs = [:]
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder.dateEncodingStrategy = .iso8601

        do {
            let payload = try loadPayload()
            self.accounts = Self.migratedAccounts(payload.accounts)
            self.activeConsumerAccountIDs = payload.activeConsumerAccountIDs
        } catch {
            self.accounts = []
            self.activeConsumerAccountIDs = [:]
        }
    }

    // MARK: - Active consumer tracking

    func activeConsumerAccountID(for serviceType: ServiceType) -> UUID? {
        activeConsumerAccountIDs[serviceType.rawValue]
    }

    func setActiveConsumer(_ accountID: UUID, for serviceType: ServiceType) throws {
        var updated = activeConsumerAccountIDs
        updated[serviceType.rawValue] = accountID
        try persist(accounts: accounts, activeConsumerAccountIDs: updated)
        activeConsumerAccountIDs = updated
    }

    // MARK: - CRUD

    func add(_ account: Account) throws {
        var updatedAccounts = accounts
        updatedAccounts.append(account)
        var updatedActive = activeConsumerAccountIDs
        // Auto-activate the first consumer account for each service type
        if account.planType == "consumer",
           updatedActive[account.serviceType.rawValue] == nil {
            updatedActive[account.serviceType.rawValue] = account.id
        }
        try persist(accounts: updatedAccounts, activeConsumerAccountIDs: updatedActive)
        accounts = updatedAccounts
        activeConsumerAccountIDs = updatedActive
    }

    func update(_ account: Account) throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var updatedAccounts = accounts
        updatedAccounts[index] = account
        try persist(accounts: updatedAccounts, activeConsumerAccountIDs: activeConsumerAccountIDs)
        accounts = updatedAccounts
    }

    func remove(accountID: UUID) throws {
        let updatedAccounts = accounts.filter { $0.id != accountID }
        // If we're removing the active consumer, fall back to another consumer for same service type
        var updatedActive = activeConsumerAccountIDs
        for (key, id) in updatedActive where id == accountID {
            let serviceRaw = key
            let remaining = updatedAccounts.filter {
                $0.serviceType.rawValue == serviceRaw && $0.planType == "consumer"
            }
            if let next = remaining.first {
                updatedActive[serviceRaw] = next.id
            } else {
                updatedActive.removeValue(forKey: serviceRaw)
            }
        }
        try persist(accounts: updatedAccounts, activeConsumerAccountIDs: updatedActive)
        accounts = updatedAccounts
        activeConsumerAccountIDs = updatedActive
    }

    func persist() throws {
        try persist(accounts: accounts, activeConsumerAccountIDs: activeConsumerAccountIDs)
    }

    // MARK: - Storage

    private func persist(accounts: [Account], activeConsumerAccountIDs: [String: UUID]) throws {
        let directory = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = StoragePayload(accounts: accounts, activeConsumerAccountIDs: activeConsumerAccountIDs)
        let data = try encoder.encode(payload)
        try data.write(to: storageURL, options: .atomic)
    }

    private func loadPayload() throws -> StoragePayload {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return StoragePayload(accounts: [], activeConsumerAccountIDs: [:])
        }
        let data = try Data(contentsOf: storageURL)
        // Migrate: old format was a bare [Account] array
        if let accounts = try? decoder.decode([Account].self, from: data) {
            let migratedAccounts = Self.migratedAccounts(accounts)
            // Rebuild active map from migrated accounts
            var activeMap: [String: UUID] = [:]
            for account in migratedAccounts where account.planType == "consumer" {
                let key = account.serviceType.rawValue
                if activeMap[key] == nil { activeMap[key] = account.id }
            }
            return StoragePayload(accounts: migratedAccounts, activeConsumerAccountIDs: activeMap)
        }
        let payload = try decoder.decode(StoragePayload.self, from: data)
        let migratedAccounts = Self.migratedAccounts(payload.accounts)
        var activeMap = payload.activeConsumerAccountIDs
        for account in migratedAccounts where account.planType == "consumer" {
            if activeMap[account.serviceType.rawValue] == nil {
                activeMap[account.serviceType.rawValue] = account.id
            }
        }
        return StoragePayload(
            accounts: migratedAccounts,
            activeConsumerAccountIDs: activeMap
        )
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let storageDirectory = appSupport.appendingPathComponent(storageDirectoryName, isDirectory: true)
        let storageURL = storageDirectory.appendingPathComponent("accounts.json", isDirectory: false)
        let legacyURL = appSupport
            .appendingPathComponent(legacyStorageDirectoryName, isDirectory: true)
            .appendingPathComponent("accounts.json", isDirectory: false)

        migrateLegacyFileIfNeeded(from: legacyURL, to: storageURL, fileManager: fileManager)
        return storageURL
    }

    private static func migrateLegacyFileIfNeeded(from legacyURL: URL, to storageURL: URL, fileManager: FileManager) {
        guard !fileManager.fileExists(atPath: storageURL.path),
              fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: legacyURL, to: storageURL)
        } catch {
            try? fileManager.copyItem(at: legacyURL, to: storageURL)
        }
    }

    private static func migratedAccounts(_ accounts: [Account]) -> [Account] {
        accounts.map { account in
            guard account.serviceType == .antigravity, account.planType == nil else {
                return account
            }

            var updated = account
            updated.configuration[Account.ConfigurationKey.planType] = "consumer"
            if updated.configuration[Account.ConfigurationKey.consumerEmail] == nil,
               account.name.contains("@") {
                updated.configuration[Account.ConfigurationKey.consumerEmail] = account.name
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            return updated
        }
    }
}
