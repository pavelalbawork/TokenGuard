import Foundation

struct OpenAIProvider: ServiceProvider, ConsumerAccountDetecting {
    let serviceType: ServiceType = .codex

    private let session: NetworkSession
    private let baseURL: URL
    private let codexLiveStateProvider: (any CodexLiveStateProviding)?
    private let snapshotReader: (any ConsumerUsageSnapshotReading)?
    private let cliParser: (any CLIParser)?
    private let identityReader: CodexAuthIdentityReader
    private let now: @Sendable () -> Date

    init(
        session: NetworkSession = URLSession.shared,
        baseURL: URL = URL(string: "https://api.openai.com")!,
        codexLiveStateProvider: (any CodexLiveStateProviding)? = nil,
        snapshotReader: (any ConsumerUsageSnapshotReading)? = CompositeConsumerUsageSnapshotReader(readers: [
            CodexSessionSnapshotReader()
        ]),
        cliParser: (any CLIParser)? = nil,
        identityReader: CodexAuthIdentityReader = CodexAuthIdentityReader(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.session = session
        self.baseURL = baseURL
        self.codexLiveStateProvider = codexLiveStateProvider
        self.snapshotReader = snapshotReader
        self.cliParser = cliParser
        self.identityReader = identityReader
        self.now = now
    }

    func currentConsumerIdentity() async throws -> ConsumerAccountIdentity? {
        if let authIdentity = try identityReader.readIdentity() {
            return authIdentity
        }

        if let liveIdentity = await codexLiveStateProvider?.currentState().identity {
            return liveIdentity
        }

        return nil
    }

    func fetchUsage(account: Account, credential: String) async throws -> UsageSnapshot {
        let timestamp = now()
        let planType = account.planType ?? (account.configurationValue(for: Account.ConfigurationKey.openAIOrganizationID) == nil ? "consumer" : "api")

        if planType == "consumer" {
            let consumerSnapshot = try await consumerSnapshot(for: account, timestamp: timestamp)
            return UsageSnapshot(
                accountId: account.id,
                timestamp: timestamp,
                windows: consumerSnapshot.windows,
                tier: consumerSnapshot.tier ?? "Consumer",
                breakdown: nil,
                isStale: false
            )
        }

        let startDate = Calendar(identifier: .gregorian).date(byAdding: .month, value: -1, to: timestamp) ?? timestamp
        let organizationID = account.configurationValue(for: Account.ConfigurationKey.openAIOrganizationID)

        let usagePayload = try await performRequest(
            path: "/v1/organization/usage/completions",
            startDate: startDate,
            now: timestamp,
            credential: credential,
            organizationID: organizationID
        )

        let costPayload = try await performRequest(
            path: "/v1/organization/costs",
            startDate: startDate,
            now: timestamp,
            credential: credential,
            organizationID: organizationID
        )

        let usageRoot = try ProviderSupport.dictionary(usagePayload, context: "OpenAI usage response")
        let usageBuckets = try ProviderSupport.array(usageRoot["data"], context: "OpenAI usage buckets")

        var tokenTotal = 0.0
        var perModel: [String: Double] = [:]

        for bucket in usageBuckets {
            let results = (bucket["results"] as? [[String: Any]]) ?? (bucket["result"] as? [[String: Any]]) ?? []
            for result in results {
                let inputTokens = ProviderSupport.double(result["input_tokens"]) ?? 0
                let outputTokens = ProviderSupport.double(result["output_tokens"]) ?? 0
                let total = inputTokens + outputTokens
                tokenTotal += total

                if let model = ProviderSupport.string(result["model"]) ?? ProviderSupport.string(result["snapshot_id"]) {
                    perModel[model, default: 0] += total
                }
            }
        }

        let costRoot = try ProviderSupport.dictionary(costPayload, context: "OpenAI costs response")
        let costBuckets = try ProviderSupport.array(costRoot["data"], context: "OpenAI cost buckets")

        let totalCost = costBuckets.reduce(0.0) { partial, bucket in
            let results = (bucket["results"] as? [[String: Any]]) ?? (bucket["result"] as? [[String: Any]]) ?? []
            let bucketCost = results.reduce(0.0) { subtotal, result in
                if let amount = ProviderSupport.double(result["amount_value"]) {
                    return subtotal + amount
                }

                if let amountObject = result["amount"] as? [String: Any],
                   let amount = ProviderSupport.double(amountObject["value"]) {
                    return subtotal + amount
                }

                return subtotal
            }

            return partial + bucketCost
        }

        let budgetLimit = account.configurationDouble(for: Account.ConfigurationKey.openAIMonthlyBudgetUSD)
        let tokenLimit = account.configurationDouble(for: Account.ConfigurationKey.openAITokenLimit)
        let resetDate = ProviderSupport.monthlyResetDate(
            resetDayOfMonth: account.configurationInt(for: Account.ConfigurationKey.resetDayOfMonth),
            resetHourUTC: account.configurationInt(for: Account.ConfigurationKey.resetHourUTC),
            from: timestamp
        )

        let windows: [UsageWindow]
        if let budgetLimit {
            windows = [
                UsageWindow(
                    windowType: .monthly,
                    used: totalCost,
                    limit: budgetLimit,
                    unit: .dollars,
                    resetDate: resetDate,
                    label: "Monthly budget"
                )
            ]
        } else {
            windows = [
                UsageWindow(
                    windowType: .monthly,
                    used: tokenTotal,
                    limit: tokenLimit,
                    unit: .tokens,
                    resetDate: resetDate,
                    label: "Monthly usage"
                )
            ]
        }

        let breakdown = perModel
            .sorted { $0.key < $1.key }
            .map { UsageBreakdown(label: $0.key, used: $0.value, limit: nil, unit: .tokens) }

        return UsageSnapshot(
            accountId: account.id,
            timestamp: timestamp,
            windows: windows,
            tier: nil,
            breakdown: breakdown.isEmpty ? nil : breakdown,
            isStale: false
        )
    }

    func validateCredentials(account: Account, credential: String) async throws -> Bool {
        if (account.planType ?? "api") == "consumer" {
            let snapshot = try? await consumerSnapshot(for: account, timestamp: now())
            return !(snapshot?.windows.isEmpty ?? true)
        }

        var request = URLRequest(url: baseURL.appending(path: "/v1/models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")

        _ = try await ProviderSupport.performJSONRequest(session: session, request: request)
        return true
    }

    private func consumerSnapshot(for account: Account, timestamp: Date) async throws -> CodexConsumerSnapshot {
        var liveStateError: Error?

        if let liveState = await codexLiveStateProvider?.currentState() {
            if let liveSnapshot = liveState.snapshot, !liveSnapshot.windows.isEmpty {
                return liveSnapshot
            }

            if let lastErrorText = liveState.lastErrorText,
               liveState.status == .error {
                liveStateError = ServiceProviderError.unavailable(lastErrorText)
            }
        }

        if let snapshotReader {
            let snapshotWindows = try? snapshotReader.windows(for: serviceType)
            if let windows = snapshotWindows ?? nil, !windows.isEmpty {
                return CodexConsumerSnapshot(windows: windows, identity: nil, tier: nil)
            }
        }

        if let cliParser, let windows = try? await cliParser.parseUsageOutput(), !windows.isEmpty {
            return CodexConsumerSnapshot(windows: windows, identity: nil, tier: nil)
        }

        if let liveStateError {
            throw liveStateError
        }

        _ = account
        _ = timestamp
        throw ServiceProviderError.unavailable(
            "Codex consumer usage was not found from Codex app-server, local Codex sessions, or the Codex CLI status probe on this Mac."
        )
    }

    private func performRequest(
        path: String,
        startDate: Date,
        now: Date,
        credential: String,
        organizationID: String?
    ) async throws -> Any {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(startDate.timeIntervalSince1970))),
            URLQueryItem(name: "end_time", value: String(Int(now.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d")
        ]

        guard let url = components?.url else {
            throw ServiceProviderError.invalidPayload("Could not build OpenAI request URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        if let organizationID {
            request.setValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }

        return try await ProviderSupport.performJSONRequest(session: session, request: request)
    }
}
