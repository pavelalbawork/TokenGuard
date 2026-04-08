import Foundation
import XCTest
@testable import TokenGuard

private struct MockConsumerSnapshotReader: ConsumerUsageSnapshotReading {
    let windowsToReturn: [UsageWindow]?

    func windows(for serviceType: ServiceType) throws -> [UsageWindow]? {
        guard serviceType == .codex else { return nil }
        return windowsToReturn
    }
}

private struct MockCodexLiveStateProvider: CodexLiveStateProviding {
    let state: CodexLiveState

    func currentState() async -> CodexLiveState {
        state
    }
}

final class OpenAIProviderTests: XCTestCase {
    func testConsumerUsagePrefersAppServerSnapshotOverSessionFallback() async throws {
        let liveWindows = [
            UsageWindow(
                windowType: .rolling5h,
                used: 18,
                limit: 100,
                unit: .percent,
                resetDate: nil
            )
        ]
        let cliWindows = [
            UsageWindow(
                windowType: .rolling5h,
                used: 12,
                limit: 100,
                unit: .percent,
                resetDate: nil
            )
        ]
        let snapshotWindows = [
            UsageWindow(
                windowType: .rolling5h,
                used: 88,
                limit: 100,
                unit: .percent,
                resetDate: nil
            )
        ]

        let provider = OpenAIProvider(
            codexLiveStateProvider: MockCodexLiveStateProvider(
                state: CodexLiveState(
                    snapshot: CodexConsumerSnapshot(
                        windows: liveWindows,
                        identity: ConsumerAccountIdentity(email: "live@example.com", externalID: nil),
                        tier: "Team"
                    ),
                    identity: ConsumerAccountIdentity(email: "live@example.com", externalID: nil),
                    status: .live,
                    lastUpdateAt: Date(timeIntervalSince1970: 1_775_000_000),
                    lastErrorText: nil
                )
            ),
            snapshotReader: MockConsumerSnapshotReader(windowsToReturn: snapshotWindows),
            cliParser: MockCLIParser(windows: cliWindows),
            identityReader: CodexAuthIdentityReader(
                authURL: URL(fileURLWithPath: "/tmp/nonexistent-codex-auth.json")
            ),
            now: { Date(timeIntervalSince1970: 1_775_000_000) }
        )

        let account = Account(
            name: "codex@example.com",
            serviceType: .codex,
            credentialRef: "codex-test",
            configuration: [
                Account.ConfigurationKey.planType: "consumer"
            ]
        )

        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows.first?.used ?? -1, 18, accuracy: 0.1)
        XCTAssertEqual(snapshot.windows.first?.unit, .percent)
        XCTAssertEqual(snapshot.tier, "Team")
    }

    func testConsumerIdentityPrefersLiveAppServerIdentity() async throws {
        let provider = OpenAIProvider(
            codexLiveStateProvider: MockCodexLiveStateProvider(
                state: CodexLiveState(
                    snapshot: CodexConsumerSnapshot(
                        windows: [],
                        identity: ConsumerAccountIdentity(email: "live@example.com", externalID: nil),
                        tier: "Team"
                    ),
                    identity: ConsumerAccountIdentity(email: "live@example.com", externalID: nil),
                    status: .live,
                    lastUpdateAt: nil,
                    lastErrorText: nil
                )
            ),
            snapshotReader: MockConsumerSnapshotReader(windowsToReturn: nil),
            cliParser: nil,
            identityReader: CodexAuthIdentityReader(
                authURL: URL(fileURLWithPath: "/tmp/nonexistent-codex-auth.json")
            ),
            now: { Date(timeIntervalSince1970: 1_775_000_000) }
        )

        let identity = try await provider.currentConsumerIdentity()

        XCTAssertEqual(identity?.email, "live@example.com")
    }

    func testCodexClientParsesBootstrapAndLaterRateLimitUpdate() async throws {
        let session = makeBootstrapCodexSession(
            email: "live@example.com",
            planType: "team",
            primaryUsedPercent: 32,
            secondaryUsedPercent: 94
        )
        let client = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory { session },
            sleep: { _ in },
            reconnectBackoff: [0]
        )

        await client.start()

        var didBootstrap = false
        for _ in 0..<50 {
            let state = await client.currentState()
            if state.snapshot?.windows.first?.used == 32 {
                didBootstrap = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(didBootstrap)

        session.emit(makeRateLimitUpdate(primaryUsedPercent: 41, secondaryUsedPercent: 94))

        var didUpdate = false
        for _ in 0..<50 {
            let state = await client.currentState()
            if state.snapshot?.windows.first?.used == 41 {
                didUpdate = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(didUpdate)
    }

    func testCodexClientUpdatesIdentityIndependentlyFromRateLimits() async throws {
        let session = makeBootstrapCodexSession(
            email: "old@example.com",
            planType: "team",
            primaryUsedPercent: 32,
            secondaryUsedPercent: 94
        )
        let client = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory { session },
            sleep: { _ in },
            reconnectBackoff: [0]
        )

        await client.start()

        for _ in 0..<50 {
            let state = await client.currentState()
            if state.identity?.email == "old@example.com" {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        session.emit(.stdout("""
{"id":2,"result":{"account":{"type":"chatgpt","email":"new@example.com","planType":"team"},"requiresOpenaiAuth":true}}
"""))

        var identityUpdated = false
        for _ in 0..<50 {
            let state = await client.currentState()
            if state.identity?.email == "new@example.com",
               state.snapshot?.windows.first?.used == 32 {
                identityUpdated = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(identityUpdated)
    }

    func testCodexClientReconnectMarksSnapshotStaleUntilNewBootstrap() async throws {
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
            email: "live@example.com",
            planType: "team",
            primaryUsedPercent: 32,
            secondaryUsedPercent: 94
        )
        let secondSession = makeBootstrapCodexSession(
            email: "live@example.com",
            planType: "team",
            primaryUsedPercent: 41,
            secondaryUsedPercent: 94
        )

        let sequence = SessionSequence(sessions: [firstSession, secondSession])
        let factory = MockCodexAppServerSessionFactory {
            sequence.next()
        }

        let client = CodexAppServerClient(
            sessionFactory: factory,
            sleep: { interval in
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            },
            reconnectBackoff: [0.2]
        )

        await client.start()

        for _ in 0..<50 {
            let state = await client.currentState()
            if state.snapshot?.windows.first?.used == 32 {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        firstSession.emit(.terminated(1))
        firstSession.finish()

        var sawStale = false
        for _ in 0..<50 {
            let state = await client.currentState()
            if state.status == .staleFallback, state.snapshot?.windows.first?.used == 32 {
                sawStale = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(sawStale)

        var sawReconnect = false
        for _ in 0..<50 {
            let state = await client.currentState()
            if state.status == .live, state.snapshot?.windows.first?.used == 41 {
                sawReconnect = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(sawReconnect)
    }
}
