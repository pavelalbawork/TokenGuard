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

                Text("Manage linked accounts and optional display names.")
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
    @State private var showDeleteConfirmation = false
    @State private var mutationError: String?

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

                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundStyle(theme.error.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ALIAS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.textSecondary)

                TextField("Enter Alias (Optional)", text: $alias)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .tint(theme.primaryAccent)
                    .padding(8)
                    .background(theme.isLight ? theme.surfaceContainer : theme.backgroundMain)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
                    .onChange(of: alias) { _, newValue in
                        updateAlias(newValue)
                    }

                if let mutationError {
                    Text(mutationError)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.error)
                }
            }
        }
        .padding(12)
        .background(theme.isLight ? theme.surfaceContainerHigh : theme.surfaceContainerHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
        .alert("Delete account?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the account and its local state.")
        }
        .onAppear {
            alias = account.alias ?? ""
        }
    }

    private func updateAlias(_ value: String) {
        var updated = account
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.alias = trimmed.isEmpty ? nil : trimmed

        do {
            try accountStore.update(updated)
            mutationError = nil
        } catch {
            mutationError = "Could not save alias: \(error.localizedDescription)"
        }
    }

    private func deleteAccount() {
        do {
            try pollingEngine.deleteAccount(account)
            mutationError = nil
        } catch {
            mutationError = "Could not delete account: \(error.localizedDescription)"
        }
    }
}
