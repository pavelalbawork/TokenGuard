import SwiftUI

struct UsageWindowRow: View {
    let window: UsageWindow
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                Text(window.label ?? window.windowType.defaultLabel)
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(themeManager.currentTheme.textSecondary)

                Spacer()

                HStack(spacing: 6) {
                    if let resetDate = window.resetDate {
                        CountdownTimerText(resetDate: resetDate)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(themeManager.currentTheme.textSecondary.opacity(0.5))
                    }
                    
                    Text(valueText)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(valueColor)
                }
            }

            if window.limit != nil {
                UsageProgressBar(window: window)
            }
        }
    }

    private var valueColor: Color {
        let theme = themeManager.currentTheme
        switch window.usageStatus {
        case .critical: return theme.error
        case .warning: return theme.secondaryAccent
        case .normal: return theme.textPrimary
        }
    }

    private var valueText: String {
        if window.unit == .percent {
            let remaining = max(0, 100 - window.used)
            return "\(Int(remaining.rounded()))%"
        }

        if let limit = window.limit {
            let remaining = max(0, limit - window.used)
            if window.unit == .dollars {
                return "\(window.unit.symbol)\(remaining.formatted(.number.precision(.fractionLength(2)))) left"
            }
            let fmt = IntegerFormatStyle<Int>()
            return "\(fmt.format(Int(remaining)))/\(fmt.format(Int(limit)))\(window.unit.suffix)"
        }

        // No limit — just show used as fallback
        if window.unit == .dollars {
            return "\(window.unit.symbol)\(window.used.formatted(.number.precision(.fractionLength(2))))"
        }
        let fmt = IntegerFormatStyle<Int>()
        return "\(fmt.format(Int(window.used)))\(window.unit.suffix)"
    }
}
