import Foundation

struct GeminiProvider: ServiceProvider {
    let serviceType: ServiceType = .gemini

    private let session: NetworkSession
    private let monitoringBaseURL: URL
    private let oauthManager: any GoogleOAuthManaging
    private let now: @Sendable () -> Date

    init(
        session: NetworkSession = URLSession.shared,
        monitoringBaseURL: URL = URL(string: "https://monitoring.googleapis.com")!,
        oauthManager: any GoogleOAuthManaging = GoogleOAuthManager(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.monitoringBaseURL = monitoringBaseURL
        self.oauthManager = oauthManager
        self.now = now
    }

    func fetchUsage(account: Account, credential: String) async throws -> UsageSnapshot {
        guard !credential.isEmpty else {
            throw ServiceProviderError.unavailable(
                "Gemini background refresh is disabled until local credentials are reworked to avoid Keychain prompts."
            )
        }

        guard let projectID = account.configurationValue(for: Account.ConfigurationKey.googleProjectID) else {
            throw ServiceProviderError.missingConfiguration("Gemini accounts require a Google Cloud project ID.")
        }

        let timestamp = now()
        let accessToken = try await oauthManager.accessToken(using: credential, account: account)
        let startDate = ProviderSupport.startOfCurrentUTCDay(from: timestamp)
        let requestMetricType = account.configurationValue(for: Account.ConfigurationKey.googleRequestMetricType)
            ?? "aiplatform.googleapis.com/prediction/online/request_count"
        let tokenMetricType = account.configurationValue(for: Account.ConfigurationKey.googleTokenMetricType)
            ?? "aiplatform.googleapis.com/prediction/online/total_tokens"

        async let requestPayload = fetchTimeSeries(
            projectID: projectID,
            metricType: requestMetricType,
            startDate: startDate,
            endDate: timestamp,
            accessToken: accessToken
        )
        async let tokenPayload = fetchTimeSeries(
            projectID: projectID,
            metricType: tokenMetricType,
            startDate: startDate,
            endDate: timestamp,
            accessToken: accessToken
        )

        let requestTotal = try await parseSeriesTotal(from: requestPayload)
        let tokenTotal = try await parseSeriesTotal(from: tokenPayload)

        let requestLimit = account.configurationDouble(for: Account.ConfigurationKey.googleRequestLimit)
        let tokenLimit = account.configurationDouble(for: Account.ConfigurationKey.googleTokenLimit)
        let resetDate = ProviderSupport.endOfCurrentUTCDay(from: timestamp)

        var windows: [UsageWindow] = [
            UsageWindow(
                windowType: .daily,
                used: requestTotal,
                limit: requestLimit,
                unit: .requests,
                resetDate: resetDate,
                label: "Daily requests"
            )
        ]

        if tokenTotal > 0 || tokenLimit != nil {
            windows.append(
                UsageWindow(
                    windowType: .daily,
                    used: tokenTotal,
                    limit: tokenLimit,
                    unit: .tokens,
                    resetDate: resetDate,
                    label: "Daily tokens"
                )
            )
        }

        return UsageSnapshot(
            accountId: account.id,
            timestamp: timestamp,
            windows: windows,
            tier: nil,
            breakdown: tokenTotal > 0 ? [
                UsageBreakdown(label: "Tokens", used: tokenTotal, limit: tokenLimit, unit: .tokens)
            ] : nil,
            isStale: false
        )
    }

    func validateCredentials(account: Account, credential: String) async throws -> Bool {
        guard !credential.isEmpty else {
            return false
        }
        _ = try await oauthManager.accessToken(using: credential, account: account)
        return true
    }



    private func fetchTimeSeries(
        projectID: String,
        metricType: String,
        startDate: Date,
        endDate: Date,
        accessToken: String
    ) async throws -> Any {
        var components = URLComponents(
            url: monitoringBaseURL.appending(path: "/v3/projects/\(projectID)/timeSeries"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "filter", value: "metric.type=\"\(metricType)\""),
            URLQueryItem(name: "interval.startTime", value: ISO8601DateFormatter().string(from: startDate)),
            URLQueryItem(name: "interval.endTime", value: ISO8601DateFormatter().string(from: endDate))
        ]

        guard let url = components?.url else {
            throw ServiceProviderError.invalidPayload("Could not build Cloud Monitoring URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        return try await ProviderSupport.performJSONRequest(session: session, request: request)
    }

    private func parseSeriesTotal(from payload: Any) throws -> Double {
        let root = try ProviderSupport.dictionary(payload, context: "Google timeSeries response")
        let series = (root["timeSeries"] as? [[String: Any]]) ?? []

        return series.reduce(0.0) { total, item in
            let points = (item["points"] as? [[String: Any]]) ?? []
            let pointTotal = points.reduce(0.0) { subtotal, point in
                guard let value = point["value"] as? [String: Any] else { return subtotal }
                let numericValue =
                    ProviderSupport.double(value["doubleValue"]) ??
                    ProviderSupport.double(value["int64Value"])
                return subtotal + (numericValue ?? 0)
            }
            return total + pointTotal
        }
    }
}
