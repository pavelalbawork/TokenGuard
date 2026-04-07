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

final class OpenAIProviderTests: XCTestCase {
    func testConsumerUsagePrefersCLIOverSnapshot() async throws {
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
        XCTAssertEqual(snapshot.windows.first?.used ?? -1, 12, accuracy: 0.1)
        XCTAssertEqual(snapshot.windows.first?.unit, .percent)
    }
}
