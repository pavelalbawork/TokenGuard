import Foundation
import SQLite3
import XCTest
@testable import UsageTool

private func antigravityHttpOK(data: Data, for url: URL) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    return (response, data)
}

private func antigravityJsonData(_ body: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: body)
}

final class AntigravityProviderTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a minimal state.vscdb with an antigravityAuthStatus entry.
    private func makeStateDb(in directory: URL, apiKey: String) throws -> URL {
        let dbURL = directory.appendingPathComponent("state.vscdb")
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            XCTFail("Could not create temp SQLite database")
            throw NSError(domain: "test", code: 0)
        }
        defer { sqlite3_close(db) }

        let createSQL = "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)"
        sqlite3_exec(db, createSQL, nil, nil, nil)

        let json = #"{"name":"Test","email":"test@example.com","apiKey":"\#(apiKey)"}"#
        let insertSQL = "INSERT INTO ItemTable (key, value) VALUES ('antigravityAuthStatus', '\(json)')"
        sqlite3_exec(db, insertSQL, nil, nil, nil)

        return dbURL
    }

    /// Builds a URL that points to nothing (no file).
    private func nonExistentURL() -> URL {
        URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/does_not_exist")
    }


    // MARK: - Direct path: pool grouping from availableModels array

    func testDirectPathParsesAvailableModelsArray() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeStateDb(in: tempDir, apiKey: "ya29.testtoken")

        let apiURL = URL(string: "https://cloudcode-pa.googleapis.com")!
        let response: [String: Any] = [
            "availableModels": [
                [
                    "modelName": "claude-sonnet-4-6",
                    "quotaInfo": [
                        "remainingFraction": 0.6,
                        "resetTime": "2026-04-07T00:00:00Z"
                    ]
                ],
                [
                    "modelName": "claude-opus-4-6",
                    "quotaInfo": [
                        "remainingFraction": 0.4,
                        "resetTime": "2026-04-07T00:00:00Z"
                    ]
                ],
                [
                    "modelName": "gemini-3-flash",
                    "quotaInfo": [
                        "remainingFraction": 0.9,
                        "resetTime": "2026-04-07T00:00:00Z"
                    ]
                ],
                [
                    "modelName": "gemini-3.1-pro",
                    "quotaInfo": [
                        "remainingFraction": 0.2,
                        "resetTime": "2026-04-07T00:00:00Z"
                    ]
                ]
            ]
        ]

        let session = makeMockedSession()
        let responseData = antigravityJsonData(response)
        URLProtocolMock.requestHandler = { [apiURL, responseData] _ in antigravityHttpOK(data: responseData, for: apiURL) }

        let provider = AntigravityProvider(
            stateDbURL: stateDbURL,
            cloudCodeBaseURL: apiURL,
            session: session
        )

        let account = Account(name: "Test", serviceType: .antigravity, credentialRef: "ref", configuration: [:])
        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        // Three pools: Anthropic (claude-sonnet + claude-opus), Flash, Pro
        XCTAssertEqual(snapshot.windows.count, 3)

        // Anthropic pool: constrained by the lower of the two Claude models (40% remaining = 60% used)
        let anthropicWindow = snapshot.windows.first { $0.label == "Anthropic (Claude)" }
        XCTAssertNotNil(anthropicWindow)
        XCTAssertEqual(anthropicWindow?.used ?? -1, 60, accuracy: 1)

        // Flash pool: 10% used (90% remaining)
        let flashWindow = snapshot.windows.first { $0.label == "Gemini Flash" }
        XCTAssertNotNil(flashWindow)
        XCTAssertEqual(flashWindow?.used ?? -1, 10, accuracy: 1)

        // Pro pool: 80% used (20% remaining)
        let proWindow = snapshot.windows.first { $0.label == "Gemini Pro" }
        XCTAssertNotNil(proWindow)
        XCTAssertEqual(proWindow?.used ?? -1, 80, accuracy: 1)
    }

    // MARK: - Direct path: models object format

    func testDirectPathParsesModelsObjectFormat() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeStateDb(in: tempDir, apiKey: "ya29.testtoken")
        let apiURL = URL(string: "https://cloudcode-pa.googleapis.com")!

        let response: [String: Any] = [
            "models": [
                "claude-sonnet-4-6": [
                    "displayName": "Claude Sonnet 4.6",
                    "quotaInfo": [
                        "remainingFraction": 0.75,
                        "resetTime": "2026-04-07T00:00:00Z"
                    ]
                ],
                "gemini-3-flash": [
                    "displayName": "Gemini 3 Flash",
                    "quotaInfo": [
                        "remainingFraction": 0.5,
                        "resetTime": "2026-04-07T00:00:00Z"
                    ]
                ]
            ]
        ]

        let session = makeMockedSession()
        let responseData = antigravityJsonData(response)
        URLProtocolMock.requestHandler = { [apiURL, responseData] _ in antigravityHttpOK(data: responseData, for: apiURL) }

        let provider = AntigravityProvider(
            stateDbURL: stateDbURL,
            cloudCodeBaseURL: apiURL,
            session: session
        )

        let account = Account(name: "Test", serviceType: .antigravity, credentialRef: "ref", configuration: [:])
        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        XCTAssertEqual(snapshot.windows.count, 2)

        let anthropicWindow = snapshot.windows.first { $0.label == "Anthropic (Claude)" }
        XCTAssertNotNil(anthropicWindow)
        // 75% remaining → 25% used
        XCTAssertEqual(anthropicWindow?.used ?? -1, 25, accuracy: 1)

        let flashWindow = snapshot.windows.first { $0.label == "Gemini Flash" }
        XCTAssertNotNil(flashWindow)
        // 50% remaining → 50% used
        XCTAssertEqual(flashWindow?.used ?? -1, 50, accuracy: 1)
    }

    func testDirectPathParsesLegacyModelsObjectPercentageFormat() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeStateDb(in: tempDir, apiKey: "ya29.testtoken")
        let apiURL = URL(string: "https://cloudcode-pa.googleapis.com")!

        let response: [String: Any] = [
            "models": [
                "claude-sonnet-4-6": ["percentage": 75, "resetTime": "2026-04-07T00:00:00Z"],
                "gemini-3-flash": ["percentage": 50, "resetTime": "2026-04-07T00:00:00Z"]
            ]
        ]

        let session = makeMockedSession()
        let responseData = antigravityJsonData(response)
        URLProtocolMock.requestHandler = { [apiURL, responseData] _ in antigravityHttpOK(data: responseData, for: apiURL) }

        let provider = AntigravityProvider(
            stateDbURL: stateDbURL,
            cloudCodeBaseURL: apiURL,
            session: session
        )

        let account = Account(name: "Test", serviceType: .antigravity, credentialRef: "ref", configuration: [:])
        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        XCTAssertEqual(snapshot.windows.first { $0.label == "Anthropic (Claude)" }?.used ?? -1, 25, accuracy: 1)
        XCTAssertEqual(snapshot.windows.first { $0.label == "Gemini Flash" }?.used ?? -1, 50, accuracy: 1)
    }

    func testDirectPathTreatsMissingRemainingFractionWithResetTimeAsExhausted() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeStateDb(in: tempDir, apiKey: "ya29.testtoken")
        let apiURL = URL(string: "https://cloudcode-pa.googleapis.com")!

        let response: [String: Any] = [
            "models": [
                "gemini-3.1-pro-high": [
                    "displayName": "Gemini 3.1 Pro (High)",
                    "quotaInfo": [
                        "resetTime": "2026-04-07T00:00:00Z"
                    ]
                ],
                "gemini-3-flash": [
                    "displayName": "Gemini 3 Flash",
                    "quotaInfo": [
                        "remainingFraction": 1.0,
                        "resetTime": "2026-04-07T00:00:00Z"
                    ]
                ]
            ]
        ]

        let session = makeMockedSession()
        let responseData = antigravityJsonData(response)
        URLProtocolMock.requestHandler = { [apiURL, responseData] _ in antigravityHttpOK(data: responseData, for: apiURL) }

        let provider = AntigravityProvider(
            stateDbURL: stateDbURL,
            cloudCodeBaseURL: apiURL,
            session: session
        )

        let account = Account(name: "Test", serviceType: .antigravity, credentialRef: "ref", configuration: [:])
        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        XCTAssertEqual(snapshot.windows.first { $0.label == "Gemini Pro" }?.used ?? -1, 100, accuracy: 1)
        XCTAssertEqual(snapshot.windows.first { $0.label == "Gemini Flash" }?.used ?? -1, 0, accuracy: 1)
    }

    // MARK: - Direct path: 401 propagates as unauthorized

    func testDirectPathThrowsOnUnauthorized() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeStateDb(in: tempDir, apiKey: "expired-token")
        let apiURL = URL(string: "https://cloudcode-pa.googleapis.com")!

        let session = makeMockedSession()
        URLProtocolMock.requestHandler = { [apiURL] _ in
            let data = Data(#"{"error":{"code":401,"status":"UNAUTHENTICATED"}}"#.utf8)
            let response = HTTPURLResponse(url: apiURL, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let provider = AntigravityProvider(
            stateDbURL: stateDbURL,
            cloudCodeBaseURL: apiURL,
            session: session
        )

        let account = Account(name: "Test", serviceType: .antigravity, credentialRef: "ref", configuration: [:])
        do {
            _ = try await provider.fetchUsage(account: account, credential: "")
            XCTFail("Expected unauthorized error")
        } catch ServiceProviderError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected unauthorized, got \(error)")
        }
    }

    // MARK: - Direct path: missing state.vscdb surfaces clear error

    func testDirectPathThrowsWhenNoDatabaseExists() async throws {
        let provider = AntigravityProvider(
            stateDbURL: nonExistentURL()
        )

        let account = Account(name: "Test", serviceType: .antigravity, credentialRef: "ref", configuration: [:])
        do {
            _ = try await provider.fetchUsage(account: account, credential: "")
            XCTFail("Expected unavailable error")
        } catch ServiceProviderError.unavailable {
            // expected
        }
    }

    // MARK: - Breakdown contains individual model names

    func testBreakdownContainsModelNames() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeStateDb(in: tempDir, apiKey: "ya29.test")
        let apiURL = URL(string: "https://cloudcode-pa.googleapis.com")!

        let response: [String: Any] = [
            "availableModels": [
                ["modelName": "claude-sonnet-4-6", "quotaInfo": ["remainingFraction": 0.8]],
                ["modelName": "claude-opus-4-6", "quotaInfo": ["remainingFraction": 0.5]]
            ]
        ]

        let session = makeMockedSession()
        let responseData = antigravityJsonData(response)
        URLProtocolMock.requestHandler = { [apiURL, responseData] _ in antigravityHttpOK(data: responseData, for: apiURL) }

        let provider = AntigravityProvider(
            stateDbURL: stateDbURL,
            cloudCodeBaseURL: apiURL,
            session: session
        )

        let account = Account(name: "Test", serviceType: .antigravity, credentialRef: "ref", configuration: [:])
        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        let breakdownLabels = snapshot.breakdown?.map(\.label) ?? []
        XCTAssertTrue(breakdownLabels.contains("claude-sonnet-4-6"))
        XCTAssertTrue(breakdownLabels.contains("claude-opus-4-6"))
    }

    func testCurrentConsumerIdentityReadsEmailFromAuthStatus() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeStateDb(in: tempDir, apiKey: "ya29.testidentity")
        let provider = AntigravityProvider(stateDbURL: stateDbURL)

        let identity = try await provider.currentConsumerIdentity()

        XCTAssertEqual(identity?.email, "test@example.com")
        XCTAssertNil(identity?.externalID)
    }
}
