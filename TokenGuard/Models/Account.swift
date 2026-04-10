import Foundation

enum ServiceType: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case antigravity

    var iconName: String {
        switch self {
        case .claude: return "asterisk"
        case .codex: return "terminal"
        case .gemini: return "sparkles"
        case .antigravity: return "point.3.filled.connected.trianglepath.dotted"
        }
    }
}

import SwiftUI

extension ServiceType {
    func tintColor(for theme: Theme) -> Color {
        switch self {
        case .claude: return theme.primaryAccent
        case .codex: return theme.primaryAccent
        case .gemini: return theme.primaryAccent
        case .antigravity: return theme.primaryAccent
        }
    }

    var rotationAngle: Double {
        self == .antigravity ? 180 : 0
    }
}

struct Account: Identifiable, Codable, Hashable, Sendable {
    enum ConfigurationKey {
        static let planType = "planType"
        static let consumerEmail = "consumerEmail"
        static let consumerExternalID = "consumerExternalID"
        static let anthropicOrganizationID = "anthropicOrganizationID"
        static let rolling5hUsed = "rolling5hUsed"
        static let rolling5hLimit = "rolling5hLimit"
        static let weeklyUsed = "weeklyUsed"
        static let weeklyLimit = "weeklyLimit"
        static let weeklyResetWeekday = "weeklyResetWeekday"
        static let monthlyUsed = "monthlyUsed"
        static let monthlyLimit = "monthlyLimit"
        static let dailyUsed = "dailyUsed"
        static let dailyLimit = "dailyLimit"
        static let openAIOrganizationID = "openAIOrganizationID"
        static let openAIMonthlyBudgetUSD = "openAIMonthlyBudgetUSD"
        static let openAITokenLimit = "openAITokenLimit"
        static let googleProjectID = "googleProjectID"
        static let googleClientID = "googleClientID"
        static let googleRedirectURI = "googleRedirectURI"
        static let googleOAuthScopes = "googleOAuthScopes"
        static let googleRequestMetricType = "googleRequestMetricType"
        static let googleTokenMetricType = "googleTokenMetricType"
        static let googleRequestLimit = "googleRequestLimit"
        static let googleTokenLimit = "googleTokenLimit"
        static let usageLimit = "usageLimit"
        static let resetDayOfMonth = "resetDayOfMonth"
        static let resetHourUTC = "resetHourUTC"
        static let antigravityBaseURL = "antigravityBaseURL"
    }

    let id: UUID
    var name: String
    var alias: String?
    var serviceType: ServiceType
    var credentialRef: String
    var isEnabled: Bool
    var configuration: [String: String]

    init(
        id: UUID = UUID(),
        name: String,
        alias: String? = nil,
        serviceType: ServiceType,
        credentialRef: String,
        isEnabled: Bool = true,
        configuration: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.alias = alias
        self.serviceType = serviceType
        self.credentialRef = credentialRef
        self.isEnabled = isEnabled
        self.configuration = configuration
    }

    var displayName: String {
        alias?.isEmpty == false ? alias! : name
    }

    func configurationValue(for key: String) -> String? {
        configuration[key]
    }

    func configurationDouble(for key: String) -> Double? {
        configurationValue(for: key).flatMap(Double.init)
    }

    func configurationInt(for key: String) -> Int? {
        configurationValue(for: key).flatMap(Int.init)
    }

    var planType: String? {
        configurationValue(for: ConfigurationKey.planType)?.lowercased()
    }

    var consumerEmail: String? {
        normalizedConsumerIdentity(configurationValue(for: ConfigurationKey.consumerEmail))
            ?? normalizedConsumerIdentity(name.contains("@") ? name : nil)
    }

    var consumerExternalID: String? {
        normalizedConsumerIdentity(configurationValue(for: ConfigurationKey.consumerExternalID))
    }

    func matchingConsumerIdentityScore(_ identity: ConsumerAccountIdentity) -> Int? {
        if let externalID = consumerExternalID,
           let liveExternalID = identity.externalID,
           externalID == normalizedConsumerIdentity(liveExternalID) {
            return 2
        }

        if let email = consumerEmail,
           let liveEmail = identity.email,
           email == normalizedConsumerIdentity(liveEmail) {
            return 1
        }

        return nil
    }

    func withStoredConsumerIdentity(_ identity: ConsumerAccountIdentity) -> Account {
        var updated = self

        if configuration[ConfigurationKey.consumerEmail] == nil,
           let email = normalizedConsumerIdentity(identity.email) {
            updated.configuration[ConfigurationKey.consumerEmail] = email
        }

        if configuration[ConfigurationKey.consumerExternalID] == nil,
           let externalID = normalizedConsumerIdentity(identity.externalID) {
            updated.configuration[ConfigurationKey.consumerExternalID] = externalID
        }

        return updated
    }

    private func normalizedConsumerIdentity(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
