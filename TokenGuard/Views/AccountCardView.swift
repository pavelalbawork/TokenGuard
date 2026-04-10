import SwiftUI

struct AccountCardView: View {
    let account: Account

    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        // Item 4: TimelineView auto-refreshes the "Updated X ago" label every 30s
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            let state = pollingEngine.accountStates[account.id]
            let theme = themeManager.currentTheme

            CardHoverContainer(theme: theme) {
                VStack(alignment: .leading, spacing: 14) {
                if let snapshot = state?.snapshot {
                    VStack(spacing: 14) {
                        ForEach(sortedWindows(for: snapshot.windows)) { window in
                            UsageWindowRow(window: window)
                        }
                    }

                    if snapshot.isStale {
                        // Item 5: softer stale icon
                        Label("Updated \(ageString(for: snapshot.timestamp, now: context.date))", systemImage: "clock.badge.exclamationmark")
                            .font(.system(size: 8, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(theme.secondaryAccent.opacity(0.8))
                    } else {
                        Text("Updated \(ageString(for: snapshot.timestamp, now: context.date))")
                            .font(.system(size: 8, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(theme.textSecondary.opacity(0.5))
                    }
                } else if let errorMessage = state?.errorMessage {
                    // Item 6 + 9: consistent font, Antigravity-aware copy
                    VStack(alignment: .leading, spacing: 6) {
                        Label(antigravityAwareError(errorMessage), systemImage: "exclamationmark.circle")
                            .font(.system(size: 9, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(theme.error.opacity(0.8))

                        if account.serviceType == .antigravity {
                            Text("Uses the local Antigravity app state. Reopen Antigravity if authentication needs a refresh.")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(theme.textSecondary.opacity(0.6))
                        }
                    }
                } else if isInactiveConsumerAccount {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Inactive saved account", systemImage: "pause.circle")
                            .font(.system(size: 9, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(theme.textSecondary.opacity(0.8))

                        Text("Sign into this account in the local app or CLI to refresh it. The current LIVE account is updated automatically.")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(theme.textSecondary.opacity(0.7))
                    }
                } else if state?.connectionStatus == .connecting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting to Codex\u{2026}")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.textSecondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading\u{2026}")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Item 4: accepts current time from TimelineView context so it stays live
    private func ageString(for date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private var isInactiveConsumerAccount: Bool {
        account.planType == "consumer" &&
        accountStore.activeConsumerAccountID(for: account.serviceType) != account.id
    }

    // Item 9: strip noisy path info from Antigravity DB errors
    private func antigravityAwareError(_ message: String) -> String {
        guard account.serviceType == .antigravity else { return message }
        if message.contains("database not found") { return "Antigravity DB not found" }
        if message.contains("key file not found") { return "Antigravity key file missing" }
        if message.contains("unexpected format") { return "Unsupported key format" }
        if message.contains("provided credentials were rejected") { return "Antigravity sign-in needs refresh" }
        return message
    }

    private func sortedWindows(for windows: [UsageWindow]) -> [UsageWindow] {
        if account.serviceType == .antigravity {
            let order: [String: Int] = [
                "Anthropic (Claude)": 0,
                "Gemini Pro": 1,
                "Gemini Flash": 2
            ]
            return windows.sorted { a, b in
                let indexA = order[a.label ?? ""] ?? 99
                let indexB = order[b.label ?? ""] ?? 99
                return indexA < indexB
            }
        }
        if account.serviceType == .gemini {
            let order: [String: Int] = [
                "PRO": 0,
                "FLASH": 1,
                "LITE": 2
            ]
            return windows.sorted { a, b in
                let indexA = order[a.label ?? ""] ?? 99
                let indexB = order[b.label ?? ""] ?? 99
                return indexA < indexB
            }
        }
        return windows
    }
}

struct CardHoverContainer<Content: View>: View {
    let theme: Theme
    @ViewBuilder let content: Content
    
    @State private var isHovered = false
    
    var body: some View {
        content
            .background(theme.isLight ? (isHovered ? theme.surfaceContainerHigh : theme.surfaceContainer) : theme.surfaceContainerHigh.opacity(isHovered ? 0.7 : 0.5))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? theme.primaryAccent.opacity(theme.isLight ? 0.4 : 0.25) : theme.border, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
