import Foundation
import XCTest
@testable import TokenGuard

private func geminiHttpOK(data: Data, for url: URL) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (response, data)
}

private func geminiJsonData(_ body: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: body)
}

final class GeminiCLIProviderTests: XCTestCase {
    func testFetchUsageParsesIdentityAndQuotaBuckets() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let accountsURL = tempDirectory.appendingPathComponent("google_accounts.json")
        let oauthURL = tempDirectory.appendingPathComponent("oauth_creds.json")

        try """
        {
          "active": "work@example.com",
          "old": ["personal@example.com"]
        }
        """.write(to: accountsURL, atomically: true, encoding: .utf8)

        try """
        {
          "access_token": "initial-access-token",
          "refresh_token": "refresh-token",
          "expiry_date": 4102444800000,
          "token_type": "Bearer",
          "scope": "scope"
        }
        """.write(to: oauthURL, atomically: true, encoding: .utf8)

        let session = makeMockedSession()
        let cloudCodeBaseURL = URL(string: "https://cloudcode-pa.googleapis.com")!
        let tokenBaseURL = URL(string: "https://oauth2.googleapis.com/token")!

        URLProtocolMock.requestHandler = { request in
            guard let url = request.url else {
                throw ServiceProviderError.invalidResponse
            }

            if url == cloudCodeBaseURL.appending(path: "/v1internal:loadCodeAssist") {
                return geminiHttpOK(data: geminiJsonData([
                    "cloudaicompanionProject": "imagined-sandbox-w80f5",
                    "currentTier": ["name": "Gemini Code Assist"],
                    "paidTier": ["name": "Gemini Code Assist in Google One AI Pro"]
                ]), for: url)
            }

            if url == cloudCodeBaseURL.appending(path: "/v1internal:retrieveUserQuota") {
                return geminiHttpOK(data: geminiJsonData([
                    "buckets": [
                        [
                            "modelId": "gemini-2.5-pro",
                            "tokenType": "REQUESTS",
                            "remainingAmount": "8",
                            "remainingFraction": 0.8,
                            "resetTime": "2026-04-10T21:08:21Z"
                        ],
                        [
                            "modelId": "gemini-2.5-flash",
                            "tokenType": "REQUESTS",
                            "remainingFraction": 0.5,
                            "resetTime": "2026-04-10T21:08:21Z"
                        ]
                    ]
                ]), for: url)
            }

            if url == tokenBaseURL {
                return geminiHttpOK(data: geminiJsonData([
                    "access_token": "refreshed-access-token",
                    "expires_in": 3600,
                    "token_type": "Bearer"
                ]), for: url)
            }

            throw ServiceProviderError.invalidResponse
        }

        let provider = GeminiCLIProvider(
            googleAccountsURL: accountsURL,
            oauthCredentialsURL: oauthURL,
            session: session,
            tokenBaseURL: tokenBaseURL,
            cloudCodeBaseURL: cloudCodeBaseURL,
            now: { Date(timeIntervalSince1970: 1_775_000_000) }
        )

        let identity = try await provider.currentConsumerIdentity()
        XCTAssertEqual(identity?.email, "work@example.com")

        let account = Account(
            name: "work@example.com",
            serviceType: .gemini,
            credentialRef: "gemini-work",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "work@example.com"
            ]
        )

        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        XCTAssertEqual(snapshot.tier, "Gemini Code Assist in Google One AI Pro")
        XCTAssertEqual(snapshot.windows.count, 2)

        let proWindow = try XCTUnwrap(snapshot.windows.first { $0.label == "PRO" })
        XCTAssertEqual(proWindow.used, 2, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(proWindow.limit), 10, accuracy: 0.1)
        XCTAssertEqual(proWindow.unit, .requests)

        let flashWindow = try XCTUnwrap(snapshot.windows.first { $0.label == "FLASH" })
        XCTAssertEqual(flashWindow.used, 50, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(flashWindow.limit), 100, accuracy: 0.1)
        XCTAssertEqual(flashWindow.unit, .percent)
    }
}
