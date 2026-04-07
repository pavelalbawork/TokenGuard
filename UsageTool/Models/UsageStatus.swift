import Foundation

enum UsageStatus: String, Codable, Sendable {
    case normal
    case warning
    case critical
}

extension UsageWindow {
    var percentUsed: Double? {
        guard let limit, limit > 0 else { return nil }
        return min(max(used / limit, 0), 1)
    }

    var usageStatus: UsageStatus {
        guard let percentUsed else { return .normal }
        switch percentUsed {
        case 0.95...:
            return .critical
        case 0.75...:
            return .warning
        default:
            return .normal
        }
    }

    var timeUntilReset: TimeInterval? {
        resetDate?.timeIntervalSinceNow
    }
}

extension UsageSnapshot {
    var usageStatus: UsageStatus {
        windows.worstUsageStatus
    }

    var primaryWindow: UsageWindow? {
        windows.first
    }
}

extension Sequence where Element == UsageWindow {
    var worstUsageStatus: UsageStatus {
        reduce(.normal) { current, window in
            switch (current, window.usageStatus) {
            case (.critical, _), (_, .critical):
                .critical
            case (.warning, _), (_, .warning):
                .warning
            default:
                .normal
            }
        }
    }
}
