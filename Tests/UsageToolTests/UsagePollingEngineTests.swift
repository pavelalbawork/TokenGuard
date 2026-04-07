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

        let codexClient = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory {
                makeBootstrapCodexSession(
                    email: "new@example.com",
                    planType: "team",
                    primaryUsedPercent: 42,
                    secondaryUsedPercent: 75
                )
            },
            now: { Date(timeIntervalSince1970: 1_710_000_000) },
            sleep: { _ in },
            reconnectBackoff: [0]
        )

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            codexClient: codexClient,
            providers: [.codex: OpenAIProvider(codexLiveStateProvider: codexClient)],
            serviceRefreshIntervals: [.codex: 300],
            sleep: { _ in }
        )

        engine.start()
        let didUpdate = await waitUntil {
            accountStore.activeConsumerAccountID(for: .codex) == secondAccount.id &&
            engine.accountStates[secondAccount.id]?.snapshot?.windows.first?.used == 42
        }

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(accountStore.activeConsumerAccountID(for: .codex), secondAccount.id)
        XCTAssertEqual(engine.accountStates[secondAccount.id]?.snapshot?.windows.first?.used, 42)
        XCTAssertEqual(accountStore.accounts.first(where: { $0.id == secondAccount.id })?.consumerEmail, "new@example.com")
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

        let codexClient = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory {
                makeBootstrapCodexSession(
                    email: "old@example.com",
                    planType: "team",
                    primaryUsedPercent: 17,
                    secondaryUsedPercent: 80
                )
            },
            now: { Date(timeIntervalSince1970: 1_710_000_000) },
            sleep: { _ in },
            reconnectBackoff: [0]
        )

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            codexClient: codexClient,
            providers: [.codex: OpenAIProvider(codexLiveStateProvider: codexClient)],
            serviceRefreshIntervals: [.codex: 300],
            sleep: { _ in }
        )

        engine.start()
        let didUpdate = await waitUntil {
            accountStore.activeConsumerAccountID(for: .codex) == firstAccount.id &&
            engine.accountStates[firstAccount.id]?.snapshot?.windows.first?.used == 17
        }

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(accountStore.activeConsumerAccountID(for: .codex), firstAccount.id)
        XCTAssertNil(engine.accountStates[secondAccount.id]?.lastAttemptAt)
        XCTAssertEqual(engine.accountStates[firstAccount.id]?.snapshot?.windows.first?.used, 17)
    }

    func testLoadsCachedSnapshotAndMarksItStaleOnRefreshFailure() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let cacheURL = tempDirectory.appendingPathComponent("usage-snapshots.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())
        let snapshotCache = UsageSnapshotCache(storageURL: cacheURL)

        let account = Account(
            name: "pavelalbawork@gmail.com",
            serviceType: .claude,
            credentialRef: "claude-1",
            configuration: [
                Account.ConfigurationKey.planType: "consumer"
            ]
        )
        try accountStore.add(account)

        let cachedSnapshot = UsageSnapshot(
            accountId: account.id,
            timestamp: Date(timeIntervalSince1970: 1_775_000_000),
            windows: [
                UsageWindow(windowType: .rolling5h, used: 40, limit: 100, unit: .percent, resetDate: nil)
            ],
            tier: "Pro"
        )
        try snapshotCache.save(snapshot: cachedSnapshot)

        let provider = MockFailingProvider(serviceType: .claude, message: "Claude live usage is temporarily rate-limited.")

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            snapshotCache: snapshotCache,
            providers: [.claude: provider],
            serviceRefreshIntervals: [.claude: 300],
            sleep: { _ in }
        )

        XCTAssertEqual(engine.accountStates[account.id]?.snapshot?.windows.first?.used ?? -1, 40, accuracy: 0.1)

        await engine.refresh(accountID: account.id)

        XCTAssertEqual(engine.accountStates[account.id]?.snapshot?.isStale, true)
        XCTAssertEqual(engine.accountStates[account.id]?.errorMessage, "Claude live usage is temporarily rate-limited.")
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

private struct MockFailingProvider: ServiceProvider {
    let serviceType: ServiceType
    let message: String

    func fetchUsage(account: Account, credential: String) async throws -> UsageSnapshot {
        _ = account
        _ = credential
        throw ServiceProviderError.unavailable(message)
    }

    func validateCredentials(account: Account, credential: String) async throws -> Bool {
        _ = account
        _ = credential
        return false
    }
}
