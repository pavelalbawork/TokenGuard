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

    func testConsumerIdentityFallsBackToLiveAppServerIdentityWhenAuthFileMissing() async throws {
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

    func testConsumerIdentityPrefersCurrentAuthFileOverStaleLiveAppServerIdentity() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let authURL = tempDirectory.appendingPathComponent("auth.json")
        try """
        {
          "tokens": {
            "account_id": "acct-local",
            "id_token": "\(Self.jwt(email: "local@example.com"))"
          }
        }
        """.write(to: authURL, atomically: true, encoding: .utf8)

        let provider = OpenAIProvider(
            codexLiveStateProvider: MockCodexLiveStateProvider(
                state: CodexLiveState(
                    snapshot: nil,
                    identity: ConsumerAccountIdentity(email: "stale-live@example.com", externalID: nil),
                    status: .live,
                    lastUpdateAt: nil,
                    lastErrorText: nil
                )
            ),
            snapshotReader: MockConsumerSnapshotReader(windowsToReturn: nil),
            cliParser: nil,
            identityReader: CodexAuthIdentityReader(authURL: authURL),
            now: { Date(timeIntervalSince1970: 1_775_000_000) }
        )

        let identity = try await provider.currentConsumerIdentity()

        XCTAssertEqual(identity?.email, "local@example.com")
        XCTAssertEqual(identity?.externalID, "acct-local")
    }

    func testConsumerUsageFallsBackToSessionSnapshotWhenAppServerErrors() async throws {
        let snapshotWindows = [
            UsageWindow(
                windowType: .rolling5h,
                used: 61,
                limit: 100,
                unit: .percent,
                resetDate: nil
            )
        ]

        let provider = OpenAIProvider(
            codexLiveStateProvider: MockCodexLiveStateProvider(
                state: CodexLiveState(
                    snapshot: nil,
                    identity: ConsumerAccountIdentity(email: "live@example.com", externalID: nil),
                    status: .error,
                    lastUpdateAt: nil,
                    lastErrorText: "codex app-server missing"
                )
            ),
            snapshotReader: MockConsumerSnapshotReader(windowsToReturn: snapshotWindows),
            cliParser: nil,
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
        XCTAssertEqual(snapshot.windows.first?.used ?? -1, 61, accuracy: 0.1)
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

    func testCodexClientRefreshesAccountOnBootstrap() async throws {
        let lock = NSLock()
        nonisolated(unsafe) var accountReadRefreshToken: Bool?

        let session = MockCodexAppServerSession { line, session in
            guard let data = line.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = payload["id"] as? Int else {
                return
            }

            if id == 1 {
                session.emit(.stdout(#"{"id":1,"result":{}}"#))
            }

            if id == 2 {
                let params = payload["params"] as? [String: Any]
                lock.lock()
                accountReadRefreshToken = params?["refreshToken"] as? Bool
                lock.unlock()
                session.emit(.stdout("""
{"id":2,"result":{"account":{"type":"chatgpt","email":"live@example.com","planType":"team"},"requiresOpenaiAuth":true}}
"""))
            }
        }

        let client = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory { session },
            sleep: { _ in },
            reconnectBackoff: [0]
        )

        await client.start()

        let didReadAccount = await waitUntil {
            lock.lock()
            defer { lock.unlock() }
            return accountReadRefreshToken != nil
        }

        XCTAssertTrue(didReadAccount)
        XCTAssertEqual(accountReadRefreshToken, true)
        await client.stop()
    }

    func testCodexClientReportsSessionLaunchFailureWithoutCrashing() async throws {
        let client = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory {
                throw ServiceProviderError.unavailable("codex app-server missing")
            },
            sleep: { interval in
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            },
            reconnectBackoff: [0, 60]
        )

        await client.start()

        var didReportError = false
        for _ in 0..<50 {
            let state = await client.currentState()
            if state.status == .error,
               state.lastErrorText == "codex app-server missing" {
                didReportError = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertTrue(didReportError)
        await client.stop()
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

    func testCodexClientRestartClearsIdentityUntilNewBootstrap() async throws {
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
            email: "old@example.com",
            planType: "team",
            primaryUsedPercent: 32,
            secondaryUsedPercent: 94
        )
        let secondSession = makeBootstrapCodexSession(
            email: "new@example.com",
            planType: "team",
            primaryUsedPercent: 41,
            secondaryUsedPercent: 94
        )
        let sequence = SessionSequence(sessions: [firstSession, secondSession])

        let client = CodexAppServerClient(
            sessionFactory: MockCodexAppServerSessionFactory { sequence.next() },
            sleep: { interval in
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            },
            reconnectBackoff: [0.2]
        )

        await client.start()

        for _ in 0..<50 {
            let state = await client.currentState()
            if state.identity?.email == "old@example.com",
               state.snapshot?.windows.first?.used == 32 {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        await client.restart()

        var sawClearedIdentity = false
        for _ in 0..<50 {
            let state = await client.currentState()
            if state.identity == nil,
               state.snapshot?.windows.first?.used == 32,
               state.status != .live {
                sawClearedIdentity = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(sawClearedIdentity)

        var sawReconnect = false
        for _ in 0..<50 {
            let state = await client.currentState()
            if state.identity?.email == "new@example.com",
               state.snapshot?.windows.first?.used == 41,
               state.status == .live {
                sawReconnect = true
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(sawReconnect)
    }

    private static func jwt(email: String) -> String {
        let header = #"{"alg":"none"}"#
        let payload = #"{"email":"\#(email)"}"#
        return [
            base64URL(header),
            base64URL(payload),
            "signature"
        ].joined(separator: ".")
    }

    private static func base64URL(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
