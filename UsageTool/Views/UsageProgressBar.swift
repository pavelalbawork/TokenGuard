import SwiftUI

struct UsageProgressBar: View {
    let window: UsageWindow
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(themeManager.currentTheme.surfaceContainerHigh)
                
                Capsule()
                    .fill(color)
                    // Show REMAINING: invert percentUsed so bar shrinks as usage grows
                    .frame(width: max(0, min(1, 1.0 - (window.percentUsed ?? 0))) * geometry.size.width)
                    .shadow(color: color.opacity(0.6), radius: 4, x: 0, y: 0)
            }
        }
        .frame(height: 6) // Match Stitch .h-1.5 (6px)
    }

    private var color: Color {
        let theme = themeManager.currentTheme
        switch window.usageStatus {
        case .normal:
            return theme.tertiaryAccent
        case .warning:
            return theme.secondaryAccent
        case .critical:
            return theme.error
        }
    }
}
