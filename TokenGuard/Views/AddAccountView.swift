import SwiftUI

struct InlineAddAccountView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager

    let onCancel: () -> Void
    let onComplete: () -> Void

    @State private var selectedProvider: ServiceType = .claude
    @State private var accountEmail = ""
    @State private var accountAlias = ""
    @State private var statusMessage: String?
    @State private var isSaving = false

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(spacing: 0) {
            // Header
            HStack {
                Text("ADD ACCOUNT")
                    .font(.system(size: 14, weight: .black))
                    .tracking(1.0)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.textSecondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // 1. Provider Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SERVICE PROVIDER")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(theme.textSecondary)
                        
                        // Custom Segmented Control equivalent
                        HStack(spacing: 8) {
                            ForEach(ServiceType.allCases, id: \.self) { type in
                                providerButton(for: type, theme: theme)
                            }
                        }
                    }

                    // 2. Account Information Input
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ACCOUNT EMAIL")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.0)
                                .foregroundStyle(theme.textSecondary)
                            
                            TextField("e.g. you@example.com", text: $accountEmail)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium))
                                .padding(10)
                                .background(theme.backgroundMain)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(theme.border, lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("ACCOUNT ALIAS")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.0)
                                .foregroundStyle(theme.textSecondary)
                            
                            TextField("e.g. Work, Personal (Optional)", text: $accountAlias)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .medium))
                                .padding(10)
                                .background(theme.backgroundMain)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(theme.border, lineWidth: 1)
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(theme.secondaryAccent)
                                .font(.system(size: 10))
                            Text("Relies on local provider state. Ensure the provider CLI/app is already installed and signed in.")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(theme.textSecondary.opacity(0.8))
                        }
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.error)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            // Footer Action
            HStack {
                Button(action: saveAccount) {
                    HStack {
                        if isSaving {
                            ProgressView().controlSize(.small).tint(theme.backgroundMain)
                        } else {
                            Text("SAVE ACCOUNT")
                                .tracking(1.5)
                        }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.backgroundMain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(canSubmit ? theme.primaryAccent : theme.surfaceContainerHigh)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(theme.backgroundMain)
            .border(width: 1, edges: [.top], color: theme.border)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private func providerButton(for type: ServiceType, theme: Theme) -> some View {
        let isSelected = selectedProvider == type
        Button {
            selectedProvider = type
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .font(.system(size: 16, weight: .light))
                Text(type.rawValue.capitalized)
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? type.tintColor(for: theme) : theme.textSecondary.opacity(0.5))
            .background(isSelected ? type.tintColor(for: theme).opacity(0.1) : (theme.isLight ? theme.surfaceContainer : theme.surfaceContainerHigh.opacity(0.3)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? type.tintColor(for: theme).opacity(0.5) : theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var canSubmit: Bool {
        !accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveAccount() {
        guard canSubmit else { return }
        isSaving = true
        statusMessage = nil

        let normalizedEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlias = accountAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let account = try await buildAccount(named: normalizedEmail, alias: normalizedAlias.isEmpty ? nil : normalizedAlias)
                try accountStore.add(account)
                await pollingEngine.refreshAll(force: true)
                await MainActor.run {
                    isSaving = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    let errorDesc = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    statusMessage = "Unable to verify local state. Ensure CLI is authenticated. (\(errorDesc))"
                }
            }
        }
    }

    private func buildAccount(named normalizedName: String, alias: String?) async throws -> Account {
        let credentialRef = "\(selectedProvider.rawValue)-\(UUID().uuidString)"
        var configuration: [String: String] = [:]

        if selectedProvider == .claude || selectedProvider == .codex || selectedProvider == .antigravity {
            configuration[Account.ConfigurationKey.planType] = "consumer"
        }

        let normalizedNameLower = normalizedName.lowercased()
        if normalizedNameLower.contains("@") && (selectedProvider == .codex || selectedProvider == .antigravity || selectedProvider == .claude) {
            configuration[Account.ConfigurationKey.consumerEmail] = normalizedNameLower
        }

        if selectedProvider == .antigravity,
           configuration[Account.ConfigurationKey.consumerEmail] == nil,
           let identity = try await AntigravityProvider().currentConsumerIdentity(),
           let email = identity.email {
            configuration[Account.ConfigurationKey.consumerEmail] = email
        }

        return Account(
            name: normalizedName,
            alias: alias,
            serviceType: selectedProvider,
            credentialRef: credentialRef,
            configuration: configuration
        )
    }
}
