import Foundation
import XCTest
@testable import UsageTool

private struct MockConsumerSnapshotReader: ConsumerUsageSnapshotReading {
    let windowsToReturn: [UsageWindow]?

    func windows(for serviceType: ServiceType) throws -> [UsageWindow]? {
        guard serviceType == .codex else { return nil }
        return windowsToReturn
    }
}

private struct MockCodexLiveSnapshotReader: CodexLiveSnapshotReading {
    let snapshot: CodexConsumerSnapshot?

    func readSnapshot() throws -> CodexConsumerSnapshot? {
        snapshot
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
            liveSnapshotReader: MockCodexLiveSnapshotReader(
                snapshot: CodexConsumerSnapshot(
                    windows: liveWindows,
                    identity: ConsumerAccountIdentity(email: "live@example.com", externalID: nil),
                    tier: "Team"
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
            liveSnapshotReader: MockCodexLiveSnapshotReader(
                snapshot: CodexConsumerSnapshot(
                    windows: [],
                    identity: ConsumerAccountIdentity(email: "live@example.com", externalID: nil),
                    tier: "Team"
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
}
