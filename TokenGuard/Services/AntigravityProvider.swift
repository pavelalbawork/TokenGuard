import CryptoKit
import Foundation
import SQLite3

// MARK: - Internal types

private struct AntigravityAuthState: Sendable {
    let accessToken: String
    let refreshToken: String?
    let email: String?
    let name: String?
}

private struct AntigravityRefreshedToken: Sendable {
    let accessToken: String
    let email: String?
}

private struct AntigravityAccount: Sendable {
    let email: String
    let isActive: Bool
    let pools: [QuotaPool]
}

private struct QuotaPool: Sendable {
    enum Category: Sendable {
        case anthropic
        case geminiFlash
        case geminiPro

        var displayName: String {
            switch self {
            case .anthropic: return "Anthropic (Claude)"
            case .geminiFlash: return "Gemini Flash"
            case .geminiPro: return "Gemini Pro"
            }
        }
    }

    let category: Category
    let remainingPercent: Int   // 0 = exhausted, 100 = full
    let resetTime: Date?
    let modelNames: [String]
}

// MARK: - Provider

struct AntigravityProvider: ServiceProvider, ConsumerAccountDetecting {
    let serviceType: ServiceType = .antigravity

    private static let oauthClientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private static let oauthClientSecret = "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"
    private static let userAgent = "antigravity/1.11.3 Darwin/arm64"

    private let stateDbURL: URL
    private let cloudCodeBaseURL: URL
    private let session: NetworkSession
    private let now: @Sendable () -> Date
    private let keychainManager: KeychainManager?

    init(
        stateDbURL: URL = URL(
            fileURLWithPath: (
                "~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb" as NSString
            ).expandingTildeInPath
        ),
        cloudCodeBaseURL: URL = URL(string: "https://cloudcode-pa.googleapis.com")!,
        session: NetworkSession = URLSession.shared,
        now: @escaping @Sendable () -> Date = Date.init,
        keychainManager: KeychainManager? = nil
    ) {
        self.stateDbURL = stateDbURL
        self.cloudCodeBaseURL = cloudCodeBaseURL
        self.session = session
        self.now = now
        self.keychainManager = keychainManager
    }

    func fetchUsage(account: Account, credential: String) async throws -> UsageSnapshot {
        let authState = try await resolvedAuthState(readAuthStateFromStateDb())
        let accounts: [AntigravityAccount] = try await readAccountsDirect(authState: authState)

        // Match this TokenGuard account's name (email) to the corresponding
        // Antigravity database account.  Fall back to the active/first account
        // when no email matches, preserving existing single-account behavior.
        let target: AntigravityAccount
        tgLog("[AG] fetchUsage: account='\(account.displayName)' name=\(account.name) consumerEmail=\(account.consumerEmail ?? "nil"), API returned \(accounts.count) accounts: \(accounts.map { "\($0.email)(active=\($0.isActive))" }.joined(separator: ", "))")
        if let byName = accounts.first(where: {
            let normalizedAccountName = normalizedIdentity(account.name)
            let normalizedConfiguredEmail = normalizedIdentity(account.consumerEmail)
            let normalizedCandidateEmail = normalizedIdentity($0.email)
            return normalizedCandidateEmail == normalizedAccountName || normalizedCandidateEmail == normalizedConfiguredEmail
        }) {
            target = byName
            tgLog("[AG] fetchUsage: matched by name/email → \(byName.email)")

            // Save the refresh token so this account can fetch independently
            // after an account switch makes the stateDB credentials stale.
            if let refreshToken = authState.refreshToken, !account.credentialRef.isEmpty {
                try? keychainManager?.saveSecret(refreshToken, reference: account.credentialRef)
            }
        } else {
            // StaleDB credentials belong to a different account. Try this
            // account's own saved refresh token from the Keychain.
            let savedRefreshToken = credential.isEmpty ? nil : credential
            if let refreshToken = savedRefreshToken {
                tgLog("[AG] fetchUsage: stateDB stale, trying saved refresh token for '\(account.displayName)'")
                return try await fetchUsageWithRefreshToken(refreshToken, account: account)
            }
            tgLog("[AG] fetchUsage: no email match and no saved credentials, skipping")
            throw ServiceProviderError.credentialsStale
        }

        let timestamp = now()
        var windows: [UsageWindow] = []
        var breakdown: [UsageBreakdown] = []

        for pool in target.pools {
            let usedPercent = Double(100 - pool.remainingPercent)
            windows.append(UsageWindow(
                windowType: .daily,
                used: usedPercent,
                limit: 100,
                unit: .percent,
                resetDate: pool.resetTime,
                label: pool.category.displayName
            ))
            for model in pool.modelNames {
                breakdown.append(UsageBreakdown(
                    label: model,
                    used: usedPercent,
                    limit: 100,
                    unit: .percent
                ))
            }
        }

        return UsageSnapshot(
            accountId: account.id,
            timestamp: timestamp,
            windows: windows,
            tier: target.email.isEmpty ? authState.name ?? "Antigravity" : target.email,
            breakdown: breakdown.isEmpty ? nil : breakdown,
            isStale: false
        )
    }

    /// Fetches usage using a saved per-account refresh token instead of the
    /// stateDB credentials (which may belong to a different account after a switch).
    private func fetchUsageWithRefreshToken(_ refreshToken: String, account: Account) async throws -> UsageSnapshot {
        let refreshed = try await refreshAccessToken(refreshToken: refreshToken)
        let authState = AntigravityAuthState(
            accessToken: refreshed.accessToken,
            refreshToken: refreshToken,
            email: refreshed.email,
            name: nil
        )
        let accounts = try await readAccountsDirect(authState: authState)

        guard let target = accounts.first else {
            throw ServiceProviderError.unavailable("No Antigravity accounts found.")
        }

        tgLog("[AG] fetchUsage: saved-token fetch OK for '\(account.displayName)' → \(target.email)")

        let timestamp = now()
        var windows: [UsageWindow] = []
        var breakdown: [UsageBreakdown] = []

        for pool in target.pools {
            let usedPercent = Double(100 - pool.remainingPercent)
            windows.append(UsageWindow(
                windowType: .daily,
                used: usedPercent,
                limit: 100,
                unit: .percent,
                resetDate: pool.resetTime,
                label: pool.category.displayName
            ))
            for model in pool.modelNames {
                breakdown.append(UsageBreakdown(
                    label: model,
                    used: usedPercent,
                    limit: 100,
                    unit: .percent
                ))
            }
        }

        return UsageSnapshot(
            accountId: account.id,
            timestamp: timestamp,
            windows: windows,
            tier: target.email.isEmpty ? "Antigravity" : target.email,
            breakdown: breakdown.isEmpty ? nil : breakdown,
            isStale: false
        )
    }

    func validateCredentials(account _: Account, credential _: String) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: stateDbURL.path) else {
            throw ServiceProviderError.unavailable(
                "Antigravity editor not found. Install the Antigravity editor and sign in."
            )
        }

        let accounts = try await readAccountsDirect(authState: readAuthStateFromStateDb())
        return !accounts.isEmpty
    }

    func currentConsumerIdentity() async throws -> ConsumerAccountIdentity? {
        guard let authState = try? readAuthStateFromStateDb() else {
            tgLog("[AG] identity: could not read auth state from stateDB")
            return nil
        }

        let db = try? openStateDatabase()
        defer { if let db { sqlite3_close(db) } }

        let profileUrl = db.flatMap { normalizedIdentity(readProfileUrl(db: $0)) }

        // Detect account switch: `antigravity.profileUrl` (live, updates on
        // switch) vs the profileUrl embedded in the protobuf `userStatus`
        // (stale, never updates on switch).  When they differ, the OAuth token
        // and email in stateDB belong to the OLD account and must be ignored.
        let staleProfileUrl = db.flatMap { readProfileUrlFromUserStatus(db: $0) }
        let accountSwitched = profileUrl != nil && staleProfileUrl != nil && profileUrl != staleProfileUrl

        tgLog("[AG] identity: profileUrl=\(profileUrl ?? "nil") staleProfileUrl=\(staleProfileUrl ?? "nil") switched=\(accountSwitched) hasRefreshToken=\(authState.refreshToken != nil)")

        if accountSwitched {
            // After an account switch, the oauthToken and userStatus in stateDB
            // still belong to the previous account.  Return a profileUrl-only
            // identity so the polling engine can match by stored profileUrl
            // rather than the stale email.
            tgLog("[AG] identity: switch detected — returning profileUrl-only identity")
            return ConsumerAccountIdentity(email: nil, externalID: nil, profileUrl: profileUrl)
        }

        // No switch detected — email sources are trustworthy.
        if let refreshToken = authState.refreshToken {
            do {
                let refreshed = try await refreshAccessToken(refreshToken: refreshToken)
                if let freshEmail = normalizedIdentity(refreshed.email) {
                    tgLog("[AG] identity: OAuth refresh succeeded, freshEmail=\(freshEmail)")
                    return ConsumerAccountIdentity(
                        email: freshEmail,
                        externalID: nil,
                        profileUrl: profileUrl
                    )
                } else {
                    tgLog("[AG] identity: OAuth refresh returned nil email")
                }
            } catch {
                tgLog("[AG] identity: OAuth refresh FAILED: \(error.localizedDescription)")
            }
        }

        if let email = normalizedIdentity(authState.email) {
            tgLog("[AG] identity: falling back to stale stateDB email=\(email)")
            return ConsumerAccountIdentity(
                email: email,
                externalID: nil,
                profileUrl: profileUrl
            )
        }

        guard profileUrl != nil else {
            tgLog("[AG] identity: no email and no profileUrl, returning nil")
            return nil
        }
        tgLog("[AG] identity: returning profileUrl-only identity")
        return ConsumerAccountIdentity(email: nil, externalID: nil, profileUrl: profileUrl)
    }

    /// Returns the currently-signed-in account's profile URL as recorded in
    /// `state.vscdb`. This is the freshest per-account identifier Antigravity
    /// exposes outside the Electron safe-storage keychain blob.
    private func readProfileUrl(db: OpaquePointer?) -> String? {
        guard let raw = readItemTableValue(db: db, key: "antigravity.profileUrl") else {
            return nil
        }
        return unquoteJSONString(raw)
    }

    /// VS Code's ItemTable stores some values as JSON-encoded strings
    /// (including the surrounding quotes). Strip them when present.
    private func unquoteJSONString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\""),
           let data = trimmed.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String {
            return decoded
        }
        return trimmed
    }

    /// Refreshes the access token when a refresh token is available so that
    /// downstream API calls see the currently-signed-in account rather than a
    /// stale cached token. The refreshed `id_token` also carries the live
    /// account email, which `currentConsumerIdentity()` relies on to pick the
    /// correct TokenGuard account to mark active.
    private func resolvedAuthState(_ authState: AntigravityAuthState) async throws -> AntigravityAuthState {
        guard let refreshToken = authState.refreshToken else {
            return authState
        }

        do {
            let refreshed = try await refreshAccessToken(refreshToken: refreshToken)
            return AntigravityAuthState(
                accessToken: refreshed.accessToken,
                refreshToken: refreshToken,
                email: refreshed.email ?? authState.email,
                name: authState.name
            )
        } catch ServiceProviderError.unauthorized {
            throw ServiceProviderError.unauthorized
        } catch {
            return authState
        }
    }

    // MARK: - Direct path (cloudcode-pa API)

    private func readAccountsDirect(authState: AntigravityAuthState) async throws -> [AntigravityAccount] {
        let models = try await fetchModelsFromAPI(authState: authState)
        let pools = groupPools(from: models)
        let email = normalizedIdentity(authState.email) ?? ""
        return [AntigravityAccount(email: email, isActive: true, pools: pools)]
    }

    private func readAuthStateFromStateDb() throws -> AntigravityAuthState {
        let db = try openStateDatabase()
        defer { sqlite3_close(db) }

        // Primary path: unified OAuth protobuf (present in all recent Antigravity versions).
        if let unifiedState = try? readUnifiedOAuthState(from: db),
           !unifiedState.accessToken.isEmpty {
            let email = readEmailFromUserStatus(db: db)
            let name = readNameFromUserStatus(db: db)
            return AntigravityAuthState(
                accessToken: unifiedState.accessToken,
                refreshToken: unifiedState.refreshToken,
                email: email,
                name: name
            )
        }

        return try readLegacyAuthState(from: db)
    }

    /// Reads the signed-in user's email from `antigravityUnifiedStateSync.userStatus` (protobuf).
    /// Recent Antigravity builds nest the user profile inside multiple protobuf and base64 layers.
    /// Walk those payloads recursively until an email-shaped token appears.
    private func readEmailFromUserStatus(db: OpaquePointer?) -> String? {
        let pattern = "[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}"
        for payload in decodedUserStatusPayloads(db: db) {
            let text = String(decoding: payload, as: UTF8.self)
            if let range = text.range(of: pattern, options: .regularExpression) {
                return normalizedIdentity(String(text[range]))
            }
        }
        return nil
    }

    /// Reads the profile URL embedded inside `antigravityUnifiedStateSync.userStatus` (protobuf).
    /// This URL is stale — it does NOT update on account switches. Comparing it
    /// against the live `antigravity.profileUrl` ItemTable key detects switches.
    private func readProfileUrlFromUserStatus(db: OpaquePointer?) -> String? {
        let pattern = "https://lh3\\.googleusercontent\\.com/[^\\s\"<>]+"
        for payload in decodedUserStatusPayloads(db: db) {
            let text = String(decoding: payload, as: UTF8.self)
            if let range = text.range(of: pattern, options: .regularExpression) {
                return normalizedIdentity(String(text[range]))
            }
        }
        return nil
    }

    /// Reads the signed-in user's display name from `antigravityUnifiedStateSync.userStatus`.
    private func readNameFromUserStatus(db: OpaquePointer?) -> String? {
        let payloads = decodedUserStatusPayloads(db: db)
        for payload in payloads {
            if let nameData = protobufField(1, in: payload),
               let name = String(data: nameData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }
        }

        guard let email = readEmailFromUserStatus(db: db) else {
            return nil
        }

        for payload in payloads {
            let text = String(decoding: payload, as: UTF8.self)
            guard let emailRange = text.range(of: email, options: [.caseInsensitive]) else {
                continue
            }

            let prefix = text[..<emailRange.lowerBound]
            let candidates = prefix
                .components(separatedBy: CharacterSet.controlCharacters.union(.newlines))
                .map {
                    $0.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
                }
                .filter { !$0.isEmpty }

            if let candidate = candidates.last, candidate.contains(" ") {
                return candidate
            }
        }

        return nil
    }

    /// Generic helper to fetch a single text value from ItemTable by key.
    private func readItemTableValue(db: OpaquePointer?, key: String) -> String? {
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = '\(key)'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: ptr)
    }

    private func openStateDatabase() throws -> OpaquePointer? {
        var errors: [String] = []

        // Prefer a normal read-only open so committed WAL changes are visible
        // immediately after Antigravity switches accounts. Immutable mode can read
        // stale main-db pages when recent auth state is still in the WAL file.
        for attempt in [
            (label: "read-only", query: "mode=ro", flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI),
            (label: "read-write", query: "mode=rw", flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_URI),
            (label: "immutable", query: "immutable=1", flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI)
        ] {
            var db: OpaquePointer?
            let result = sqlite3_open_v2(
                stateDbURI(query: attempt.query),
                &db,
                attempt.flags,
                nil
            )

            if result == SQLITE_OK {
                sqlite3_busy_timeout(db, 1_000)
                do {
                    try validateReadableStateDatabase(db)
                    return db
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    errors.append("\(attempt.label): \(message)")
                    sqlite3_close(db)
                    continue
                }
            }

            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            errors.append("\(attempt.label): \(message)")
            sqlite3_close(db)
        }

        throw ServiceProviderError.unavailable(
            "Could not open Antigravity editor database at \(stateDbURL.path). \(errors.joined(separator: "; "))"
        )
    }

    private func validateReadableStateDatabase(_ db: OpaquePointer?) throws {
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable LIMIT 1"
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }

        guard result == SQLITE_OK else {
            throw ServiceProviderError.unavailable(
                "Could not query Antigravity editor database. Error: \(String(cString: sqlite3_errmsg(db)))"
            )
        }
    }

    private func stateDbURI(query: String) -> String {
        var components = URLComponents(url: stateDbURL.standardizedFileURL, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = query
        return components?.string ?? stateDbURL.standardizedFileURL.absoluteString
    }

    private func normalizedIdentity(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fetchModelsFromAPI(authState: AntigravityAuthState) async throws -> [String: [String: Any]] {
        do {
            return try await fetchModelsFromAPI(accessToken: authState.accessToken)
        } catch ServiceProviderError.unauthorized {
            guard let refreshToken = authState.refreshToken else {
                throw ServiceProviderError.unauthorized
            }
            let refreshed = try await refreshAccessToken(refreshToken: refreshToken)
            return try await fetchModelsFromAPI(accessToken: refreshed.accessToken)
        }
    }

    private func fetchModelsFromAPI(accessToken: String) async throws -> [String: [String: Any]] {
        let project = try await fetchProject(accessToken: accessToken)
        let url = cloudCodeBaseURL.appending(path: "/v1internal:fetchAvailableModels")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = project.map { ["project": $0] } ?? [:]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Antigravity fetchAvailableModels")

        // The API returns either an "availableModels" array or a "models" object.
        if let modelsObject = root["models"] as? [String: [String: Any]] {
            return parseModelsObject(modelsObject)
        }

        if let modelsArray = root["availableModels"] as? [[String: Any]] {
            return parseModelsArray(modelsArray)
        }

        throw ServiceProviderError.invalidPayload(
            "Unexpected response format from Antigravity API."
        )
    }

    private func fetchProject(accessToken: String) async throws -> String? {
        let url = cloudCodeBaseURL.appending(path: "/v1internal:loadCodeAssist")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["metadata": ["ideType": "ANTIGRAVITY"]]
        )

        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Antigravity loadCodeAssist")
        return ProviderSupport.string(root["cloudaicompanionProject"])
    }

    private func refreshAccessToken(refreshToken: String) async throws -> AntigravityRefreshedToken {
        let requestBody = [
            "client_id": Self.oauthClientID,
            "client_secret": Self.oauthClientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        var components = URLComponents(string: "https://oauth2.googleapis.com/token")
        components?.queryItems = requestBody.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let body = components?.percentEncodedQuery?.data(using: .utf8),
              let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw ServiceProviderError.invalidPayload("Could not build Antigravity OAuth refresh request.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Antigravity OAuth refresh")
        guard let accessToken = ProviderSupport.string(root["access_token"]), !accessToken.isEmpty else {
            throw ServiceProviderError.invalidPayload("Antigravity OAuth refresh did not return an access token.")
        }
        let email = ProviderSupport.string(root["email"])
            ?? ProviderSupport.string(root["user_email"])
            ?? parseEmailFromIDToken(ProviderSupport.string(root["id_token"]))
        return AntigravityRefreshedToken(
            accessToken: accessToken,
            email: normalizedIdentity(email)
        )
    }

    private func parseEmailFromIDToken(_ idToken: String?) -> String? {
        guard let idToken else { return nil }
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: payload),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return ProviderSupport.string(root["email"])
    }

    private func readUnifiedOAuthState(from db: OpaquePointer?) throws -> (accessToken: String, refreshToken: String?)? {
        for payload in decodedPayloads(forKey: "antigravityUnifiedStateSync.oauthToken", db: db) {
            if let accessToken = oauthAccessToken(in: payload) {
                return (
                    accessToken,
                    oauthRefreshToken(in: payload)
                )
            }
        }
        return nil
    }

    private func readLegacyAuthState(from db: OpaquePointer?) throws -> AntigravityAuthState {
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = 'antigravityAuthStatus'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ServiceProviderError.unavailable(
                "Could not query Antigravity editor database. Error: \(String(cString: sqlite3_errmsg(db)))"
            )
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW, let valuePtr = sqlite3_column_text(stmt, 0) else {
            throw ServiceProviderError.unavailable(
                "Antigravity editor has no auth status. Open Antigravity and sign in."
            )
        }

        let json = String(cString: valuePtr)
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ServiceProviderError.unavailable(
                "Could not read access token from Antigravity editor. Try signing in to Antigravity again."
            )
        }

        let apiKey = ProviderSupport.string(root["apiKey"])
            ?? ProviderSupport.string(root["accessToken"])
            ?? ProviderSupport.string(root["token"])

        guard let apiKey, !apiKey.isEmpty else {
            throw ServiceProviderError.unavailable(
                "Could not read access token from Antigravity editor. Try signing in to Antigravity again."
            )
        }

        return AntigravityAuthState(
            accessToken: apiKey,
            refreshToken: nil,
            email: ProviderSupport.string(root["email"]),
            name: ProviderSupport.string(root["name"])
        )
    }

    private func oauthAccessToken(in payload: Data) -> String? {
        if let tokenData = protobufField(1, in: payload),
           let token = String(data: tokenData, encoding: .utf8),
           token.hasPrefix("ya29.") {
            return token
        }

        let text = String(decoding: payload, as: UTF8.self)
        if let match = text.firstMatch(of: /ya29\.[A-Za-z0-9._-]+/) {
            return String(match.output)
        }

        return nil
    }

    private func oauthRefreshToken(in payload: Data) -> String? {
        if let tokenData = protobufField(3, in: payload),
           let token = String(data: tokenData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }

        let text = String(decoding: payload, as: UTF8.self)
        if let match = text.firstMatch(of: /1\/\/[A-Za-z0-9._-]+/) {
            return String(match.output)
        }

        return nil
    }

    private func protobufField(_ fieldNumber: Int, in data: Data) -> Data? {
        var offset = 0
        while offset < data.count {
            guard let (tag, nextOffset) = readVarint(in: data, offset: offset) else { return nil }
            let wireType = Int(tag & 0b111)
            let currentField = Int(tag >> 3)
            offset = nextOffset

            switch wireType {
            case 0:
                guard let (_, varintEnd) = readVarint(in: data, offset: offset) else { return nil }
                offset = varintEnd
            case 2:
                guard let (length, payloadStart) = readVarint(in: data, offset: offset) else { return nil }
                let payloadEnd = payloadStart + Int(length)
                guard payloadEnd <= data.count else { return nil }
                if currentField == fieldNumber {
                    return data.subdata(in: payloadStart..<payloadEnd)
                }
                offset = payloadEnd
            case 1:
                offset += 8
            case 5:
                offset += 4
            default:
                return nil
            }
        }
        return nil
    }

    private func decodedUserStatusPayloads(db: OpaquePointer?) -> [Data] {
        decodedPayloads(forKey: "antigravityUnifiedStateSync.userStatus", db: db)
    }

    private func decodedPayloads(forKey key: String, db: OpaquePointer?) -> [Data] {
        guard let raw = readItemTableValue(db: db, key: key),
              let outer = Data(base64Encoded: raw) else {
            return []
        }

        var queue: [Data] = [outer]
        var payloads: [Data] = []
        var seen = Set<Data>()

        while !queue.isEmpty {
            let current = queue.removeFirst()
            if seen.contains(current) {
                continue
            }
            seen.insert(current)
            payloads.append(current)

            queue.append(contentsOf: protobufLengthDelimitedFields(in: current))

            let text = String(decoding: current, as: UTF8.self)
            for match in text.matches(of: /[A-Za-z0-9+\/=]{40,}/) {
                guard let decoded = Data(base64Encoded: String(match.output)),
                      !decoded.isEmpty,
                      !seen.contains(decoded) else {
                    continue
                }
                queue.append(decoded)
            }
        }

        return payloads
    }

    private func protobufLengthDelimitedFields(in data: Data) -> [Data] {
        var payloads: [Data] = []
        var offset = 0

        while offset < data.count {
            guard let (tag, nextOffset) = readVarint(in: data, offset: offset) else {
                return payloads
            }
            let wireType = Int(tag & 0b111)
            offset = nextOffset

            switch wireType {
            case 0:
                guard let (_, varintEnd) = readVarint(in: data, offset: offset) else {
                    return payloads
                }
                offset = varintEnd
            case 2:
                guard let (length, payloadStart) = readVarint(in: data, offset: offset) else {
                    return payloads
                }
                let payloadEnd = payloadStart + Int(length)
                guard payloadEnd <= data.count else {
                    return payloads
                }
                payloads.append(data.subdata(in: payloadStart..<payloadEnd))
                offset = payloadEnd
            case 1:
                offset += 8
            case 5:
                offset += 4
            default:
                return payloads
            }
        }

        return payloads
    }

    private func readVarint(in data: Data, offset: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var cursor = offset

        while cursor < data.count {
            let byte = data[cursor]
            value |= UInt64(byte & 0x7F) << shift
            cursor += 1
            if byte & 0x80 == 0 {
                return (value, cursor)
            }
            shift += 7
        }

        return nil
    }

    private func parseModelsArray(_ array: [[String: Any]]) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for model in array {
            guard let name = ProviderSupport.string(model["modelName"] ?? model["name"]) else {
                continue
            }
            result[name] = normalizedModelInfo(from: model)
        }
        return result
    }

    private func parseModelsObject(_ models: [String: [String: Any]]) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for (name, info) in models {
            result[name] = normalizedModelInfo(from: info)
        }
        return result
    }

    private func normalizedModelInfo(from raw: [String: Any]) -> [String: Any] {
        var info: [String: Any] = [:]

        // Map API fields to the internal format used by groupPools().
        if let quota = raw["quotaInfo"] as? [String: Any] {
            if let fraction = ProviderSupport.double(quota["remainingFraction"]) {
                info["percentage"] = Int(fraction * 100)
            }
            if let resetTime = ProviderSupport.string(quota["resetTime"] ?? quota["reset_time"]) {
                info["resetTime"] = resetTime
                // Antigravity sometimes omits remainingFraction when a quota bucket is
                // exhausted but still reports the next reset time.
                if info["percentage"] == nil {
                    info["percentage"] = 0
                }
            }
        } else {
            if let fraction = ProviderSupport.double(raw["remainingFraction"] ?? raw["remaining_fraction"]) {
                info["percentage"] = Int(fraction * 100)
            } else if let percentage = ProviderSupport.int(raw["percentage"]) {
                info["percentage"] = percentage
            }
            if let resetTime = ProviderSupport.string(raw["resetTime"] ?? raw["reset_time"]) {
                info["resetTime"] = resetTime
            }
        }

        if let displayName = ProviderSupport.string(raw["displayName"] ?? raw["display_name"]) {
            info["displayName"] = displayName
        }

        return info
    }

    // MARK: - Pool grouping

    private func groupPools(from models: [String: [String: Any]]) -> [QuotaPool] {
        var byCategory: [QuotaPool.Category: [(name: String, remaining: Int, resetTime: Date?)]] = [:]
        let isoFormatter = ISO8601DateFormatter()

        for (name, info) in models {
            let remaining = (info["percentage"] as? Int) ?? 100
            let resetTime = (info["resetTime"] as? String).flatMap { isoFormatter.date(from: $0) }
            let lower = name.lowercased()

            let category: QuotaPool.Category
            if lower.contains("claude") {
                category = .anthropic
            } else if lower.contains("flash") {
                category = .geminiFlash
            } else if lower.contains("pro") {
                category = .geminiPro
            } else {
                continue
            }

            byCategory[category, default: []].append((name, remaining, resetTime))
        }

        return [QuotaPool.Category.anthropic, .geminiPro, .geminiFlash].compactMap { category in
            guard let entries = byCategory[category], !entries.isEmpty else { return nil }
            // Use the most-depleted model as the representative for this pool.
            let constraining = entries.min(by: { $0.remaining < $1.remaining })!
            return QuotaPool(
                category: category,
                remainingPercent: constraining.remaining,
                resetTime: constraining.resetTime,
                modelNames: entries.map(\.name).sorted()
            )
        }
    }
}
