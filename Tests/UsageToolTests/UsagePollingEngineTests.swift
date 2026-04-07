import Foundation
import XCTest
@testable import UsageTool

@MainActor
final class UsagePollingEngineTests: XCTestCase {
    func testRefreshAllSwitchesActiveCodexConsumerToLiveIdentity() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let firstAccount = Account(
            name: "old@example.com",
            serviceType: .codex,
            credentialRef: "codex-1",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "old@example.com"
            ]
        )
        let secondAccount = Account(
            name: "new@example.com",
            serviceType: .codex,
            credentialRef: "codex-2",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "new@example.com"
            ]
        )

        try accountStore.add(firstAccount)
        try accountStore.add(secondAccount)

        let provider = MockConsumerIdentityProvider(
            identity: ConsumerAccountIdentity(email: "new@example.com", externalID: "acct-2"),
            snapshot: UsageSnapshot(
                accountId: secondAccount.id,
                timestamp: Date(timeIntervalSince1970: 1_710_000_000),
                windows: [
                    UsageWindow(windowType: .rolling5h, used: 42, limit: 100, unit: .percent, resetDate: nil)
                ],
                tier: "Consumer"
            )
        )

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            providers: [.codex: provider],
            serviceRefreshIntervals: [.codex: 300],
            sleep: { _ in }
        )

        await engine.refreshAll()

        XCTAssertEqual(accountStore.activeConsumerAccountID(for: .codex), secondAccount.id)
        XCTAssertEqual(engine.accountStates[secondAccount.id]?.snapshot?.windows.first?.used, 42)
        XCTAssertNil(engine.accountStates[firstAccount.id]?.lastAttemptAt)
        XCTAssertEqual(
            accountStore.accounts.first(where: { $0.id == secondAccount.id })?.consumerExternalID,
            "acct-2"
        )
    }

    func testRefreshSkipsInactiveCodexConsumerAfterIdentitySync() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let firstAccount = Account(
            name: "old@example.com",
            serviceType: .codex,
            credentialRef: "codex-1",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "old@example.com"
            ]
        )
        let secondAccount = Account(
            name: "new@example.com",
            serviceType: .codex,
            credentialRef: "codex-2",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "new@example.com"
            ]
        )

        try accountStore.add(firstAccount)
        try accountStore.add(secondAccount)

        let provider = MockConsumerIdentityProvider(
            identity: ConsumerAccountIdentity(email: "old@example.com", externalID: "acct-1"),
            snapshot: UsageSnapshot(
                accountId: firstAccount.id,
                timestamp: Date(timeIntervalSince1970: 1_710_000_000),
                windows: [
                    UsageWindow(windowType: .rolling5h, used: 17, limit: 100, unit: .percent, resetDate: nil)
                ],
                tier: "Consumer"
            )
        )

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            providers: [.codex: provider],
            serviceRefreshIntervals: [.codex: 300],
            sleep: { _ in }
        )

        await engine.refresh(accountID: secondAccount.id)

        XCTAssertEqual(accountStore.activeConsumerAccountID(for: .codex), firstAccount.id)
        XCTAssertNil(engine.accountStates[secondAccount.id]?.lastAttemptAt)
        XCTAssertEqual(engine.accountStates[firstAccount.id]?.snapshot?.windows.first?.used, nil)
    }
}

private struct MockConsumerIdentityProvider: ServiceProvider, ConsumerAccountDetecting {
    let serviceType: ServiceType = .codex
    let identity: ConsumerAccountIdentity?
    let snapshot: UsageSnapshot

    func fetchUsage(account: Account, credential: String) async throws -> UsageSnapshot {
        _ = credential
        return UsageSnapshot(
            accountId: account.id,
            timestamp: snapshot.timestamp,
            windows: snapshot.windows,
            tier: snapshot.tier,
            breakdown: snapshot.breakdown,
            isStale: snapshot.isStale
        )
    }

    func validateCredentials(account: Account, credential: String) async throws -> Bool {
        _ = account
        _ = credential
        return true
    }

    func currentConsumerIdentity() async throws -> ConsumerAccountIdentity? {
        identity
    }
}
