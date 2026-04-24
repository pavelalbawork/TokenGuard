import SwiftUI

struct ServiceSectionView: View {
    let serviceType: ServiceType
    let accounts: [Account]
    let referenceDate: Date

    @Environment(AccountStore.self) private var accountStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(UsagePollingEngine.self) private var pollingEngine

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: 10) {
            // ── Section Header ──────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: serviceType.iconName)
                    .font(.system(size: 14, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .rotationEffect(.degrees(serviceType.rotationAngle))
                    .foregroundStyle(theme.id == "luminous" ? theme.textPrimary : serviceType.tintColor(for: theme))

                Text(serviceType.rawValue.capitalized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if accounts.count == 1, let account = accounts.first,
                   let state = pollingEngine.accountStates[account.id],
                   let status = displayStatus(for: account, state: state) {
                    statusBadge(status, theme: theme, serviceTint: serviceType.tintColor(for: theme))
                }

                Spacer()

                // Single-account email badge
                if accounts.count == 1, let account = accounts.first {
                    accountBadge(account: account, theme: theme)
                }
            }

            // ── Account Cards ───────────────────────────────────────────
            ForEach(accounts) { account in
                VStack(alignment: .leading, spacing: 5) {
                    // Show per-account header when multiple accounts exist
                    if accounts.count > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.square.fill")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundStyle(theme.id == "luminous" ? theme.primaryAccent : serviceType.tintColor(for: theme))

                            Text(account.displayName)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            if let state = pollingEngine.accountStates[account.id],
                               let status = displayStatus(for: account, state: state) {
                                statusBadge(status, theme: theme, serviceTint: serviceType.tintColor(for: theme))
                            }

                            Spacer()
                        }
                    }

                    accountCard(account: account, theme: theme)
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func accountCard(account: Account, theme: Theme) -> some View {
        AccountCardView(account: account, referenceDate: referenceDate)
    }

    @ViewBuilder
    private func accountBadge(account: Account, theme: Theme) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.crop.square.fill")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.id == "luminous" ? theme.primaryAccent : serviceType.tintColor(for: theme))

            Text(account.displayName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(theme.isLight ? theme.surfaceContainer : theme.surfaceContainerHigh.opacity(0.3))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border, lineWidth: 1))
        .accessibilityLabel("\(account.displayName) account")
    }

    @ViewBuilder
    private func statusBadge(_ status: AccountDisplayStatus, theme: Theme, serviceTint: Color) -> some View {
        Text(status.label)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(statusColor(for: status, theme: theme, serviceTint: serviceTint).opacity(0.12), in: .rect(cornerRadius: 3))
            .foregroundStyle(statusColor(for: status, theme: theme, serviceTint: serviceTint))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(status.accessibilityLabel)
    }

    private func displayStatus(for account: Account, state: UsagePollingEngine.AccountRefreshState) -> AccountDisplayStatus? {
        if state.connectionStatus == .connecting {
            return .reconnecting
        }

        if let snapshot = state.snapshot {
            if snapshot.isStale || state.errorMessage != nil {
                return .stale
            }

            if account.planType == "consumer",
               activeConsumerAccountID(for: account) != account.id {
                return nil
            }

            return .live
        }

        if state.errorMessage != nil {
            return .error
        }

        return nil
    }

    private func activeConsumerAccountID(for account: Account) -> UUID? {
        accountStore.activeConsumerAccountID(for: account.serviceType)
    }

    private func statusColor(for status: AccountDisplayStatus, theme: Theme, serviceTint: Color) -> Color {
        switch status {
        case .live:
            return theme.id == "luminous" ? theme.primaryAccent : serviceTint
        case .stale, .reconnecting:
            return theme.textSecondary
        case .error:
            return theme.error
        }
    }

    private enum AccountDisplayStatus {
        case live
        case stale
        case error
        case reconnecting

        var label: String {
            switch self {
            case .live:
                return "LIVE"
            case .stale:
                return "STALE"
            case .error:
                return "ERROR"
            case .reconnecting:
                return "RECONNECTING"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .live:
                return "Live"
            case .stale:
                return "Stale"
            case .error:
                return "Error"
            case .reconnecting:
                return "Reconnecting"
            }
        }
    }
}
