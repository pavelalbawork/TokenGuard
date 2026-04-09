import SwiftUI

struct AccountEditScreen: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("ACCOUNTS")
                    .font(.system(size: 14, weight: .black))
                    .tracking(1.0)
                    .foregroundStyle(theme.textPrimary)

                Text("Manage your linked API accounts.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 16)

            // Accounts List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(accountStore.accounts) { account in
                        AccountEditRow(account: account, theme: theme)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .padding(.top, 16)
    }
}

struct AccountEditRow: View {
    let account: Account
    let theme: Theme
    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine

    @State private var alias: String = ""
    @State private var isDeleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: account.serviceType.iconName)
                    .rotationEffect(.degrees(account.serviceType.rotationAngle))
                    .foregroundStyle(account.serviceType.tintColor(for: theme))
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.serviceType.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                    Text(account.consumerEmail ?? account.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                }
                Spacer()

                if isDeleting {
                    Button(action: {
                        try? pollingEngine.deleteAccount(account)
                    }) {
                        Text("Delete")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(theme.error.opacity(0.8))
                            .foregroundStyle(theme.backgroundMain)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    Button(action: { isDeleting = false }) {
                        Text("Cancel")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { isDeleting = true }) {
                        Image(systemName: "trash")
                            .foregroundStyle(theme.error.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ALIAS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.textSecondary)

                TextField("Enter Alias (Optional)", text: $alias)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(8)
                    .background(theme.isLight ? theme.surfaceContainer : theme.backgroundMain)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
                    .onChange(of: alias) { _, newValue in
                        var updated = account
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.alias = trimmed.isEmpty ? nil : trimmed
                        try? accountStore.update(updated)
                    }
            }
        }
        .padding(12)
        .background(theme.isLight ? theme.surfaceContainerHigh : theme.surfaceContainerHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
        .onAppear {
            alias = account.alias ?? ""
        }
    }
}