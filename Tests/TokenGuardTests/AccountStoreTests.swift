import Foundation
import XCTest
@testable import TokenGuard

@MainActor
final class AccountStoreTests: XCTestCase {
    func testAddDoesNotMutateInMemoryAccountsWhenPersistFails() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let store = AccountStore(storageURL: storageURL)
        let account = Account(name: "Claude", serviceType: .claude, credentialRef: "claude-ref")

        try makeDirectoryReadOnly(tempDirectory)
        defer { try? makeDirectoryWritable(tempDirectory) }

        XCTAssertThrowsError(try store.add(account))
        XCTAssertTrue(store.accounts.isEmpty)
    }

    func testUpdateDoesNotMutateInMemoryAccountsWhenPersistFails() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let originalAccount = Account(name: "Antigravity", serviceType: .antigravity, credentialRef: "antigravity-ref")
        let encoded = try JSONEncoder().encode([originalAccount])
        try encoded.write(to: storageURL)

        let store = AccountStore(storageURL: storageURL)
        var updatedAccount = originalAccount
        updatedAccount.configuration[Account.ConfigurationKey.googleRequestLimit] = "100"

        try makeDirectoryReadOnly(tempDirectory)
        defer { try? makeDirectoryWritable(tempDirectory) }

        XCTAssertThrowsError(try store.update(updatedAccount))
        XCTAssertEqual(store.accounts.first?.configuration[Account.ConfigurationKey.googleRequestLimit], nil)
    }

    func testMigratesLegacyAntigravityAccountsToConsumerPlan() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let legacyAccount = Account(
            name: "pavelalbawork@gmail.com",
            serviceType: .antigravity,
            credentialRef: "antigravity-ref"
        )
        let encoded = try JSONEncoder().encode([legacyAccount])
        try encoded.write(to: storageURL)

        let store = AccountStore(storageURL: storageURL)

        XCTAssertEqual(store.accounts.first?.planType, "consumer")
        XCTAssertEqual(store.accounts.first?.consumerEmail, "pavelalbawork@gmail.com")
        XCTAssertEqual(store.activeConsumerAccountID(for: .antigravity), legacyAccount.id)
    }

    private func makeDirectoryReadOnly(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path)
    }

    private func makeDirectoryWritable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
