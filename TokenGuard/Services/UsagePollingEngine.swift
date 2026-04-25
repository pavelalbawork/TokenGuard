import Foundation
import Observation

func tgLog(_ message: String) {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("TokenGuard")
        .appendingPathComponent("debug.log")
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.data(using: .utf8)?.write(to: url)
    }
}

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
            .antigravity: AntigravityProvider(keychainManager: keychainManager)
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

        if codexUpdatesTask == nil {
            codexUpdatesTask = Task { [weak self] in
                guard let self else { return }
                await self.codexClient.start()
                let updates = await self.codexClient.updates()
                for await state in updates {
                    await self.handleCodexLiveState(state)
                }
            }
        }

        startPollingLoop()
    }

    func restartPollingLoop() {
        guard pollingTask != nil else { return }
        pollingTask?.cancel()
        startPollingLoop()
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        codexUpdatesTask?.cancel()
        codexUpdatesTask = nil
        Task { await codexClient.stop() }
    }

    private func startPollingLoop() {
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshAll(force: false)
                await self.sleep(self.pollCadence)
            }
        }
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
            await refreshSubscribedAccounts(force: shouldForce)

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
            await refreshSubscribedAccounts(force: true)
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
            if let providerError = error as? ServiceProviderError,
               providerError == .credentialsStale {
                // Credentials belong to a different account (e.g. Antigravity
                // account switch detected but OAuth token hasn't refreshed).
                // Set an empty snapshot so the card stops showing "Loading..."
                // and don't set an error message. Not marked stale so it
                // shows LIVE, not STALE.
                if state.snapshot == nil {
                    state.snapshot = UsageSnapshot(
                        accountId: accountID,
                        timestamp: Date(),
                        windows: [],
                        breakdown: []
                    )
                }
                state.errorMessage = nil
                break
            }
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
            .filter { shouldAutoRefresh($0) }

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

        tgLog("[PE] synchronizeActiveConsumerAccounts: force=\(force), serviceTypes=\(consumerAccountsByService.keys.map(\.rawValue).sorted().joined(separator: ",")), totalAccounts=\(accountStore.accounts.count), consumerAccounts=\(consumerAccountsByService.values.flatMap { $0 }.count)")

        for (serviceType, accounts) in consumerAccountsByService {
            if !force, shouldSkipIdentitySync(for: serviceType) {
                tgLog("[PE] sync[\(serviceType.rawValue)]: skipped (throttled)")
                continue
            }
            lastIdentitySyncAt[serviceType] = Date()
            var restartedCodexSession = false

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
                    restartedCodexSession = true
                }

                identity = localIdentity ?? liveIdentity
            } else {
                guard let detector = providers[serviceType] as? any ConsumerAccountDetecting else {
                    continue
                }
                identity = try? await detector.currentConsumerIdentity()
            }

            guard let identity else {
                tgLog("[PE] sync[\(serviceType.rawValue)]: identity detection returned nil, skipping")
                continue
            }

            tgLog("[PE] sync[\(serviceType.rawValue)]: detected identity email=\(identity.email ?? "nil") profileUrl=\(identity.profileUrl ?? "nil")")

            // Log matching scores for all accounts
            for acct in accounts {
                let score = acct.matchingConsumerIdentityScore(identity)
                tgLog("[PE] sync[\(serviceType.rawValue)]:   account '\(acct.displayName)' email=\(acct.consumerEmail ?? "nil") profileUrl=\(acct.antigravityProfileUrl ?? "nil") → score=\(score.map(String.init) ?? "nil")")
            }

            var matchedAccount = matchingConsumerAccount(for: identity, in: accounts)

            // Antigravity-specific: when the provider detected an account switch
            // (email=nil, profileUrl-only identity) and no account matched by
            // stored profileUrl, try to infer the active account.
            if matchedAccount == nil,
               serviceType == .antigravity,
               identity.email == nil,
               let liveProfileUrl = identity.profileUrl {
                let currentActiveID = accountStore.activeConsumerAccountID(for: .antigravity)
                // For 2-account case: the active one must be the OTHER account.
                if accounts.count == 2,
                   let otherAccount = accounts.first(where: { $0.id != currentActiveID }) {
                    matchedAccount = otherAccount
                    // Store the profileUrl on this account for future matching.
                    var updated = otherAccount
                    updated.configuration[Account.ConfigurationKey.antigravityProfileUrl] = liveProfileUrl
                    try? accountStore.update(updated)
                    tgLog("[PE] sync[antigravity]: switch detected, inferred → '\(otherAccount.displayName)' and stored profileUrl")
                }
            }

            guard let matchedAccount else {
                tgLog("[PE] sync[\(serviceType.rawValue)]: no account matched, clearing active consumer")
                // Live identity is present but no registered TokenGuard account
                // claims it. Unmark any stale active consumer so the UI stops
                // labelling the wrong account as "live".
                if accountStore.activeConsumerAccountID(for: serviceType) != nil {
                    do {
                        try accountStore.clearActiveConsumer(for: serviceType)
                        backgroundErrorMessage = nil
                    } catch {
                        recordBackgroundError("Could not clear active \(serviceType.rawValue) account", error)
                    }
                }
                continue
            }

            tgLog("[PE] sync[\(serviceType.rawValue)]: matched → '\(matchedAccount.displayName)' (id=\(matchedAccount.id.uuidString))")

            // Antigravity bootstrap: when the email match is confident (no
            // switch detected, email present) and the account has no stored
            // profileUrl, capture the current profileUrl for future switch
            // detection.
            if serviceType == .antigravity,
               identity.email != nil,
               matchedAccount.antigravityProfileUrl == nil,
               let liveProfileUrl = identity.profileUrl {
                var updated = matchedAccount
                updated.configuration[Account.ConfigurationKey.antigravityProfileUrl] = liveProfileUrl
                try? accountStore.update(updated)
                tgLog("[PE] sync[antigravity]: bootstrapped profileUrl on '\(matchedAccount.displayName)'")
            }

            if serviceType == .codex {
                let switchedAccounts = accountStore.activeConsumerAccountID(for: .codex) != matchedAccount.id
                activateCodexConsumerAccount(matchedAccount, identity: identity)
                if switchedAccounts && !restartedCodexSession {
                    await codexClient.restart()
                }
                continue
            }

            let previousActiveID = accountStore.activeConsumerAccountID(for: serviceType)
            if previousActiveID != matchedAccount.id {
                tgLog("[PE] sync[\(serviceType.rawValue)]: SWITCHING active consumer from \(previousActiveID?.uuidString ?? "none") → \(matchedAccount.id.uuidString)")
                do {
                    try accountStore.setActiveConsumer(matchedAccount.id, for: serviceType)
                    backgroundErrorMessage = nil
                } catch {
                    recordBackgroundError("Could not update active \(serviceType.rawValue) account", error)
                }
            } else {
                tgLog("[PE] sync[\(serviceType.rawValue)]: active consumer unchanged ('\(matchedAccount.displayName)')")
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
        if serviceType == .antigravity { return false }
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

    private func snapshotIdentityConflicts(_ snapshot: CodexConsumerSnapshot, with identity: ConsumerAccountIdentity?) -> Bool {
        identitiesConflict(snapshot.identity, identity)
    }

    private func shouldPoll(_ account: Account) -> Bool {
        if usesSubscribedRefresh(account) {
            return false
        }
        if account.planType == "consumer",
           account.serviceType != .antigravity,
           accountStore.activeConsumerAccountID(for: account.serviceType) != account.id {
            return false
        }
        return true
    }

    private func usesSubscribedRefresh(_ account: Account) -> Bool {
        account.serviceType == .codex && account.planType == "consumer"
    }

    private func shouldAutoRefresh(_ account: Account) -> Bool {
        if usesSubscribedRefresh(account) {
            return accountStore.activeConsumerAccountID(for: account.serviceType) == account.id
        }
        return shouldPoll(account)
    }

    private func refreshSubscribedAccounts(force: Bool) async {
        let subscribedAccounts = accountStore.accounts
            .filter(\.isEnabled)
            .filter { usesSubscribedRefresh($0) }
            .filter { accountStore.activeConsumerAccountID(for: $0.serviceType) == $0.id }

        guard !subscribedAccounts.isEmpty else {
            return
        }

        let dueAccounts = force ? subscribedAccounts : subscribedAccounts.filter { shouldRefresh($0) }
        guard !dueAccounts.isEmpty else {
            return
        }

        if !force,
           dueAccounts.allSatisfy({ accountStates[$0.id]?.lastAttemptAt == nil }),
           await isInitialSubscribedCodexBootstrapPending() {
            return
        }

        let attemptAt = Date()
        for account in dueAccounts {
            updateAccountState(for: account.id) { state in
                state.lastAttemptAt = attemptAt
                if force || state.connectionStatus != .live {
                    state.connectionStatus = .connecting
                }
            }
        }

        // Codex account switches only reliably converge after a fresh app-server
        // session. Re-bootstrap by reconnecting instead of reusing the session.
        await codexClient.restart()
    }

    private func isInitialSubscribedCodexBootstrapPending() async -> Bool {
        let liveState = await codexClient.currentState()
        return liveState.status != .live && liveState.lastUpdateAt == nil
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

        if let liveSnapshot = liveState.snapshot,
           snapshotIdentityConflicts(liveSnapshot, with: effectiveIdentity) {
            state.connectionStatus = .connecting
            state.errorMessage = nil
            if let existingSnapshot = state.snapshot {
                state.snapshot = existingSnapshot.markingStale(true)
                state.lastSuccessAt = existingSnapshot.timestamp
            }
            updatedStates[activeAccountID] = state
            accountStates = updatedStates
            await codexClient.restart()
            return
        } else if let liveSnapshot = liveState.snapshot {
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
