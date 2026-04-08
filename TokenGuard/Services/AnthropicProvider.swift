import Foundation
import Security
import LocalAuthentication

struct ClaudeOAuthCredential: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let subscriptionType: String?
    let rateLimitTier: String?
    let expiresAt: Date?
    let scope: String?

    var displayTier: String? {
        subscriptionType?.capitalized ?? rateLimitTier
    }

    func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date.addingTimeInterval(60)
    }
}

struct AnthropicProvider: ServiceProvider {
    let serviceType: ServiceType = .claude

    private static let claudeOAuthService = "Claude Code-credentials"
    private static let claudeOAuthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private let session: NetworkSession
    private let baseURL: URL
    private let snapshotReader: (any ConsumerUsageSnapshotReading)?
    private let authStatusReader: ClaudeAuthStatusReading
    private let credentialLoader: @Sendable () throws -> ClaudeOAuthCredential
    private let credentialPersister: @Sendable (ClaudeOAuthCredential) throws -> Void
    private let now: @Sendable () -> Date

    init(
        session: NetworkSession = URLSession.shared,
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        snapshotReader: (any ConsumerUsageSnapshotReading)? = nil,
        authStatusReader: ClaudeAuthStatusReading = ClaudeCLIAuthStatusReader(),
        credentialLoader: @escaping @Sendable () throws -> ClaudeOAuthCredential = Self.loadClaudeOAuthCredential,
        credentialPersister: @escaping @Sendable (ClaudeOAuthCredential) throws -> Void = Self.persistClaudeOAuthCredential,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.baseURL = baseURL
        self.snapshotReader = snapshotReader
        self.authStatusReader = authStatusReader
        self.credentialLoader = credentialLoader
        self.credentialPersister = credentialPersister
        self.now = now
    }

    func fetchUsage(account: Account, credential: String) async throws -> UsageSnapshot {
        let timestamp = now()
        let planType = account.planType ?? (account.configurationValue(for: Account.ConfigurationKey.anthropicOrganizationID) == nil ? "consumer" : "api")

        if planType == "consumer" {
            let consumerUsage = try await fetchClaudeConsumerUsage(account: account, timestamp: timestamp)
            return UsageSnapshot(
                accountId: account.id,
                timestamp: timestamp,
                windows: consumerUsage.windows,
                tier: consumerUsage.tier,
                breakdown: nil,
                isStale: false
            )
        }

        guard let organizationID = account.configurationValue(for: Account.ConfigurationKey.anthropicOrganizationID) else {
            throw ServiceProviderError.missingConfiguration("Anthropic API accounts require an organization ID.")
        }

        let resetDate = ProviderSupport.monthlyResetDate(
            resetDayOfMonth: account.configurationInt(for: Account.ConfigurationKey.resetDayOfMonth),
            resetHourUTC: account.configurationInt(for: Account.ConfigurationKey.resetHourUTC),
            from: timestamp
        )

        let startDate = Calendar(identifier: .gregorian).date(byAdding: .month, value: -1, to: timestamp) ?? timestamp
        var components = URLComponents(url: baseURL.appending(path: "/v1/organizations/\(organizationID)/usage_report/messages"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "starting_at", value: ISO8601DateFormatter().string(from: startDate)),
            URLQueryItem(name: "ending_at", value: ISO8601DateFormatter().string(from: timestamp)),
            URLQueryItem(name: "bucket_width", value: "1d")
        ]

        guard let url = components?.url else {
            throw ServiceProviderError.invalidPayload("Could not build Anthropic usage URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credential, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Anthropic response")
        let buckets = try ProviderSupport.array(root["data"], context: "Anthropic response data")

        var totalUsed = 0.0
        var tier: String?
        var perModel: [String: Double] = [:]

        for bucket in buckets {
            let results = (bucket["results"] as? [[String: Any]]) ?? []
            for result in results {
                let inputTokens =
                    ProviderSupport.double(result["input_tokens"]) ??
                    ProviderSupport.double(result["uncached_input_tokens"]) ??
                    0
                let outputTokens = ProviderSupport.double(result["output_tokens"]) ?? 0
                let cacheCreation = ProviderSupport.double(result["cache_creation_input_tokens"]) ?? 0
                let cacheRead = ProviderSupport.double(result["cache_read_input_tokens"]) ?? 0
                let total = inputTokens + outputTokens + cacheCreation + cacheRead

                totalUsed += total
                if let model = ProviderSupport.string(result["model"]) {
                    perModel[model, default: 0] += total
                }
                tier = tier ?? ProviderSupport.string(result["service_tier"])
            }
        }

        let limit = account.configurationDouble(for: Account.ConfigurationKey.monthlyLimit) ??
            account.configurationDouble(for: Account.ConfigurationKey.usageLimit)
        let breakdown = perModel
            .sorted { $0.key < $1.key }
            .map { UsageBreakdown(label: $0.key, used: $0.value, limit: nil, unit: .tokens) }

        return UsageSnapshot(
            accountId: account.id,
            timestamp: timestamp,
            windows: [
                UsageWindow(
                    windowType: .monthly,
                    used: totalUsed,
                    limit: limit,
                    unit: .tokens,
                    resetDate: resetDate,
                    label: "Monthly usage"
                )
            ],
            tier: tier,
            breakdown: breakdown.isEmpty ? nil : breakdown,
            isStale: false
        )
    }

    func validateCredentials(account: Account, credential: String) async throws -> Bool {
        if (account.planType ?? "api") == "consumer" {
            let usage = try? await fetchClaudeConsumerUsage(account: account, timestamp: now())
            return !(usage?.windows.isEmpty ?? true)
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/organizations"))
        request.httpMethod = "GET"
        request.setValue(credential, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        _ = try await ProviderSupport.performJSONRequest(session: session, request: request)
        return true
    }

    private func fetchClaudeConsumerUsage(account _: Account, timestamp: Date) async throws -> (windows: [UsageWindow], tier: String?) {
        do {
            return try await fetchClaudeOAuthUsage(timestamp: timestamp)
        } catch let ServiceProviderError.unavailable(message) {
            // Rate-limit and similar transitory errors already have a clear message — forward as-is.
            throw ServiceProviderError.unavailable(message)
        } catch {
            // For unexpected errors, add the auth-refresh hint.
            throw ServiceProviderError.unavailable(
                "\(error.localizedDescription)\n\nTry running `claude auth login` in Terminal to re-authenticate."
            )
        }
    }

    private func fetchClaudeOAuthUsage(timestamp: Date) async throws -> (windows: [UsageWindow], tier: String?) {
        var credential = try credentialLoader()

        if credential.isExpired(at: timestamp) {
            credential = try await refreshClaudeOAuthCredential(current: credential)
        }

        let payload: Any
        do {
            payload = try await performClaudeOAuthUsageRequest(accessToken: credential.accessToken)
        } catch ServiceProviderError.unauthorized {
            credential = try await refreshClaudeOAuthCredential(current: credential)
            payload = try await performClaudeOAuthUsageRequest(accessToken: credential.accessToken)
        }

        let root = try ProviderSupport.dictionary(payload, context: "Claude OAuth usage response")

        let windows = [
            usageWindow(from: root["five_hour"], windowType: .rolling5h, label: "5h window"),
            usageWindow(from: root["seven_day"], windowType: .weekly, label: "Weekly cap")
        ].compactMap { $0 }

        guard !windows.isEmpty else {
            throw ServiceProviderError.invalidPayload("Claude OAuth usage response did not contain any live windows.")
        }

        return (windows, credential.displayTier)
    }

    private func performClaudeOAuthUsageRequest(accessToken: String) async throws -> Any {
        var request = URLRequest(url: baseURL.appending(path: "/api/oauth/usage"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            return try await ProviderSupport.performJSONRequest(session: session, request: request)
        } catch let ServiceProviderError.unexpectedStatus(code, _) where code == 429 {
            throw ServiceProviderError.unavailable(
                "Claude live usage is temporarily rate-limited. Keeping the last known usage until Anthropic allows another refresh."
            )
        }
    }

    private func refreshClaudeOAuthCredential(current: ClaudeOAuthCredential) async throws -> ClaudeOAuthCredential {
        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            throw ServiceProviderError.unavailable(
                "Claude Code usage token expired and no refresh token was available. Reauthenticate Claude Code."
            )
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": Self.claudeOAuthClientID
            ]
        )

        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Claude OAuth token refresh response")

        guard let accessToken = ProviderSupport.string(root["access_token"]) else {
            throw ServiceProviderError.invalidPayload("Claude OAuth token refresh response did not contain an access token.")
        }

        let refreshed = ClaudeOAuthCredential(
            accessToken: accessToken,
            refreshToken: ProviderSupport.string(root["refresh_token"]) ?? current.refreshToken,
            subscriptionType: current.subscriptionType,
            rateLimitTier: current.rateLimitTier,
            expiresAt: ProviderSupport.double(root["expires_in"]).map { now().addingTimeInterval($0) },
            scope: ProviderSupport.string(root["scope"]) ?? current.scope
        )

        do {
            try credentialPersister(refreshed)
        } catch {
            throw ServiceProviderError.unavailable(
                "Claude Code token refresh succeeded but could not be saved back to Keychain. Reauthenticate Claude Code."
            )
        }

        return refreshed
    }

    private func usageWindow(from rawValue: Any?, windowType: WindowType, label: String) -> UsageWindow? {
        guard let rawValue else { return nil }
        guard let dictionary = rawValue as? [String: Any],
              let utilization = ProviderSupport.double(dictionary["utilization"]) else {
            return nil
        }

        return UsageWindow(
            windowType: windowType,
            used: min(max(utilization, 0), 100),
            limit: 100,
            unit: .percent,
            resetDate: ProviderSupport.isoDate(dictionary["resets_at"]),
            label: label
        )
    }

    private static func loadClaudeOAuthCredential() throws -> ClaudeOAuthCredential {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeOAuthService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: {
                let context = LAContext()
                context.interactionNotAllowed = true
                return context
            }()
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw ServiceProviderError.unavailable("Claude Code credentials were not found in Keychain.")
        }

        guard let data = result as? Data else {
            throw ServiceProviderError.invalidPayload("Claude Code credentials in Keychain had an unexpected format.")
        }

        return try parseClaudeOAuthCredential(from: data)
    }

    private static func parseClaudeOAuthCredential(from data: Data) throws -> ClaudeOAuthCredential {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = payload["claudeAiOauth"] as? [String: Any],
              let accessToken = ProviderSupport.string(oauth["accessToken"]) else {
            throw ServiceProviderError.invalidPayload("Claude Code credentials in Keychain had an unexpected format.")
        }

        let expiresAt: Date?
        if let expiresAtMillis = ProviderSupport.double(oauth["expiresAt"]) {
            expiresAt = Date(timeIntervalSince1970: expiresAtMillis / 1000)
        } else {
            expiresAt = nil
        }

        return ClaudeOAuthCredential(
            accessToken: accessToken,
            refreshToken: ProviderSupport.string(oauth["refreshToken"]),
            subscriptionType: ProviderSupport.string(oauth["subscriptionType"]),
            rateLimitTier: ProviderSupport.string(oauth["rateLimitTier"]),
            expiresAt: expiresAt,
            scope: ProviderSupport.string(oauth["scope"])
        )
    }

    private static func persistClaudeOAuthCredential(_ credential: ClaudeOAuthCredential) throws {
        let expiresAtMillis = credential.expiresAt.map { $0.timeIntervalSince1970 * 1000 }
        var oauthPayload: [String: Any] = [
            "accessToken": credential.accessToken
        ]

        if let refreshToken = credential.refreshToken {
            oauthPayload["refreshToken"] = refreshToken
        }
        if let subscriptionType = credential.subscriptionType {
            oauthPayload["subscriptionType"] = subscriptionType
        }
        if let rateLimitTier = credential.rateLimitTier {
            oauthPayload["rateLimitTier"] = rateLimitTier
        }
        if let expiresAtMillis {
            oauthPayload["expiresAt"] = expiresAtMillis
        }
        if let scope = credential.scope {
            oauthPayload["scope"] = scope
        }

        let data = try JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauthPayload])
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: claudeOAuthService
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ServiceProviderError.unavailable("Could not save refreshed Claude Code credentials to Keychain.")
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw ServiceProviderError.unavailable("Could not save refreshed Claude Code credentials to Keychain.")
        }
    }
}

struct ClaudeCLIAuthStatus: Equatable, Sendable {
    let loggedIn: Bool
    let email: String?
    let subscriptionType: String?
}

protocol ClaudeAuthStatusReading: Sendable {
    func readStatus() throws -> ClaudeCLIAuthStatus
}

struct ClaudeCLIAuthStatusReader: ClaudeAuthStatusReading {
    func readStatus() throws -> ClaudeCLIAuthStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "auth", "status", "--json"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ServiceProviderError.unavailable(
                errorText?.isEmpty == false ? errorText! : "Could not read Claude auth status from the local CLI."
            )
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let payload = try JSONSerialization.jsonObject(with: data)
        let root = try ProviderSupport.dictionary(payload, context: "Claude auth status")

        return ClaudeCLIAuthStatus(
            loggedIn: (root["loggedIn"] as? Bool) ?? false,
            email: ProviderSupport.string(root["email"]),
            subscriptionType: ProviderSupport.string(root["subscriptionType"])
        )
    }
}
