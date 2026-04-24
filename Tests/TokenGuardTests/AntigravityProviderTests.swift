import Foundation
import SQLite3
import XCTest
@testable import TokenGuard

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
    private func makeStateDb(
        in directory: URL,
        apiKey: String,
        email: String = "test@example.com",
        name: String = "Test"
    ) throws -> URL {
        let dbURL = directory.appendingPathComponent("state.vscdb")
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            XCTFail("Could not create temp SQLite database")
            throw NSError(domain: "test", code: 0)
        }
        defer { sqlite3_close(db) }

        let createSQL = "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)"
        sqlite3_exec(db, createSQL, nil, nil, nil)

        let json = #"{"name":"\#(name)","email":"\#(email)","apiKey":"\#(apiKey)"}"#
        let insertSQL = "INSERT INTO ItemTable (key, value) VALUES ('antigravityAuthStatus', '\(json)')"
        sqlite3_exec(db, insertSQL, nil, nil, nil)

        return dbURL
    }

    private func executeSQL(_ sql: String, on db: OpaquePointer?) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
            throw NSError(domain: "sqlite", code: Int(result), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func protobufVarint(_ value: UInt64) -> Data {
        var remaining = value
        var data = Data()

        while true {
            if remaining < 0x80 {
                data.append(UInt8(remaining))
                return data
            }

            data.append(UInt8((remaining & 0x7F) | 0x80))
            remaining >>= 7
        }
    }

    private func protobufField(number: Int, payload: Data) -> Data {
        var data = Data()
        let tag = UInt64((number << 3) | 2)
        data.append(protobufVarint(tag))
        data.append(protobufVarint(UInt64(payload.count)))
        data.append(payload)
        return data
    }

    private func base64URLEncodedJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeIDToken(email: String) throws -> String {
        let header = try base64URLEncodedJSON(["alg": "none", "typ": "JWT"])
        let payload = try base64URLEncodedJSON(["email": email])
        return "\(header).\(payload).signature"
    }

    private func makeUnifiedStateDb(
        in directory: URL,
        accessToken: String,
        refreshToken: String? = nil,
        email: String,
        name: String,
        profileURL: String? = nil
    ) throws -> URL {
        let dbURL = directory.appendingPathComponent("state.vscdb")
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            XCTFail("Could not create temp SQLite database")
            throw NSError(domain: "test", code: 0)
        }
        defer { sqlite3_close(db) }

        try executeSQL("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)", on: db)

        var oauthInfo = protobufField(number: 1, payload: Data(accessToken.utf8))
        oauthInfo.append(protobufField(number: 2, payload: Data("Bearer".utf8)))
        if let refreshToken {
            oauthInfo.append(protobufField(number: 3, payload: Data(refreshToken.utf8)))
        }
        let oauthTokenInfo = protobufField(
            number: 1,
            payload: Data("oauthTokenInfoSentinelKey".utf8)
        ) + protobufField(
            number: 2,
            payload: protobufField(number: 1, payload: Data(Data(oauthInfo).base64EncodedString().utf8))
        )
        let oauthToken = (
            protobufField(number: 1, payload: Data("authStateWithContextSentinelKey".utf8)) +
            protobufField(
                number: 2,
                payload: protobufField(number: 1, payload: Data(#"{"state":"signedIn"}"#.utf8))
            ) +
            protobufField(number: 1, payload: oauthTokenInfo)
        ).base64EncodedString()

        let nestedProfile = Data("\(name):\u{0014}\(email)".utf8).base64EncodedString()
        let userStatus = protobufField(number: 2, payload: Data(nestedProfile.utf8)).base64EncodedString()

        let insertOAuthSQL = "INSERT INTO ItemTable (key, value) VALUES ('antigravityUnifiedStateSync.oauthToken', '\(oauthToken)')"
        let insertUserStatusSQL = "INSERT INTO ItemTable (key, value) VALUES ('antigravityUnifiedStateSync.userStatus', '\(userStatus)')"
        try executeSQL(insertOAuthSQL, on: db)
        try executeSQL(insertUserStatusSQL, on: db)
        if let profileURL {
            let insertProfileSQL = "INSERT INTO ItemTable (key, value) VALUES ('antigravity.profileUrl', '\(profileURL)')"
            try executeSQL(insertProfileSQL, on: db)
        }

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

    func testCurrentConsumerIdentityReadsLatestWalAuthStatusAfterAccountSwitch() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeStateDb(
            in: tempDir,
            apiKey: "ya29.old",
            email: "old@example.com",
            name: "Old"
        )

        var db: OpaquePointer?
        guard sqlite3_open(stateDbURL.path, &db) == SQLITE_OK else {
            XCTFail("Could not reopen temp SQLite database")
            return
        }
        defer { sqlite3_close(db) }

        try executeSQL("PRAGMA journal_mode=WAL", on: db)
        try executeSQL("PRAGMA wal_autocheckpoint=0", on: db)
        try executeSQL("PRAGMA wal_checkpoint(FULL)", on: db)

        let switchedAuthStatus = #"{"name":"New","email":"new@example.com","apiKey":"ya29.new"}"#
        try executeSQL(
            "UPDATE ItemTable SET value = '\(switchedAuthStatus)' WHERE key = 'antigravityAuthStatus'",
            on: db
        )

        let provider = AntigravityProvider(stateDbURL: stateDbURL)
        let identity = try await provider.currentConsumerIdentity()

        XCTAssertEqual(identity?.email, "new@example.com")
        XCTAssertNil(identity?.externalID)
    }

    func testCurrentConsumerIdentityReadsEmailFromRefreshedIdToken() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeUnifiedStateDb(
            in: tempDir,
            accessToken: "ya29.unified",
            refreshToken: "refresh.unified",
            email: "stale@example.com",
            name: "Nested User"
        )
        let idToken = try makeIDToken(email: "nested@example.com")
        let session = makeMockedSession()
        URLProtocolMock.requestHandler = { [idToken] request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.host == "oauth2.googleapis.com" {
                let body = antigravityJsonData([
                    "access_token": "ya29.refreshed",
                    "id_token": idToken,
                    "token_type": "Bearer"
                ])
                return antigravityHttpOK(data: body, for: url)
            }
            throw URLError(.badServerResponse)
        }

        let provider = AntigravityProvider(stateDbURL: stateDbURL, session: session)

        let identity = try await provider.currentConsumerIdentity()

        XCTAssertEqual(identity?.email, "nested@example.com")
        XCTAssertNil(identity?.externalID)
    }

    func testCurrentConsumerIdentityFallsBackToUserStatusEmailWhenOAuthRefreshFails() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Antigravity Provider Tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeUnifiedStateDb(
            in: tempDir,
            accessToken: "ya29.spaces",
            refreshToken: "refresh.spaces",
            email: "spaces@example.com",
            name: "Space User"
        )
        let session = makeMockedSession()
        URLProtocolMock.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let provider = AntigravityProvider(stateDbURL: stateDbURL, session: session)

        let identity = try await provider.currentConsumerIdentity()

        XCTAssertEqual(identity?.email, "spaces@example.com")
        XCTAssertNil(identity?.externalID)
    }

    func testCurrentConsumerIdentityPrefersRefreshedIdTokenOverUserStatusEmail() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeUnifiedStateDb(
            in: tempDir,
            accessToken: "ya29.current",
            refreshToken: "refresh.fresh",
            email: "stale@example.com",
            name: "Stale User",
            profileURL: "\"https://lh3.googleusercontent.com/a/fresh-profile=s96-c\""
        )
        let idToken = try makeIDToken(email: "fresh@example.com")
        let session = makeMockedSession()
        URLProtocolMock.requestHandler = { [idToken] request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.host == "oauth2.googleapis.com" {
                let body = antigravityJsonData([
                    "access_token": "ya29.refreshed",
                    "id_token": idToken,
                    "token_type": "Bearer"
                ])
                return antigravityHttpOK(data: body, for: url)
            }
            throw URLError(.badServerResponse)
        }

        let provider = AntigravityProvider(stateDbURL: stateDbURL, session: session)

        let identity = try await provider.currentConsumerIdentity()

        XCTAssertEqual(identity?.email, "fresh@example.com")
        XCTAssertNil(identity?.externalID)
    }

    func testFetchUsageRefreshesAccessTokenBeforeCallingAPI() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeUnifiedStateDb(
            in: tempDir,
            accessToken: "ya29.stale",
            refreshToken: "refresh.current",
            email: "stale@example.com",
            name: "Nested User"
        )
        let apiURL = URL(string: "https://cloudcode-pa.googleapis.com")!
        let idToken = try makeIDToken(email: "fresh@example.com")

        let session = makeMockedSession()
        URLProtocolMock.requestHandler = { [idToken] request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.host == "oauth2.googleapis.com" {
                let body = antigravityJsonData([
                    "access_token": "ya29.refreshed",
                    "id_token": idToken,
                    "token_type": "Bearer"
                ])
                return antigravityHttpOK(data: body, for: url)
            }

            if url.host == apiURL.host, url.path == "/v1internal:loadCodeAssist" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ya29.refreshed")
                let body = antigravityJsonData([
                    "cloudaicompanionProject": "projects/test-project"
                ])
                return antigravityHttpOK(data: body, for: url)
            }

            if url.host == apiURL.host, url.path == "/v1internal:fetchAvailableModels" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ya29.refreshed")
                let body = antigravityJsonData([
                    "models": [
                        "gemini-3-flash": [
                            "quotaInfo": [
                                "remainingFraction": 0.8,
                                "resetTime": "2026-04-07T00:00:00Z"
                            ]
                        ]
                    ]
                ])
                return antigravityHttpOK(data: body, for: url)
            }

            throw URLError(.badServerResponse)
        }

        let provider = AntigravityProvider(
            stateDbURL: stateDbURL,
            cloudCodeBaseURL: apiURL,
            session: session
        )

        let account = Account(
            name: "fresh@example.com",
            serviceType: .antigravity,
            credentialRef: "ref",
            configuration: [
                Account.ConfigurationKey.planType: "consumer",
                Account.ConfigurationKey.consumerEmail: "fresh@example.com"
            ]
        )

        let snapshot = try await provider.fetchUsage(account: account, credential: "")

        XCTAssertEqual(snapshot.tier, "fresh@example.com")
        XCTAssertEqual(snapshot.windows.first?.used ?? -1, 20, accuracy: 1)
    }

    func testCurrentConsumerIdentityPopulatesProfileUrl() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stateDbURL = try makeUnifiedStateDb(
            in: tempDir,
            accessToken: "ya29.current",
            refreshToken: "refresh.current",
            email: "primary@example.com",
            name: "Primary User",
            profileURL: "\"https://lh3.googleusercontent.com/a/active-account=s96-c\""
        )
        let idToken = try makeIDToken(email: "primary@example.com")
        let session = makeMockedSession()
        URLProtocolMock.requestHandler = { [idToken] request in
            guard let url = request.url else { throw URLError(.badURL) }
            if url.host == "oauth2.googleapis.com" {
                let body = antigravityJsonData([
                    "access_token": "ya29.refreshed",
                    "id_token": idToken,
                    "token_type": "Bearer"
                ])
                return antigravityHttpOK(data: body, for: url)
            }
            throw URLError(.badServerResponse)
        }

        let provider = AntigravityProvider(stateDbURL: stateDbURL, session: session)
        let identity = try await provider.currentConsumerIdentity()

        XCTAssertEqual(identity?.profileUrl, "https://lh3.googleusercontent.com/a/active-account=s96-c")
        XCTAssertEqual(identity?.email, "primary@example.com")
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error but none thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
