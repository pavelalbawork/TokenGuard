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
    @State private var warningMessage: String?
    @State private var mismatchConfirmed = false
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

                    if let warningMessage {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 10))
                            Text(warningMessage)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.orange.opacity(0.9))
                        }
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
                            Text(mismatchConfirmed ? "SAVE ANYWAY" : "SAVE ACCOUNT")
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
        .onChange(of: selectedProvider) { _, _ in
            mismatchConfirmed = false
            warningMessage = nil
            statusMessage = nil
        }
        .onChange(of: accountEmail) { _, _ in
            mismatchConfirmed = false
            warningMessage = nil
        }
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
                    .rotationEffect(.degrees(type.rotationAngle))
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
                let account = try await buildValidatedAccount(
                    email: normalizedEmail,
                    alias: normalizedAlias.isEmpty ? nil : normalizedAlias
                )

                if selectedProvider == .antigravity && !mismatchConfirmed {
                    if let warning = await antigravityMismatchWarning(enteredEmail: normalizedEmail) {
                        await MainActor.run {
                            warningMessage = warning
                            mismatchConfirmed = true
                            isSaving = false
                        }
                        return
                    }
                }

                try accountStore.add(account)
                await pollingEngine.refreshAll(force: true)
                await MainActor.run {
                    isSaving = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    statusMessage = validationErrorMessage(for: error)
                }
            }
        }
    }

    private func buildValidatedAccount(email: String, alias: String?) async throws -> Account {
        let normalizedEmail = normalizedIdentity(email)
        guard let normalizedEmail, !normalizedEmail.isEmpty else {
            throw AddAccountValidationError.missingEmail
        }

        let provider = provider(for: selectedProvider)
        let detectedIdentity = try await consumerIdentityIfAvailable(for: provider)

        // Antigravity stores the signed-in email in a protobuf blob that lags
        // behind account switches (it keeps showing the "primary" account even
        // after the user switches to another signed-in account). The only
        // freshly-updating identifier is `antigravity.profileUrl`, so we cannot
        // validate the entered email against the detected email here — the user
        // would be blocked from adding any non-primary account. Trust the user's
        // input instead and capture the current profileUrl for later matching.
        if selectedProvider != .antigravity,
           let detectedEmail = normalizedIdentity(detectedIdentity?.email),
           detectedEmail != normalizedEmail {
            throw AddAccountValidationError.identityMismatch(
                provider: selectedProvider.rawValue.capitalized,
                detectedEmail: detectedEmail,
                enteredEmail: normalizedEmail
            )
        }

        let credentialRef = "\(selectedProvider.rawValue)-\(UUID().uuidString)"
        var configuration: [String: String] = [
            Account.ConfigurationKey.planType: "consumer"
        ]

        let consumerEmail: String
        if selectedProvider == .antigravity {
            consumerEmail = normalizedEmail
        } else {
            consumerEmail = normalizedIdentity(detectedIdentity?.email) ?? normalizedEmail
        }
        configuration[Account.ConfigurationKey.consumerEmail] = consumerEmail
        if let externalID = normalizedIdentity(detectedIdentity?.externalID) {
            configuration[Account.ConfigurationKey.consumerExternalID] = externalID
        }
        if selectedProvider == .antigravity,
           let profileUrl = normalizedIdentity(detectedIdentity?.profileUrl) {
            configuration[Account.ConfigurationKey.antigravityProfileUrl] = profileUrl
        }

        let account = Account(
            name: normalizedEmail,
            alias: alias,
            serviceType: selectedProvider,
            credentialRef: credentialRef,
            configuration: configuration
        )

        guard try await provider.validateCredentials(account: account, credential: "") else {
            throw AddAccountValidationError.providerStateUnavailable(provider: selectedProvider.rawValue.capitalized)
        }

        return account
    }

    private func provider(for serviceType: ServiceType) -> any ServiceProvider {
        switch serviceType {
        case .claude:
            AnthropicProvider()
        case .codex:
            OpenAIProvider()
        case .gemini:
            GeminiCLIProvider()
        case .antigravity:
            AntigravityProvider()
        }
    }

    private func consumerIdentityIfAvailable(for provider: any ServiceProvider) async throws -> ConsumerAccountIdentity? {
        guard let detector = provider as? any ConsumerAccountDetecting else {
            return nil
        }
        return try await detector.currentConsumerIdentity()
    }

    private func validationErrorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return "Unable to verify local provider state. \(error.localizedDescription)"
    }

    private func antigravityMismatchWarning(enteredEmail: String) async -> String? {
        let provider = AntigravityProvider()
        guard let identity = try? await provider.currentConsumerIdentity() else {
            return nil
        }

        let entered = enteredEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if let detectedEmail = identity.email?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
           !detectedEmail.isEmpty {
            if detectedEmail != entered {
                return "Antigravity is currently signed into \(detectedEmail). Usage for \(enteredEmail) won't appear until you switch to this account in Antigravity."
            }
            return nil
        }

        // No email detected — likely an account switch; can't verify
        return "Could not verify the active Antigravity account. Usage for \(enteredEmail) won't appear until its credentials are captured (requires signing into this account in Antigravity)."
    }

    private func normalizedIdentity(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum AddAccountValidationError: LocalizedError {
    case missingEmail
    case identityMismatch(provider: String, detectedEmail: String, enteredEmail: String)
    case providerStateUnavailable(provider: String)

    var errorDescription: String? {
        switch self {
        case .missingEmail:
            return "Enter the email or identifier shown by the signed-in local provider."
        case let .identityMismatch(provider, detectedEmail, enteredEmail):
            return "\(provider) is signed into \(detectedEmail), not \(enteredEmail). Switch the local \(provider) session or enter the active account before saving."
        case let .providerStateUnavailable(provider):
            return "TokenGuard could not verify local \(provider) state on this Mac. Open the provider CLI/app, confirm you are signed in, then try again."
        }
    }
}
