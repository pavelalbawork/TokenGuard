import Foundation

private struct GeminiCLIOAuthCredential: Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
    let tokenType: String?
    let scope: String?

    func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date.addingTimeInterval(60)
    }
}

private struct GeminiCodeAssistContext: Sendable {
    let projectID: String
    let tierName: String?
}

private struct GeminiQuotaBucket: Sendable {
    let modelID: String
    let tokenType: String?
    let remainingAmount: Double?
    let remainingFraction: Double?
    let resetTime: Date?
}

struct GeminiCLIProvider: ServiceProvider, ConsumerAccountDetecting {
    let serviceType: ServiceType = .gemini

    private static let oauthClientID = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
    private static let oauthClientSecret = "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"
    private static let userAgent = "gemini-cli/0.37.0 TokenGuard"

    private let googleAccountsURL: URL
    private let oauthCredentialsURL: URL
    private let session: NetworkSession
    private let tokenBaseURL: URL
    private let cloudCodeBaseURL: URL
    private let now: @Sendable () -> Date

    init(
        googleAccountsURL: URL = URL(fileURLWithPath: NSString(string: "~/.gemini/google_accounts.json").expandingTildeInPath),
        oauthCredentialsURL: URL = URL(fileURLWithPath: NSString(string: "~/.gemini/oauth_creds.json").expandingTildeInPath),
        session: NetworkSession = URLSession.shared,
        tokenBaseURL: URL = URL(string: "https://oauth2.googleapis.com/token")!,
        cloudCodeBaseURL: URL = URL(string: "https://cloudcode-pa.googleapis.com")!,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.googleAccountsURL = googleAccountsURL
        self.oauthCredentialsURL = oauthCredentialsURL
        self.session = session
        self.tokenBaseURL = tokenBaseURL
        self.cloudCodeBaseURL = cloudCodeBaseURL
        self.now = now
    }

    func currentConsumerIdentity() async throws -> ConsumerAccountIdentity? {
        guard let email = try readActiveEmail() else {
            return nil
        }

        return ConsumerAccountIdentity(email: email, externalID: nil)
    }

    func fetchUsage(account: Account, credential _: String) async throws -> UsageSnapshot {
        let timestamp = now()
        let oauth = try readOAuthCredential()
        let accessToken: String
        if oauth.isExpired(at: timestamp) {
            accessToken = try await refreshAccessToken(refreshToken: oauth.refreshToken)
        } else {
            accessToken = oauth.accessToken
        }

        let context = try await loadCodeAssistContext(accessToken: accessToken)
        let buckets = try await fetchQuotaBuckets(accessToken: accessToken, projectID: context.projectID)
        let allWindows = buckets.compactMap(makeUsageWindow(from:))
        
        var uniqueWindows: [UsageWindow] = []
        var seenCategories: Set<String> = []
        
        for window in allWindows {
            guard let label = window.label else { continue }
            let lowerLabel = label.lowercased()
            let category: String
            
            if lowerLabel.contains("pro") { category = "PRO" }
            else if lowerLabel.contains("flash") { category = "FLASH" }
            else if lowerLabel.contains("lite") { category = "LITE" }
            else { continue }
            
            if !seenCategories.contains(category) {
                seenCategories.insert(category)
                let cleanWindow = UsageWindow(
                    windowType: window.windowType,
                    used: window.used,
                    limit: window.limit,
                    unit: window.unit,
                    resetDate: window.resetDate,
                    label: category
                )
                uniqueWindows.append(cleanWindow)
            }
        }
        
        let order = ["PRO": 0, "FLASH": 1, "LITE": 2]
        uniqueWindows.sort {
            (order[$0.label ?? ""] ?? 99) < (order[$1.label ?? ""] ?? 99)
        }

        let breakdown = buckets.compactMap(makeBreakdown(from:))

        guard !uniqueWindows.isEmpty else {
            throw ServiceProviderError.unavailable(
                "Gemini CLI did not return any usage buckets. Run `gemini` once, confirm `/stats model` works, and try again."
            )
        }

        return UsageSnapshot(
            accountId: account.id,
            timestamp: timestamp,
            windows: uniqueWindows,
            tier: context.tierName,
            breakdown: breakdown.isEmpty ? nil : breakdown,
            isStale: false
        )
    }

    func validateCredentials(account: Account, credential: String) async throws -> Bool {
        let snapshot = try await fetchUsage(account: account, credential: credential)
        return !snapshot.windows.isEmpty
    }

    private func readActiveEmail() throws -> String? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: googleAccountsURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: googleAccountsURL)
        let payload = try JSONSerialization.jsonObject(with: data)
        let root = try ProviderSupport.dictionary(payload, context: "Gemini account state")
        return normalizedIdentity(ProviderSupport.string(root["active"]))
    }

    private func readOAuthCredential() throws -> GeminiCLIOAuthCredential {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: oauthCredentialsURL.path) else {
            throw ServiceProviderError.unavailable(
                "Gemini CLI credentials were not found. Sign in with `gemini` on this Mac first."
            )
        }

        let data = try Data(contentsOf: oauthCredentialsURL)
        let payload = try JSONSerialization.jsonObject(with: data)
        let root = try ProviderSupport.dictionary(payload, context: "Gemini OAuth credentials")

        guard let accessToken = ProviderSupport.string(root["access_token"]),
              let refreshToken = ProviderSupport.string(root["refresh_token"]) else {
            throw ServiceProviderError.invalidPayload("Gemini OAuth credentials are missing required token fields.")
        }

        return GeminiCLIOAuthCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiryDate(from: root["expiry_date"]),
            tokenType: ProviderSupport.string(root["token_type"]),
            scope: ProviderSupport.string(root["scope"])
        )
    }

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        var request = URLRequest(url: tokenBaseURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyItems = [
            URLQueryItem(name: "client_id", value: Self.oauthClientID),
            URLQueryItem(name: "client_secret", value: Self.oauthClientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]
        var components = URLComponents()
        components.queryItems = bodyItems
        request.httpBody = components.query?.data(using: .utf8)

        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Gemini OAuth refresh")
        guard let accessToken = ProviderSupport.string(root["access_token"]) else {
            throw ServiceProviderError.invalidPayload("Gemini OAuth refresh response did not contain an access token.")
        }

        return accessToken
    }

    private func loadCodeAssistContext(accessToken: String) async throws -> GeminiCodeAssistContext {
        let url = cloudCodeBaseURL.appending(path: "/v1internal:loadCodeAssist")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "cloudaicompanionProject": NSNull(),
            "metadata": [
                "ideType": "IDE_UNSPECIFIED",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ])

        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Gemini loadCodeAssist")
        guard let projectID = ProviderSupport.string(root["cloudaicompanionProject"]) else {
            throw ServiceProviderError.invalidPayload("Gemini loadCodeAssist response did not include a project.")
        }

        let currentTierName = (root["currentTier"] as? [String: Any]).flatMap { ProviderSupport.string($0["name"]) }
        let paidTierName = (root["paidTier"] as? [String: Any]).flatMap { ProviderSupport.string($0["name"]) }

        return GeminiCodeAssistContext(
            projectID: projectID,
            tierName: paidTierName ?? currentTierName
        )
    }

    private func fetchQuotaBuckets(accessToken: String, projectID: String) async throws -> [GeminiQuotaBucket] {
        let url = cloudCodeBaseURL.appending(path: "/v1internal:retrieveUserQuota")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["project": projectID])

        let payload = try await ProviderSupport.performJSONRequest(session: session, request: request)
        let root = try ProviderSupport.dictionary(payload, context: "Gemini retrieveUserQuota")
        let rawBuckets = try ProviderSupport.array(root["buckets"], context: "Gemini retrieveUserQuota buckets")

        return rawBuckets.compactMap { bucket in
            guard let modelID = ProviderSupport.string(bucket["modelId"]) else {
                return nil
            }

            return GeminiQuotaBucket(
                modelID: modelID,
                tokenType: ProviderSupport.string(bucket["tokenType"]),
                remainingAmount: ProviderSupport.double(bucket["remainingAmount"]),
                remainingFraction: ProviderSupport.double(bucket["remainingFraction"]),
                resetTime: ProviderSupport.isoDate(bucket["resetTime"])
            )
        }
    }

    private func makeUsageWindow(from bucket: GeminiQuotaBucket) -> UsageWindow? {
        let label = displayName(for: bucket.modelID)

        if let remainingAmount = bucket.remainingAmount,
           let remainingFraction = bucket.remainingFraction,
           remainingFraction > 0 {
            let limit = round(remainingAmount / remainingFraction)
            let used = max(limit - remainingAmount, 0)
            return UsageWindow(
                windowType: .daily,
                used: used,
                limit: limit,
                unit: usageUnit(for: bucket.tokenType),
                resetDate: bucket.resetTime,
                label: label
            )
        }

        if let remainingFraction = bucket.remainingFraction {
            return UsageWindow(
                windowType: .daily,
                used: max(0, 100 - (remainingFraction * 100)),
                limit: 100,
                unit: .percent,
                resetDate: bucket.resetTime,
                label: label
            )
        }

        return nil
    }

    private func makeBreakdown(from bucket: GeminiQuotaBucket) -> UsageBreakdown? {
        let label = displayName(for: bucket.modelID)

        if let remainingAmount = bucket.remainingAmount,
           let remainingFraction = bucket.remainingFraction,
           remainingFraction > 0 {
            let limit = round(remainingAmount / remainingFraction)
            let used = max(limit - remainingAmount, 0)
            return UsageBreakdown(
                label: label,
                used: used,
                limit: limit,
                unit: usageUnit(for: bucket.tokenType)
            )
        }

        if let remainingFraction = bucket.remainingFraction {
            return UsageBreakdown(
                label: label,
                used: max(0, 100 - (remainingFraction * 100)),
                limit: 100,
                unit: .percent
            )
        }

        return nil
    }

    private func usageUnit(for tokenType: String?) -> UsageUnit {
        switch tokenType?.uppercased() {
        case "TOKENS":
            return .tokens
        case "REQUESTS":
            return .requests
        default:
            return .requests
        }
    }

    private func displayName(for modelID: String) -> String {
        modelID
            .replacingOccurrences(of: "gemini-", with: "Gemini ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { token in
                if token.allSatisfy(\.isNumber) {
                    return String(token)
                }
                return token.prefix(1).uppercased() + token.dropFirst()
            }
            .joined(separator: " ")
    }

    private func expiryDate(from rawValue: Any?) -> Date? {
        guard let numeric = ProviderSupport.double(rawValue) else {
            return nil
        }

        let seconds = numeric > 10_000_000_000 ? numeric / 1000 : numeric
        return Date(timeIntervalSince1970: seconds)
    }

    private func normalizedIdentity(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
