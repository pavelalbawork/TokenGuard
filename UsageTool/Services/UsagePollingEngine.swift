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

        var isStale: Bool {
            snapshot != nil && errorMessage != nil
        }
    }

    private let accountStore: AccountStore
    private let keychainManager: KeychainManager
    private let snapshotCache: UsageSnapshotCache
    private let providers: [ServiceType: ServiceProvider]
    private let sleep: @Sendable (TimeInterval) async -> Void

    var serviceRefreshIntervals: [ServiceType: TimeInterval]
    var accountStates: [UUID: AccountRefreshState]
    var isRefreshing: Bool

    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?

    init(
        accountStore: AccountStore,
        keychainManager: KeychainManager,
        snapshotCache: UsageSnapshotCache = UsageSnapshotCache(),
        providers: [ServiceType: ServiceProvider] = [
            .claude: AnthropicProvider(),
            .codex: OpenAIProvider(),
            .gemini: GeminiProvider(),
            .antigravity: AntigravityProvider()
        ],
        serviceRefreshIntervals: [ServiceType: TimeInterval] = [
            .claude: 300,
            .codex: 5,
            .gemini: 300,
            .antigravity: 30
        ],
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { interval in
            let nanoseconds = UInt64(max(interval, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.accountStore = accountStore
        self.keychainManager = keychainManager
        self.snapshotCache = snapshotCache
        self.providers = providers
        self.serviceRefreshIntervals = serviceRefreshIntervals
        self.sleep = sleep
        self.accountStates = UsagePollingEngine.initialAccountStates(
            accounts: accountStore.accounts,
            snapshotCache: snapshotCache
        )
        self.isRefreshing = false
    }

    deinit {
        pollingTask?.cancel()
    }

    var snapshots: [UsageSnapshot] {
        accountStates.values.compactMap(\.snapshot)
    }

    func start() {
        guard pollingTask == nil else { return }

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
    }

    func refreshAll(force: Bool = true) async {
        guard !isRefreshing else { return }
        await synchronizeActiveConsumerAccounts()

        isRefreshing = true
        defer { isRefreshing = false }

        let accounts = accountStore.accounts
            .filter(\.isEnabled)
            .filter { shouldPoll($0) }
            .filter { account in
                force || shouldRefresh(account)
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
    }

    func refresh(accountID: UUID) async {
        await synchronizeActiveConsumerAccounts()

        guard let account = accountStore.accounts.first(where: { $0.id == accountID }),
              let provider = providers[account.serviceType] else {
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

    private func apply(result: Result<UsageSnapshot, Error>, to accountID: UUID) {
        var updatedStates = accountStates
        var state = updatedStates[accountID] ?? AccountRefreshState()
        state.lastAttemptAt = Date()

        switch result {
        case let .success(snapshot):
            state.snapshot = snapshot.markingStale(false)
            state.errorMessage = nil
            state.lastSuccessAt = snapshot.timestamp
            try? snapshotCache.save(snapshot: snapshot)
        case let .failure(error):
            if let snapshot = state.snapshot {
                state.snapshot = snapshot.markingStale(true)
            }
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        updatedStates[accountID] = state
        accountStates = updatedStates
    }

    private var pollCadence: TimeInterval {
        let activeServiceTypes = Set(
            accountStore.accounts
                .filter(\.isEnabled)
                .map(\.serviceType)
        )

        guard !activeServiceTypes.isEmpty else {
            return 300
        }

        let activeIntervals = activeServiceTypes.compactMap { serviceRefreshIntervals[$0] }
        return max(activeIntervals.min() ?? 300, 1)
    }

    private func synchronizeActiveConsumerAccounts() async {
        let consumerAccountsByService = Dictionary(
            grouping: accountStore.accounts.filter { $0.isEnabled && $0.planType == "consumer" },
            by: \.serviceType
        )

        for (serviceType, accounts) in consumerAccountsByService where accounts.count > 1 {
            guard let detector = providers[serviceType] as? any ConsumerAccountDetecting else {
                continue
            }

            guard let identity = try? await detector.currentConsumerIdentity() else {
                continue
            }

            guard let matchedAccount = matchingConsumerAccount(for: identity, in: accounts) else {
                continue
            }

            if accountStore.activeConsumerAccountID(for: serviceType) != matchedAccount.id {
                try? accountStore.setActiveConsumer(matchedAccount.id, for: serviceType)
            }

            let updatedAccount = matchedAccount.withStoredConsumerIdentity(identity)
            if updatedAccount != matchedAccount {
                try? accountStore.update(updatedAccount)
            }
        }
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

    private func shouldPoll(_ account: Account) -> Bool {
        if account.planType == "consumer",
           accountStore.activeConsumerAccountID(for: account.serviceType) != account.id {
            return false
        }
        return true
    }

    private func shouldRefresh(_ account: Account) -> Bool {
        let interval = serviceRefreshIntervals[account.serviceType] ?? 300
        guard let lastAttempt = accountStates[account.id]?.lastAttemptAt else {
            return true
        }
        return Date().timeIntervalSince(lastAttempt) >= interval
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

    private nonisolated static func pollingCredential(
        for account: Account,
        keychainManager: KeychainManager
    ) throws -> String {
        _ = account
        _ = keychainManager
        return ""
    }
}
