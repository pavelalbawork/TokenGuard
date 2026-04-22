import Foundation
import XCTest
@testable import TokenGuard

private struct SnapshotOnlyCodexReader: ConsumerUsageSnapshotReading {
    let windows: [UsageWindow]?

    func windows(for serviceType: ServiceType) throws -> [UsageWindow]? {
        guard serviceType == .codex else { return nil }
        return windows
    }
}

private func makeRateLimitOnlyCodexSession(
    planType: String,
    primaryUsedPercent: Int,
    secondaryUsedPercent: Int
) -> MockCodexAppServerSession {
    MockCodexAppServerSession { line, session in
        guard let data = line.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = payload["id"] as? Int else {
            return
        }

        if id == 1 {
            session.emit(.stdout("""
{"id":1,"result":{"userAgent":"Codex Desktop","codexHome":"/Users/example/.codex","platformFamily":"unix","platformOs":"macos"}}
"""))
        }

        if id == 3 {
            session.emit(.stdout("""
{"id":3,"result":{"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":\(primaryUsedPercent),"windowDurationMins":300,"resetsAt":1775600233},"secondary":{"usedPercent":\(secondaryUsedPercent),"windowDurationMins":10080,"resetsAt":1775754683},"credits":{"hasCredits":false,"unlimited":false,"balance":null},"planType":"\(planType)"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":\(primaryUsedPercent),"windowDurationMins":300,"resetsAt":1775600233},"secondary":{"usedPercent":\(secondaryUsedPercent),"windowDurationMins":10080,"resetsAt":1775754683},"credits":{"hasCredits":false,"unlimited":false,"balance":null},"planType":"\(planType)"}}}}
"""))
        }
    }
}

@MainActor
final class UsagePollingEngineTests: XCTestCase {
    func testRefreshAllSwitchesActiveGeminiConsumerToCurrentIdentity() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let firstAccount = Account(
            name: "old@example.com",
            serviceType: .gemini,
            credentialRef: "gemini-1",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "old@example.com"
            ]
        )
        let secondAccount = Account(
            name: "new@example.com",
            serviceType: .gemini,
            credentialRef: "gemini-2",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "new@example.com"
            ]
        )

        try accountStore.add(firstAccount)
        try accountStore.add(secondAccount)

        let snapshot = UsageSnapshot(
            accountId: secondAccount.id,
            timestamp: Date(timeIntervalSince1970: 1_775_000_000),
            windows: [
                UsageWindow(windowType: .daily, used: 4, limit: 10, unit: .requests, resetDate: nil, label: "Gemini 2.5 Pro")
            ],
            tier: "Gemini Code Assist in Google One AI Pro"
        )
        let provider = MockConsumerIdentityProvider(
            serviceType: .gemini,
            identity: ConsumerAccountIdentity(email: "new@example.com", externalID: nil),
            snapshot: snapshot
        )

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            providers: [.gemini: provider],
            serviceRefreshIntervals: [.gemini: 300],
            sleep: { _ in }
        )

        await engine.refreshAll(force: true)

        XCTAssertEqual(accountStore.activeConsumerAccountID(for: .gemini), secondAccount.id)
        XCTAssertEqual(engine.accountStates[secondAccount.id]?.snapshot?.windows.first?.used, 4)
        XCTAssertNil(engine.accountStates[firstAccount.id]?.lastAttemptAt)
    }

    func testRefreshAllSwitchesActiveClaudeConsumerToCurrentIdentity() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let firstAccount = Account(
            name: "old@example.com",
            serviceType: .claude,
            credentialRef: "claude-1",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "old@example.com"
            ]
        )
        let secondAccount = Account(
            name: "new@example.com",
            serviceType: .claude,
            credentialRef: "claude-2",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "new@example.com"
            ]
        )

        try accountStore.add(firstAccount)
        try accountStore.add(secondAccount)

        let snapshot = UsageSnapshot(
            accountId: secondAccount.id,
            timestamp: Date(timeIntervalSince1970: 1_775_000_000),
            windows: [
                UsageWindow(windowType: .rolling5h, used: 17, limit: 100, unit: .percent, resetDate: nil, label: "5h window")
            ],
            tier: "Pro"
        )
        let provider = MockConsumerIdentityProvider(
            serviceType: .claude,
            identity: ConsumerAccountIdentity(email: "new@example.com", externalID: nil),
            snapshot: snapshot
        )

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            providers: [.claude: provider],
            serviceRefreshIntervals: [.claude: 300],
            sleep: { _ in }
        )

        await engine.refreshAll(force: true)

        XCTAssertEqual(accountStore.activeConsumerAccountID(for: .claude), secondAccount.id)
        XCTAssertEqual(engine.accountStates[secondAccount.id]?.snapshot?.windows.first?.used, 17)
        XCTAssertNil(engine.accountStates[firstAccount.id]?.lastAttemptAt)
    }

    func testRefreshAllSwitchesActiveAntigravityConsumerToCurrentIdentity() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let firstAccount = Account(
            name: "work@example.com",
            serviceType: .antigravity,
            credentialRef: "antigravity-1",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "work@example.com"
            ]
        )
        let secondAccount = Account(
            name: "personal@example.com",
            serviceType: .antigravity,
            credentialRef: "antigravity-2",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "personal@example.com"
            ]
        )

        try accountStore.add(firstAccount)
        try accountStore.add(secondAccount)

        let snapshot = UsageSnapshot(
            accountId: secondAccount.id,
            timestamp: Date(timeIntervalSince1970: 1_775_000_000),
            windows: [
                UsageWindow(windowType: .daily, used: 12, limit: 100, unit: .percent, resetDate: nil, label: "Anthropic (Claude)")
            ],
            tier: "personal@example.com"
        )
        let provider = MockConsumerIdentityProvider(
            serviceType: .antigravity,
            identity: ConsumerAccountIdentity(email: "personal@example.com", externalID: nil),
            snapshot: snapshot
        )

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            providers: [.antigravity: provider],
            serviceRefreshIntervals: [.antigravity: 300],
            sleep: { _ in }
        )

        await engine.refreshAll(force: true)

        XCTAssertEqual(accountStore.activeConsumerAccountID(for: .antigravity), secondAccount.id)
        XCTAssertEqual(engine.accountStates[secondAccount.id]?.snapshot?.windows.first?.used, 12)
        XCTAssertNil(engine.accountStates[firstAccount.id]?.lastAttemptAt)
    }

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
            providers: [
                .codex: OpenAIProvider(
                    codexLiveStateProvider: codexClient,
                    identityReader: CodexAuthIdentityReader(authURL: tempDirectory.appendingPathComponent("missing-auth.json"))
                )
            ],
            serviceRefreshIntervals: [.codex: 300],
            sleep: { _ in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
        defer { engine.stop() }

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
            providers: [
                .codex: OpenAIProvider(
                    codexLiveStateProvider: codexClient,
                    identityReader: CodexAuthIdentityReader(authURL: tempDirectory.appendingPathComponent("missing-auth.json"))
                )
            ],
            serviceRefreshIntervals: [.codex: 300],
            sleep: { _ in }
        )
        defer { engine.stop() }

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

    func testRefreshAllSwitchesCodexFromStaleLiveIdentityToCurrentLocalIdentity() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let oldAccount = Account(
            name: "old@example.com",
            serviceType: .codex,
            credentialRef: "codex-old",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "old@example.com"
            ]
        )
        let newAccount = Account(
            name: "new@example.com",
            serviceType: .codex,
            credentialRef: "codex-new",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "new@example.com"
            ]
        )

        try accountStore.add(oldAccount)
        try accountStore.add(newAccount)

        let lock = NSLock()
        nonisolated(unsafe) var sessionNumber = 0
        let codexClient = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory {
                lock.lock()
                sessionNumber += 1
                let currentSessionNumber = sessionNumber
                lock.unlock()

                if currentSessionNumber == 1 {
                    return makeBootstrapCodexSession(
                        email: "old@example.com",
                        planType: "team",
                        primaryUsedPercent: 12,
                        secondaryUsedPercent: 34
                    )
                }

                return makeBootstrapCodexSession(
                    email: "new@example.com",
                    planType: "team",
                    primaryUsedPercent: 56,
                    secondaryUsedPercent: 78
                )
            },
            now: { Date(timeIntervalSince1970: 1_710_000_000) },
            sleep: { _ in },
            reconnectBackoff: [0]
        )

        let provider = MutableConsumerIdentityProvider(
            serviceType: .codex,
            identity: ConsumerAccountIdentity(email: "old@example.com", externalID: nil),
            snapshot: UsageSnapshot(
                accountId: newAccount.id,
                timestamp: Date(timeIntervalSince1970: 1_710_000_000),
                windows: [],
                tier: nil
            )
        )

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            codexClient: codexClient,
            providers: [.codex: provider],
            serviceRefreshIntervals: [.codex: 300],
            sleep: { _ in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
        defer { engine.stop() }

        engine.start()
        let didSeeOldLiveIdentity = await waitUntil {
            accountStore.activeConsumerAccountID(for: .codex) == oldAccount.id &&
            !engine.isRefreshing
        }

        XCTAssertTrue(didSeeOldLiveIdentity)

        provider.identity = ConsumerAccountIdentity(email: "new@example.com", externalID: nil)

        await engine.refreshAll(force: true)

        let didSwitchToLocalIdentity = await waitUntil {
            accountStore.activeConsumerAccountID(for: .codex) == newAccount.id &&
            engine.accountStates[newAccount.id]?.snapshot?.windows.first?.used == 56
        }

        XCTAssertTrue(didSwitchToLocalIdentity)
        XCTAssertEqual(accountStore.activeConsumerAccountID(for: .codex), newAccount.id)
        XCTAssertEqual(engine.accountStates[newAccount.id]?.snapshot?.windows.first?.used, 56)
    }

    func testCodexConsumerAccountDrivesPollingCadence() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let account = Account(
            name: "codex@example.com",
            serviceType: .codex,
            credentialRef: "codex-1",
            configuration: [
                Account.ConfigurationKey.planType: "consumer"
            ]
        )
        try accountStore.add(account)

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            serviceRefreshIntervals: [.codex: 5],
            refreshIntervalProvider: { nil },
            sleep: { _ in }
        )

        XCTAssertEqual(engine.pollCadence, 5)
    }

    func testCodexLiveErrorFallsBackToSessionSnapshot() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let account = Account(
            name: "codex@example.com",
            serviceType: .codex,
            credentialRef: "codex-1",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "codex@example.com"
            ]
        )
        try accountStore.add(account)

        let codexClient = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory {
                throw ServiceProviderError.unavailable("codex app-server missing")
            },
            sleep: { interval in
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            },
            reconnectBackoff: [0, 60]
        )

        let provider = OpenAIProvider(
            codexLiveStateProvider: codexClient,
            snapshotReader: SnapshotOnlyCodexReader(
                windows: [
                    UsageWindow(
                        windowType: .rolling5h,
                        used: 61,
                        limit: 100,
                        unit: .percent,
                        resetDate: nil
                    )
                ]
            ),
            cliParser: nil,
            identityReader: CodexAuthIdentityReader(
                authURL: tempDirectory.appendingPathComponent("missing-auth.json")
            ),
            now: { Date(timeIntervalSince1970: 1_775_000_000) }
        )

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            codexClient: codexClient,
            providers: [.codex: provider],
            serviceRefreshIntervals: [.codex: 300],
            sleep: { _ in }
        )

        engine.start()

        let didFallback = await waitUntil {
            engine.accountStates[account.id]?.snapshot?.windows.first?.used == 61 &&
            engine.accountStates[account.id]?.errorMessage == "codex app-server missing"
        }

        XCTAssertTrue(didFallback)
        XCTAssertEqual(engine.accountStates[account.id]?.connectionStatus, .error)
    }

    func testRefreshAllRestartsCodexWhenLocalIdentitySwitchesBeforeLiveIdentityLoads() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let oldAccount = Account(
            name: "old@example.com",
            serviceType: .codex,
            credentialRef: "codex-old",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "old@example.com"
            ]
        )
        let newAccount = Account(
            name: "new@example.com",
            serviceType: .codex,
            credentialRef: "codex-new",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "new@example.com"
            ]
        )

        try accountStore.add(oldAccount)
        try accountStore.add(newAccount)

        let lock = NSLock()
        nonisolated(unsafe) var sessionNumber = 0
        let codexClient = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory {
                lock.lock()
                sessionNumber += 1
                let currentSessionNumber = sessionNumber
                lock.unlock()

                if currentSessionNumber == 1 {
                    return makeRateLimitOnlyCodexSession(
                        planType: "team",
                        primaryUsedPercent: 12,
                        secondaryUsedPercent: 34
                    )
                }

                return makeBootstrapCodexSession(
                    email: "new@example.com",
                    planType: "team",
                    primaryUsedPercent: 56,
                    secondaryUsedPercent: 78
                )
            },
            now: { Date(timeIntervalSince1970: 1_710_000_000) },
            sleep: { _ in },
            reconnectBackoff: [0]
        )

        let provider = MutableConsumerIdentityProvider(
            serviceType: .codex,
            identity: ConsumerAccountIdentity(email: "old@example.com", externalID: nil),
            snapshot: UsageSnapshot(
                accountId: oldAccount.id,
                timestamp: Date(timeIntervalSince1970: 1_710_000_000),
                windows: [],
                tier: nil
            )
        )

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            codexClient: codexClient,
            providers: [.codex: provider],
            serviceRefreshIntervals: [.codex: 300],
            sleep: { _ in }
        )

        engine.start()
        let sawInitialActiveAccount = await waitUntil {
            accountStore.activeConsumerAccountID(for: .codex) == oldAccount.id
        }

        XCTAssertTrue(sawInitialActiveAccount)

        provider.identity = ConsumerAccountIdentity(email: "new@example.com", externalID: nil)

        await engine.refreshAll(force: true)

        let didSwitchToNewUsage = await waitUntil {
            accountStore.activeConsumerAccountID(for: .codex) == newAccount.id &&
            engine.accountStates[newAccount.id]?.snapshot?.windows.first?.used == 56
        }

        XCTAssertTrue(didSwitchToNewUsage)
        XCTAssertEqual(accountStore.activeConsumerAccountID(for: .codex), newAccount.id)
        XCTAssertEqual(engine.accountStates[newAccount.id]?.snapshot?.windows.first?.used, 56)
    }

    func testForcedRefreshRestartsCodexSessionWhenLiveIdentityAndUsageAreOutOfSync() async throws {
        throw XCTSkip("Covered by deterministic Codex restart and scheduled-refresh regressions.")
    }

    func testScheduledRefreshRequestsCodexBootstrapWhenConsumerIntervalIsDue() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let account = Account(
            name: "codex@example.com",
            serviceType: .codex,
            credentialRef: "codex-1",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "codex@example.com"
            ]
        )
        try accountStore.add(account)

        final class SessionSequence: @unchecked Sendable {
            private let lock = NSLock()
            private var index = 0
            let sessions: [MockCodexAppServerSession]

            init(sessions: [MockCodexAppServerSession]) {
                self.sessions = sessions
            }

            func next() -> MockCodexAppServerSession {
                lock.lock()
                defer { lock.unlock() }
                let session = sessions[min(index, sessions.count - 1)]
                index += 1
                return session
            }
        }

        let firstSession = makeBootstrapCodexSession(
            email: "codex@example.com",
            planType: "team",
            primaryUsedPercent: 12,
            secondaryUsedPercent: 34
        )
        let secondSession = makeBootstrapCodexSession(
            email: "codex@example.com",
            planType: "team",
            primaryUsedPercent: 61,
            secondaryUsedPercent: 74
        )
        let sequence = SessionSequence(sessions: [firstSession, secondSession])

        let codexClient = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory { sequence.next() },
            sleep: { _ in },
            reconnectBackoff: [0]
        )
        final class RefreshIntervalBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value: TimeInterval?

            init(_ value: TimeInterval?) {
                self.value = value
            }

            func get() -> TimeInterval? {
                lock.lock()
                defer { lock.unlock() }
                return value
            }

            func set(_ newValue: TimeInterval?) {
                lock.lock()
                value = newValue
                lock.unlock()
            }
        }

        let refreshInterval = RefreshIntervalBox(3_600)

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            codexClient: codexClient,
            providers: [
                .codex: OpenAIProvider(
                    codexLiveStateProvider: codexClient,
                    identityReader: CodexAuthIdentityReader(authURL: tempDirectory.appendingPathComponent("missing-auth.json"))
                )
            ],
            serviceRefreshIntervals: [.codex: 300],
            refreshIntervalProvider: { refreshInterval.get() },
            sleep: { _ in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )
        defer { engine.stop() }

        engine.accountStates[account.id] = UsagePollingEngine.AccountRefreshState(
            snapshot: nil,
            errorMessage: nil,
            lastAttemptAt: Date(),
            lastSuccessAt: nil,
            connectionStatus: nil
        )

        engine.start()
        let sawInitialUsage = await waitUntil(timeout: 5) {
            engine.accountStates[account.id]?.snapshot?.windows.first?.used == 12
        }
        XCTAssertTrue(sawInitialUsage)

        refreshInterval.set(0)
        await engine.refreshAll(force: false)

        let sawUpdatedUsage = await waitUntil(timeout: 5) {
            engine.accountStates[account.id]?.snapshot?.windows.first?.used == 61
        }

        XCTAssertTrue(sawUpdatedUsage)
    }

    func testCodexIdentityUpdateDoesNotApplyOldLiveSnapshotToNewAccount() async throws {
        throw XCTSkip("Covered by deterministic Codex restart and account-switch regressions.")
    }

    func testGlobalRefreshIntervalControlsPollableProviderCadence() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())

        let account = Account(
            name: "gemini@example.com",
            serviceType: .gemini,
            credentialRef: "gemini-1",
            configuration: [
                Account.ConfigurationKey.planType: "consumer"
            ]
        )
        try accountStore.add(account)

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            serviceRefreshIntervals: [.gemini: 60],
            refreshIntervalProvider: { 900 },
            sleep: { _ in }
        )

        XCTAssertEqual(engine.pollCadence, 900)
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

    func testStartupResetsExpiredCachedInactiveConsumerSnapshot() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storageURL = tempDirectory.appendingPathComponent("accounts.json")
        let cacheURL = tempDirectory.appendingPathComponent("usage-snapshots.json")
        let accountStore = AccountStore(storageURL: storageURL)
        let keychainManager = KeychainManager(backingStore: InMemoryKeychainBackingStore())
        let snapshotCache = UsageSnapshotCache(storageURL: cacheURL)

        let activeAccount = Account(
            name: "active@example.com",
            serviceType: .gemini,
            credentialRef: "gemini-active",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "active@example.com"
            ]
        )
        let inactiveAccount = Account(
            name: "inactive@example.com",
            serviceType: .gemini,
            credentialRef: "gemini-inactive",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "inactive@example.com"
            ]
        )
        try accountStore.add(activeAccount)
        try accountStore.add(inactiveAccount)
        try accountStore.setActiveConsumer(activeAccount.id, for: .gemini)

        let expiredResetDate = Date(timeIntervalSince1970: 1_710_000_000)
        let cachedSnapshot = UsageSnapshot(
            accountId: inactiveAccount.id,
            timestamp: Date(timeIntervalSince1970: 1_709_999_000),
            windows: [
                UsageWindow(windowType: .daily, used: 7, limit: 10, unit: .requests, resetDate: expiredResetDate, label: "PRO")
            ],
            tier: "Gemini Code Assist"
        )
        try snapshotCache.save(snapshot: cachedSnapshot)

        let engine = UsagePollingEngine(
            accountStore: accountStore,
            keychainManager: keychainManager,
            snapshotCache: snapshotCache,
            providers: [:],
            sleep: { _ in }
        )

        let normalizedWindow = try XCTUnwrap(engine.accountStates[inactiveAccount.id]?.snapshot?.windows.first)
        XCTAssertEqual(normalizedWindow.used, 0, accuracy: 0.1)
        XCTAssertNotNil(normalizedWindow.resetDate)
        XCTAssertGreaterThan(normalizedWindow.resetDate ?? .distantPast, Date())

        let persistedWindow = try XCTUnwrap(try snapshotCache.load()[inactiveAccount.id]?.windows.first)
        XCTAssertEqual(persistedWindow.used, 0, accuracy: 0.1)
        XCTAssertNotNil(persistedWindow.resetDate)
        XCTAssertGreaterThan(persistedWindow.resetDate ?? .distantPast, Date())
    }

    func testSnapshotResettingExpiredWindowsAdvancesRollingWindowAcrossMultiplePeriods() {
        let oldResetDate = Date(timeIntervalSince1970: 1_710_000_000)
        let now = oldResetDate.addingTimeInterval((11 * 60 * 60) + 60)

        let snapshot = UsageSnapshot(
            accountId: UUID(),
            timestamp: oldResetDate.addingTimeInterval(-300),
            windows: [
                UsageWindow(windowType: .rolling5h, used: 88, limit: 100, unit: .percent, resetDate: oldResetDate)
            ],
            tier: "Team"
        )

        let normalized = snapshot.resettingExpiredWindows(now: now)
        let window = normalized.windows[0]

        XCTAssertEqual(window.used, 0, accuracy: 0.1)
        XCTAssertEqual(window.resetDate, oldResetDate.addingTimeInterval(15 * 60 * 60))
    }

    func testUsageSnapshotCacheMigratesLegacySingleFileIntoPerAccountFiles() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let legacyURL = tempDirectory.appendingPathComponent("usage-snapshots.json")
        let accountID = UUID()
        let snapshot = UsageSnapshot(
            accountId: accountID,
            timestamp: Date(timeIntervalSince1970: 1_775_000_000),
            windows: [
                UsageWindow(windowType: .daily, used: 5, limit: 10, unit: .requests, resetDate: nil, label: "PRO")
            ],
            tier: "Gemini Code Assist"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([accountID.uuidString: snapshot]).write(to: legacyURL)

        let cache = UsageSnapshotCache(storageURL: legacyURL)
        let loaded = try cache.load()

        XCTAssertEqual(loaded[accountID]?.windows.first?.used ?? -1, 5, accuracy: 0.1)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.appendingPathComponent(accountID.uuidString).appendingPathExtension("json").path))
    }

    func testUsageSnapshotCacheRemovesOnlyRequestedSnapshotFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let cacheURL = tempDirectory.appendingPathComponent("usage-snapshots")
        let firstSnapshot = UsageSnapshot(
            accountId: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_775_000_000),
            windows: [UsageWindow(windowType: .daily, used: 1, limit: 10, unit: .requests, resetDate: nil, label: "PRO")],
            tier: "Gemini Code Assist"
        )
        let secondSnapshot = UsageSnapshot(
            accountId: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_775_000_001),
            windows: [UsageWindow(windowType: .daily, used: 2, limit: 10, unit: .requests, resetDate: nil, label: "FLASH")],
            tier: "Gemini Code Assist"
        )

        let cache = UsageSnapshotCache(storageURL: cacheURL)
        try cache.save(snapshot: firstSnapshot)
        try cache.save(snapshot: secondSnapshot)

        try cache.remove(accountID: firstSnapshot.accountId)
        let loaded = try cache.load()

        XCTAssertNil(loaded[firstSnapshot.accountId])
        XCTAssertEqual(loaded[secondSnapshot.accountId]?.windows.first?.used ?? -1, 2, accuracy: 0.1)
    }
}

private struct MockConsumerIdentityProvider: ServiceProvider, ConsumerAccountDetecting {
    let serviceType: ServiceType
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

private final class MutableConsumerIdentityProvider: ServiceProvider, ConsumerAccountDetecting, @unchecked Sendable {
    let serviceType: ServiceType
    let snapshot: UsageSnapshot
    private let lock = NSLock()
    private var storedIdentity: ConsumerAccountIdentity?

    var identity: ConsumerAccountIdentity? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedIdentity
        }
        set {
            lock.lock()
            storedIdentity = newValue
            lock.unlock()
        }
    }

    init(serviceType: ServiceType, identity: ConsumerAccountIdentity?, snapshot: UsageSnapshot) {
        self.serviceType = serviceType
        self.storedIdentity = identity
        self.snapshot = snapshot
    }

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
