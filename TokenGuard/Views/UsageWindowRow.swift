import SwiftUI

struct UsageWindowRow: View {
    let window: UsageWindow
    let serviceType: ServiceType?
    
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.currentTheme
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                Text(window.label ?? window.windowType.defaultLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textSecondary.opacity(theme.isLight ? 0.88 : 0.82))

                Spacer()

                HStack(spacing: 6) {
                    if let resetDate = window.resetDate {
                        CountdownTimerText(resetDate: resetDate)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textSecondary.opacity(theme.isLight ? 0.7 : 0.52))
                    }
                    
                    Text(valueText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(valueColor)
                }
            }

            if window.limit != nil {
                UsageProgressBar(window: window, serviceType: serviceType)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var valueColor: Color {
        themeManager.currentTheme.textPrimary
    }

    private var accessibilityLabel: String {
        let label = window.label ?? window.windowType.defaultLabel
        return "\(label), \(valueText)"
    }

    private var valueText: String {
        if window.unit == .percent {
            let remaining = max(0, 100 - window.used)
            return "\(Int(remaining.rounded()))% left"
        }

        if let limit = window.limit {
            let remaining = max(0, limit - window.used)
            if window.unit == .dollars {
                return "\(window.unit.symbol)\(remaining.formatted(.number.precision(.fractionLength(2)))) left"
            }
            let fmt = IntegerFormatStyle<Int>()
            return "\(fmt.format(Int(remaining)))/\(fmt.format(Int(limit)))\(window.unit.suffix) left"
        }

        // No limit — just show used as fallback
        if window.unit == .dollars {
            return "\(window.unit.symbol)\(window.used.formatted(.number.precision(.fractionLength(2))))"
        }
        let fmt = IntegerFormatStyle<Int>()
        return "\(fmt.format(Int(window.used)))\(window.unit.suffix)"
    }
}
