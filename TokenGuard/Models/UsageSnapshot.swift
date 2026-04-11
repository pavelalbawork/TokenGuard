import Foundation

enum WindowType: String, Codable, Sendable {
    case rolling5h
    case weekly
    case monthly
    case daily

    var shortLabel: String {
        switch self {
        case .rolling5h:
            return "5h"
        case .weekly:
            return "Wk"
        case .monthly:
            return "Mo"
        case .daily:
            return "Da"
        }
    }

    var defaultLabel: String {
        switch self {
        case .rolling5h:
            return "5h window"
        case .weekly:
            return "Weekly cap"
        case .monthly:
            return "Monthly budget"
        case .daily:
            return "Daily quota"
        }
    }
}

enum UsageUnit: String, Codable, Sendable {
    case percent
    case tokens
    case messages
    case dollars
    case credits
    case requests

    var symbol: String {
        switch self {
        case .percent:
            return ""
        case .dollars:
            return "$"
        default:
            return ""
        }
    }

    var suffix: String {
        switch self {
        case .percent:
            return "%"
        case .tokens:
            return " tokens"
        case .messages:
            return " messages"
        case .dollars:
            return ""
        case .credits:
            return " credits"
        case .requests:
            return " requests"
        }
    }
}

struct UsageWindow: Codable, Hashable, Sendable, Identifiable {
    let windowType: WindowType
    let used: Double
    let limit: Double?
    let unit: UsageUnit
    let resetDate: Date?
    let label: String?

    var id: String {
        [windowType.rawValue, label ?? "", unit.rawValue].joined(separator: ":")
    }

    init(
        windowType: WindowType,
        used: Double,
        limit: Double?,
        unit: UsageUnit,
        resetDate: Date?,
        label: String? = nil
    ) {
        self.windowType = windowType
        self.used = used
        self.limit = limit
        self.unit = unit
        self.resetDate = resetDate
        self.label = label
    }

    func resettingIfNeeded(
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> UsageWindow {
        guard let resetDate, resetDate <= now else {
            return self
        }

        return UsageWindow(
            windowType: windowType,
            used: 0,
            limit: limit,
            unit: unit,
            resetDate: nextResetDate(after: now, previousResetDate: resetDate, calendar: calendar),
            label: label
        )
    }

    private func nextResetDate(
        after now: Date,
        previousResetDate: Date,
        calendar: Calendar
    ) -> Date? {
        switch windowType {
        case .rolling5h:
            return advancing(previousResetDate, after: now, by: 5 * 60 * 60)
        case .daily:
            return advancing(previousResetDate, after: now, by: 24 * 60 * 60)
        case .weekly:
            return advancing(previousResetDate, after: now, by: 7 * 24 * 60 * 60)
        case .monthly:
            var next = previousResetDate
            while next <= now {
                guard let advanced = calendar.date(byAdding: .month, value: 1, to: next) else {
                    return nil
                }
                next = advanced
            }
            return next
        }
    }

    private func advancing(_ date: Date, after now: Date, by interval: TimeInterval) -> Date {
        var next = date
        while next <= now {
            next = next.addingTimeInterval(interval)
        }
        return next
    }
}

struct UsageBreakdown: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let label: String
    let used: Double
    let limit: Double?
    let unit: UsageUnit

    init(id: UUID = UUID(), label: String, used: Double, limit: Double? = nil, unit: UsageUnit) {
        self.id = id
        self.label = label
        self.used = used
        self.limit = limit
        self.unit = unit
    }
}

struct UsageSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let accountId: UUID
    let timestamp: Date
    let windows: [UsageWindow]
    let tier: String?
    let breakdown: [UsageBreakdown]?
    let isStale: Bool

    init(
        id: UUID = UUID(),
        accountId: UUID,
        timestamp: Date = Date(),
        windows: [UsageWindow],
        tier: String? = nil,
        breakdown: [UsageBreakdown]? = nil,
        isStale: Bool = false
    ) {
        self.id = id
        self.accountId = accountId
        self.timestamp = timestamp
        self.windows = windows
        self.tier = tier
        self.breakdown = breakdown
        self.isStale = isStale
    }

    func markingStale(_ stale: Bool) -> UsageSnapshot {
        UsageSnapshot(
            id: id,
            accountId: accountId,
            timestamp: timestamp,
            windows: windows,
            tier: tier,
            breakdown: breakdown,
            isStale: stale
        )
    }

    func resettingExpiredWindows(
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> UsageSnapshot {
        let updatedWindows = windows.map { $0.resettingIfNeeded(now: now, calendar: calendar) }
        guard updatedWindows != windows else {
            return self
        }

        return UsageSnapshot(
            id: id,
            accountId: accountId,
            timestamp: timestamp,
            windows: updatedWindows,
            tier: tier,
            breakdown: breakdown,
            isStale: isStale
        )
    }
}
