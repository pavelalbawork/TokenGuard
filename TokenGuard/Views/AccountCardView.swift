import SwiftUI

struct AccountCardView: View {
    let account: Account
    let referenceDate: Date

    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let state = pollingEngine.accountStates[account.id]
        let theme = themeManager.currentTheme

        CardHoverContainer(theme: theme) {
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot = state?.snapshot {
                    VStack(spacing: 13) {
                        ForEach(sortedWindows(for: snapshot.windows)) { window in
                            UsageWindowRow(window: window, serviceType: account.serviceType)
                        }
                    }

                    if snapshot.isStale {
                        Label("Last updated \(ageString(for: snapshot.timestamp, now: referenceDate))", systemImage: "clock.badge.exclamationmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.secondaryAccent.opacity(0.9))
                    } else {
                        Text("Last updated \(ageString(for: snapshot.timestamp, now: referenceDate))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.textSecondary.opacity(theme.isLight ? 0.75 : 0.58))
                    }
                } else if let errorMessage = state?.errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(antigravityAwareError(errorMessage), systemImage: "exclamationmark.circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.error.opacity(0.9))

                        if account.serviceType == .antigravity {
                            Text("Uses the local Antigravity app state. Reopen Antigravity if authentication needs a refresh.")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(theme.textSecondary.opacity(theme.isLight ? 0.78 : 0.62))
                        }
                    }
                } else if isInactiveConsumerAccount {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Inactive saved account", systemImage: "pause.circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textSecondary.opacity(theme.isLight ? 0.82 : 0.78))

                        Text("Sign into this account in the local app or CLI to refresh it. The current live account is updated automatically.")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.textSecondary.opacity(theme.isLight ? 0.76 : 0.7))
                    }
                } else if state?.connectionStatus == .connecting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting to Codex\u{2026}")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading\u{2026}")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ageString(for date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private var isInactiveConsumerAccount: Bool {
        account.planType == "consumer" &&
        accountStore.activeConsumerAccountID(for: account.serviceType) != account.id
    }

    private func antigravityAwareError(_ message: String) -> String {
        guard account.serviceType == .antigravity else { return message }
        if message.contains("database not found") { return "Antigravity DB not found" }
        if message.contains("key file not found") { return "Antigravity key file missing" }
        if message.contains("unexpected format") { return "Unsupported key format" }
        if message.contains("provided credentials were rejected") { return "Antigravity sign-in needs refresh" }
        return message
    }

    private func sortedWindows(for windows: [UsageWindow]) -> [UsageWindow] {
        if account.serviceType == .codex || account.serviceType == .claude {
            return windows.sorted { a, b in
                if a.windowType == .weekly && b.windowType != .weekly { return true }
                if b.windowType == .weekly && a.windowType != .weekly { return false }
                let labelA = a.label ?? a.windowType.defaultLabel
                let labelB = b.label ?? b.windowType.defaultLabel
                return labelA < labelB
            }
        }
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
        let background = theme.isLight
            ? (isHovered ? theme.surfaceContainerHigh : theme.surfaceContainer)
            : theme.surfaceContainerHigh.opacity(isHovered ? 0.7 : 0.5)

        if theme.isLight {
            content
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHovered ? theme.primaryAccent.opacity(0.45) : theme.border.opacity(0.9), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                .onHover { hovering in
                    isHovered = hovering
                }
        } else {
            content
                .background(background)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHovered ? theme.primaryAccent.opacity(0.25) : theme.border, lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                .onHover { hovering in
                    isHovered = hovering
                }
        }
    }
}
