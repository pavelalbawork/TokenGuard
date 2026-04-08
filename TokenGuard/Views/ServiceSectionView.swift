import SwiftUI

struct ServiceSectionView: View {
    let serviceType: ServiceType
    let accounts: [Account]

    @State private var accountToDelete: Account?
    @State private var deleteErrorMessage: String?
    @Environment(AccountStore.self) private var accountStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(UsagePollingEngine.self) private var pollingEngine

    var body: some View {
        let activeConsumerAccountId = accountStore.activeConsumerAccountID(for: serviceType)
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: 12) {
            // ── Section Header ──────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: serviceType.iconName)
                    .font(.system(size: 14, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(serviceType.tintColor(for: theme))

                Text(serviceType.rawValue.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(2.0)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                // Tier / LIVE badges for single-account case
                if accounts.count == 1, let account = accounts.first {
                    let state = pollingEngine.accountStates[account.id]
                    if let tier = state?.snapshot?.tier {
                        Text(tier)
                            .font(.system(size: 8, weight: .bold))
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(theme.primaryAccent.opacity(0.1), in: .rect(cornerRadius: 3))
                            .foregroundStyle(theme.primaryAccent)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    if activeConsumerAccountId == account.id {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(serviceType.tintColor(for: theme).opacity(0.12), in: .rect(cornerRadius: 3))
                            .foregroundStyle(serviceType.tintColor(for: theme))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }

                Spacer()

                // Single-account email badge
                if accounts.count == 1, let account = accounts.first {
                    accountBadge(account: account, activeId: activeConsumerAccountId, theme: theme)
                }
            }

            // ── Account Cards ───────────────────────────────────────────
            ForEach(accounts) { account in
                VStack(alignment: .leading, spacing: 6) {
                    // Show per-account header when multiple accounts exist
                    if accounts.count > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.square.fill")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundStyle(serviceType.tintColor(for: theme))

                            Text(account.name.uppercased())
                                .font(.system(size: 8, weight: .black))
                                .tracking(0.5)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            if activeConsumerAccountId == account.id {
                                Text("LIVE")
                                    .font(.system(size: 7, weight: .bold))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(serviceType.tintColor(for: theme).opacity(0.15), in: .rect(cornerRadius: 2))
                                    .foregroundStyle(serviceType.tintColor(for: theme))
                            }

                            Spacer()
                        }
                    }

                    accountCard(account: account, isLive: activeConsumerAccountId == account.id, theme: theme)
                }
            }

            if let accountToDelete {
                deleteConfirmation(account: accountToDelete, theme: theme)
            }

            if let deleteErrorMessage {
                Text(deleteErrorMessage)
                    .font(.system(size: 8, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.error.opacity(0.85))
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func accountCard(account: Account, isLive: Bool, theme: Theme) -> some View {
        AccountCardView(account: account)
            .overlay(alignment: .topTrailing) {
                deleteButton(for: account, theme: theme)
                    .offset(x: 6, y: -6)
            }
    }

    @ViewBuilder
    private func accountBadge(account: Account, activeId: UUID?, theme: Theme) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "person.crop.square.fill")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(serviceType.tintColor(for: theme))

            Text(account.name.uppercased())
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(theme.surfaceContainerHigh.opacity(0.3))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func deleteButton(for account: Account, theme: Theme) -> some View {
        HoverableDeleteButton(theme: theme) {
            deleteErrorMessage = nil
            accountToDelete = account
        }
    }

    @ViewBuilder
    private func deleteConfirmation(account: Account, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remove \(account.name)?")
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(theme.textPrimary)

            Text("This removes the saved account and its last known state.")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 8) {
                Button("Cancel") {
                    accountToDelete = nil
                }
                .buttonStyle(.bordered)

                Button("Delete", role: .destructive) {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    Task {
                        do {
                            try pollingEngine.deleteAccount(account)
                            accountToDelete = nil
                        } catch {
                            deleteErrorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceContainerHigh.opacity(0.45))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func connectionBadge(_ status: CodexConnectionStatus, theme: Theme) -> some View {
        Text(connectionLabel(for: status))
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(connectionColor(for: status, theme: theme).opacity(0.12), in: .rect(cornerRadius: 3))
            .foregroundStyle(connectionColor(for: status, theme: theme))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func connectionLabel(for status: CodexConnectionStatus) -> String {
        switch status {
        case .live:
            return "LIVE"
        case .staleFallback:
            return "STALE"
        case .connecting:
            return "RECONNECTING"
        case .error:
            return "ERROR"
        }
    }

    private func connectionColor(for status: CodexConnectionStatus, theme: Theme) -> Color {
        switch status {
        case .live:
            return serviceType.tintColor(for: theme)
        case .staleFallback, .connecting:
            return theme.secondaryAccent
        case .error:
            return theme.error
        }
    }
}

struct HoverableDeleteButton: View {
    let theme: Theme
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .symbolRenderingMode(.palette)
                .foregroundStyle(theme.backgroundMain, isHovered ? theme.error : theme.textSecondary.opacity(0.4))
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
