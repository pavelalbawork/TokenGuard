import Foundation
import Observation

@MainActor
@Observable
final class UsagePollingEngine {
    struct AccountRefreshState: Sendable {
        var snapshot: UsageSnapshot?
        var errorMessage: String?
        var lastAttemptAt: Date?
        var lastSuccessAt: Date?
        var connectionStatus: CodexConnectionStatus?

        var isStale: Bool {
            snapshot != nil && errorMessage != nil
        }
    }

    private let accountStore: AccountStore
    private let keychainManager: KeychainManager
    private let snapshotCache: UsageSnapshotCache
    private let providers: [ServiceType: ServiceProvider]
    private let codexClient: CodexAppServerClient
    private let refreshIntervalProvider: @Sendable () -> TimeInterval?
    private let identitySyncInterval: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void

    var serviceRefreshIntervals: [ServiceType: TimeInterval]
    var accountStates: [UUID: AccountRefreshState]
    var isRefreshing: Bool
    var backgroundErrorMessage: String?
    private var pendingForceRefresh: Bool = false
    private var lastIdentitySyncAt: [ServiceType: Date] = [:]

    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?
    @ObservationIgnored
    private var codexUpdatesTask: Task<Void, Never>?

    init(
        accountStore: AccountStore,
        keychainManager: KeychainManager,
        snapshotCache: UsageSnapshotCache = UsageSnapshotCache(),
        codexClient: CodexAppServerClient = CodexAppServerClient(),
        providers: [ServiceType: ServiceProvider]? = nil,
        serviceRefreshIntervals: [ServiceType: TimeInterval] = [
            .claude: 300,
            .codex: 5,
            .gemini: 60,
            .antigravity: 30
        ],
        refreshIntervalProvider: @escaping @Sendable () -> TimeInterval? = {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: "globalRefreshIntervalMins") != nil else {
                return nil
            }
            let minutes = defaults.integer(forKey: "globalRefreshIntervalMins")
            return minutes > 0 ? TimeInterval(minutes * 60) : nil
        },
        identitySyncInterval: TimeInterval = 60,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            let nanoseconds = UInt64(max(interval, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.accountStore = accountStore
        self.keychainManager = keychainManager
        self.snapshotCache = snapshotCache
        self.codexClient = codexClient
        self.providers = providers ?? [
            .claude: AnthropicProvider(),
            .codex: OpenAIProvider(codexLiveStateProvider: codexClient),
            .gemini: GeminiCLIProvider(),
            .antigravity: AntigravityProvider()
        ]
        self.serviceRefreshIntervals = serviceRefreshIntervals
        self.refreshIntervalProvider = refreshIntervalProvider
        self.identitySyncInterval = identitySyncInterval
        self.sleep = sleep
        self.accountStates = UsagePollingEngine.initialAccountStates(
            accounts: accountStore.accounts,
            snapshotCache: snapshotCache
        )
        self.isRefreshing = false
        self.backgroundErrorMessage = nil
        normalizeExpiredSnapshots()
    }

    deinit {
        pollingTask?.cancel()
        codexUpdatesTask?.cancel()
    }

    var snapshots: [UsageSnapshot] {
        accountStates.values.compactMap(\.snapshot)
    }

    func start() {
        guard pollingTask == nil else { return }

        codexUpdatesTask = Task { [weak self] in
            guard let self else { return }
            await self.codexClient.start()
            let updates = await self.codexClient.updates()
            for await state in updates {
                await self.handleCodexLiveState(state)
            }
        }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshAll(force: false)
                await self.sleep(self.pollCadence)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        codexUpdatesTask?.cancel()
        codexUpdatesTask = nil
        Task { await codexClient.stop() }
    }

    func refreshAll(force: Bool = true) async {
        if isRefreshing {
            if force { pendingForceRefresh = true }
            return
        }

        var shouldForce = force

        repeat {
            normalizeExpiredSnapshots()
            await synchronizeActiveConsumerAccounts(force: shouldForce)
            if shouldForce {
                await codexClient.requestImmediateRefresh()
            }

            isRefreshing = true

            let accounts = accountStore.accounts
                .filter(\.isEnabled)
                .filter { shouldPoll($0) }
                .filter { account in
                    shouldForce || shouldRefresh(account)
                }
            await withTaskGroup(of: (UUID, Result<UsageSnapshot, Error>).self) { group in
                for account in accounts {
                    group.addTask { [providers, keychainManager] in
                        guard let provider = providers[account.serviceType] else {
                            return (account.id, .failure(ServiceProviderError.unavailable("No provider registered for \(account.serviceType.rawValue).")))
                        }

                        do {
                            let credential = try Self.pollingCredential(
                                for: account,
                                keychainManager: keychainManager
                            )
                            let snapshot = try await provider.fetchUsage(account: account, credential: credential)
                            return (account.id, .success(snapshot))
                        } catch {
                            return (account.id, .failure(error))
                        }
                    }
                }

                for await (accountID, result) in group {
                    apply(result: result, to: accountID)
                }
            }

            isRefreshing = false

            // If a forced refresh was requested while we were mid-cycle, honor it now.
            if pendingForceRefresh {
                pendingForceRefresh = false
                shouldForce = true
            } else {
                break
            }
        } while true
    }

    func refresh(accountID: UUID) async {
        normalizeExpiredSnapshots()
        await synchronizeActiveConsumerAccounts(force: true)

        guard let account = accountStore.accounts.first(where: { $0.id == accountID }),
              let provider = providers[account.serviceType] else {
            return
        }

        if usesSubscribedRefresh(account) {
            await codexClient.requestImmediateRefresh()
            return
        }

        guard shouldPoll(account) else {
            return
        }

        updateAccountState(for: accountID) { state in
            state.lastAttemptAt = Date()
        }

        do {
            let credential = try Self.pollingCredential(
                for: account,
                keychainManager: keychainManager
            )
            let snapshot = try await provider.fetchUsage(account: account, credential: credential)
            apply(result: .success(snapshot), to: accountID)
        } catch {
            apply(result: .failure(error), to: accountID)
        }
    }

    func deleteAccount(_ account: Account) throws {
        try accountStore.remove(accountID: account.id)

        if !account.credentialRef.isEmpty {
            try keychainManager.deleteSecret(reference: account.credentialRef)
        }

        try snapshotCache.remove(accountID: account.id)
        accountStates.removeValue(forKey: account.id)
    }

    private func apply(result: Result<UsageSnapshot, Error>, to accountID: UUID) {
        var updatedStates = accountStates
        var state = updatedStates[accountID] ?? AccountRefreshState()
        state.lastAttemptAt = Date()

        switch result {
        case let .success(snapshot):
            state.snapshot = snapshot.markingStale(false)
            state.errorMessage = nil
            state.lastSuccessAt = snapshot.timestamp
            state.connectionStatus = nil
            do {
                try snapshotCache.save(snapshot: snapshot)
                backgroundErrorMessage = nil
            } catch {
                recordBackgroundError("Could not save usage snapshot", error)
            }
        case let .failure(error):
            if let snapshot = state.snapshot {
                state.snapshot = snapshot.markingStale(true)
            }
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state.connectionStatus = nil
        }

        updatedStates[accountID] = state
        accountStates = updatedStates
    }

    var pollCadence: TimeInterval {
        let pollableAccounts = accountStore.accounts
            .filter(\.isEnabled)
            .filter { shouldPoll($0) }

        guard !pollableAccounts.isEmpty else {
            return 300
        }

        let activeIntervals = pollableAccounts.map { refreshInterval(for: $0) }
        return max(activeIntervals.min() ?? 300, 1)
    }

    private func synchronizeActiveConsumerAccounts(force: Bool = false) async {
        let consumerAccountsByService = Dictionary(
            grouping: accountStore.accounts.filter { $0.isEnabled && $0.planType == "consumer" },
            by: \.serviceType
        )

        for (serviceType, accounts) in consumerAccountsByService {
            if !force, shouldSkipIdentitySync(for: serviceType) {
                continue
            }
            lastIdentitySyncAt[serviceType] = Date()

            let identity: ConsumerAccountIdentity?
            if serviceType == .codex {
                let liveIdentity = await codexClient.currentState().identity
                let localIdentity: ConsumerAccountIdentity?
                if let detector = providers[serviceType] as? any ConsumerAccountDetecting {
                    localIdentity = try? await detector.currentConsumerIdentity()
                } else {
                    localIdentity = nil
                }

                if identitiesConflict(localIdentity, liveIdentity) {
                    await codexClient.restart()
                }

                identity = localIdentity ?? liveIdentity
            } else {
                guard let detector = providers[serviceType] as? any ConsumerAccountDetecting else {
                    continue
                }
                identity = try? await detector.currentConsumerIdentity()
            }

            guard let identity else { continue }

            guard let matchedAccount = matchingConsumerAccount(for: identity, in: accounts) else {
                continue
            }

            if accountStore.activeConsumerAccountID(for: serviceType) != matchedAccount.id {
                do {
                    try accountStore.setActiveConsumer(matchedAccount.id, for: serviceType)
                    backgroundErrorMessage = nil
                } catch {
                    recordBackgroundError("Could not update active \(serviceType.rawValue) account", error)
                }
            }

            let updatedAccount = matchedAccount.withStoredConsumerIdentity(identity)
            if updatedAccount != matchedAccount {
                do {
                    try accountStore.update(updatedAccount)
                    backgroundErrorMessage = nil
                } catch {
                    recordBackgroundError("Could not save \(serviceType.rawValue) account identity", error)
                }
            }
        }
    }

    private func shouldSkipIdentitySync(for serviceType: ServiceType) -> Bool {
        guard let lastSync = lastIdentitySyncAt[serviceType] else {
            return false
        }
        return Date().timeIntervalSince(lastSync) < identitySyncInterval
    }

    private func matchingConsumerAccount(for identity: ConsumerAccountIdentity, in accounts: [Account]) -> Account? {
        accounts
            .compactMap { account in
                account.matchingConsumerIdentityScore(identity).map { (score: $0, account: account) }
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.account.name.localizedCaseInsensitiveCompare(rhs.account.name) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
            .first?
            .account
    }

    private func identitiesConflict(_ localIdentity: ConsumerAccountIdentity?, _ liveIdentity: ConsumerAccountIdentity?) -> Bool {
        guard let localIdentity, let liveIdentity else {
            return false
        }

        if let localEmail = normalizedIdentity(localIdentity.email),
           let liveEmail = normalizedIdentity(liveIdentity.email),
           localEmail != liveEmail {
            return true
        }

        if let localExternalID = normalizedIdentity(localIdentity.externalID),
           let liveExternalID = normalizedIdentity(liveIdentity.externalID),
           localExternalID != liveExternalID {
            return true
        }

        return false
    }

    private func normalizedIdentity(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func shouldPoll(_ account: Account) -> Bool {
        if usesSubscribedRefresh(account) {
            return false
        }
        if account.planType == "consumer",
           accountStore.activeConsumerAccountID(for: account.serviceType) != account.id {
            return false
        }
        return true
    }

    private func usesSubscribedRefresh(_ account: Account) -> Bool {
        account.serviceType == .codex && account.planType == "consumer"
    }

    private func shouldRefresh(_ account: Account) -> Bool {
        let interval = refreshInterval(for: account)
        guard let lastAttempt = accountStates[account.id]?.lastAttemptAt else {
            return true
        }
        return Date().timeIntervalSince(lastAttempt) >= interval
    }

    private func refreshInterval(for account: Account) -> TimeInterval {
        refreshIntervalProvider() ?? serviceRefreshIntervals[account.serviceType] ?? 300
    }

    private static func initialAccountStates(
        accounts: [Account],
        snapshotCache: UsageSnapshotCache
    ) -> [UUID: AccountRefreshState] {
        guard let cachedSnapshots = try? snapshotCache.load() else {
            return [:]
        }

        var states: [UUID: AccountRefreshState] = [:]
        for account in accounts {
            if let snapshot = cachedSnapshots[account.id] {
                states[account.id] = AccountRefreshState(
                    snapshot: snapshot,
                    errorMessage: nil,
                    lastAttemptAt: nil,
                    lastSuccessAt: snapshot.timestamp
                )
            }
        }
        return states
    }

    private func updateAccountState(
        for accountID: UUID,
        _ mutate: (inout AccountRefreshState) -> Void
    ) {
        var updatedStates = accountStates
        var state = updatedStates[accountID] ?? AccountRefreshState()
        mutate(&state)
        updatedStates[accountID] = state
        accountStates = updatedStates
    }

    private func normalizeExpiredSnapshots(now: Date = Date()) {
        var updatedStates = accountStates
        var didChangeAnyState = false

        for (accountID, state) in accountStates {
            guard let account = accountStore.accounts.first(where: { $0.id == accountID }) else {
                continue
            }
            guard account.planType == "consumer",
                  accountStore.activeConsumerAccountID(for: account.serviceType) != account.id else {
                continue
            }
            guard let snapshot = state.snapshot else { continue }
            let normalized = snapshot.resettingExpiredWindows(now: now)
            guard normalized != snapshot else { continue }

            var updatedState = state
            updatedState.snapshot = normalized
            updatedStates[accountID] = updatedState
            didChangeAnyState = true

            do {
                try snapshotCache.save(snapshot: normalized)
                backgroundErrorMessage = nil
            } catch {
                recordBackgroundError("Could not save normalized usage snapshot", error)
            }
        }

        if didChangeAnyState {
            accountStates = updatedStates
        }
    }

    private nonisolated static func pollingCredential(
        for account: Account,
        keychainManager: KeychainManager
    ) throws -> String {
        if account.credentialRef.isEmpty {
            return ""
        }
        return try keychainManager.readSecret(reference: account.credentialRef) ?? ""
    }

    private func handleCodexLiveState(_ liveState: CodexLiveState) async {
        let codexAccounts = accountStore.accounts.filter {
            $0.isEnabled && $0.serviceType == .codex && $0.planType == "consumer"
        }

        guard !codexAccounts.isEmpty else { return }

        let localIdentity: ConsumerAccountIdentity?
        if let detector = providers[.codex] as? any ConsumerAccountDetecting {
            localIdentity = try? await detector.currentConsumerIdentity()
        } else {
            localIdentity = nil
        }

        if identitiesConflict(localIdentity, liveState.identity) {
            if let localIdentity,
               let matchedAccount = matchingConsumerAccount(for: localIdentity, in: codexAccounts) {
                activateCodexConsumerAccount(matchedAccount, identity: localIdentity)
            }
            await codexClient.restart()
            return
        }

        let effectiveIdentity = localIdentity ?? liveState.identity

        if let identity = effectiveIdentity,
           let matchedAccount = matchingConsumerAccount(for: identity, in: codexAccounts) {
            activateCodexConsumerAccount(matchedAccount, identity: identity)
        }

        guard let activeAccountID = accountStore.activeConsumerAccountID(for: .codex),
              let activeAccount = accountStore.accounts.first(where: { $0.id == activeAccountID }) else {
            return
        }

        var updatedStates = accountStates
        var state = updatedStates[activeAccountID] ?? AccountRefreshState()
        state.connectionStatus = liveState.status
        state.lastAttemptAt = Date()

        if let liveSnapshot = liveState.snapshot {
            let snapshot = UsageSnapshot(
                accountId: activeAccount.id,
                timestamp: liveState.lastUpdateAt ?? Date(),
                windows: liveSnapshot.windows,
                tier: liveSnapshot.tier,
                breakdown: nil,
                isStale: liveState.status != .live
            )
            state.snapshot = snapshot
            state.lastSuccessAt = snapshot.timestamp
            state.errorMessage = liveState.status == .error ? liveState.lastErrorText : nil
            do {
                try snapshotCache.save(snapshot: snapshot)
                backgroundErrorMessage = nil
            } catch {
                recordBackgroundError("Could not save Codex live snapshot", error)
            }
        } else if let fallbackSnapshot = await codexFallbackSnapshot(for: activeAccount) {
            state.snapshot = fallbackSnapshot.markingStale(liveState.status != .live)
            state.lastSuccessAt = fallbackSnapshot.timestamp
            state.errorMessage = liveState.status == .error ? liveState.lastErrorText : nil
            do {
                try snapshotCache.save(snapshot: fallbackSnapshot)
                backgroundErrorMessage = nil
            } catch {
                recordBackgroundError("Could not save Codex fallback snapshot", error)
            }
        } else if let existingSnapshot = state.snapshot {
            state.snapshot = existingSnapshot.markingStale(liveState.status != .live)
            if liveState.status == .error {
                state.errorMessage = liveState.lastErrorText
            }
        } else if liveState.status == .error {
            state.errorMessage = liveState.lastErrorText ?? "Codex live usage is unavailable."
        } else {
            state.errorMessage = nil
        }

        updatedStates[activeAccountID] = state
        accountStates = updatedStates
    }

    private func codexFallbackSnapshot(for account: Account) async -> UsageSnapshot? {
        guard let provider = providers[.codex] else {
            return nil
        }

        do {
            let credential = try Self.pollingCredential(
                for: account,
                keychainManager: keychainManager
            )
            return try await provider.fetchUsage(account: account, credential: credential)
        } catch {
            return nil
        }
    }

    private func activateCodexConsumerAccount(_ matchedAccount: Account, identity: ConsumerAccountIdentity) {
        let previousActiveID = accountStore.activeConsumerAccountID(for: .codex)
        if previousActiveID != matchedAccount.id {
            do {
                try accountStore.setActiveConsumer(matchedAccount.id, for: .codex)
                backgroundErrorMessage = nil
            } catch {
                recordBackgroundError("Could not update active Codex account", error)
            }

            // Keep the old account's snapshot (as stale) so the UI can still show
            // last-known data. Only clear the live connection status so the LIVE
            // badge and error go away.
            if let previousActiveID {
                var updatedStates = accountStates
                var oldState = updatedStates[previousActiveID] ?? {
                    if let cached = (try? snapshotCache.load())?[previousActiveID] {
                        return AccountRefreshState(
                            snapshot: cached.markingStale(true),
                            errorMessage: nil,
                            lastAttemptAt: nil,
                            lastSuccessAt: cached.timestamp
                        )
                    }
                    return AccountRefreshState()
                }()
                if let snap = oldState.snapshot {
                    oldState.snapshot = snap.markingStale(true)
                }
                oldState.connectionStatus = nil
                oldState.errorMessage = nil
                updatedStates[previousActiveID] = oldState
                accountStates = updatedStates
            }
        }

        let updatedAccount = matchedAccount.withStoredConsumerIdentity(identity)
        if updatedAccount != matchedAccount {
            do {
                try accountStore.update(updatedAccount)
                backgroundErrorMessage = nil
            } catch {
                recordBackgroundError("Could not save Codex account identity", error)
            }
        }
    }

    private func recordBackgroundError(_ context: String, _ error: Error) {
        backgroundErrorMessage = "\(context): \(error.localizedDescription)"
    }
}
