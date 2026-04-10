import SwiftUI

struct UsageProgressBar: View {
    let window: UsageWindow
    let serviceType: ServiceType? // Pass the service down
    
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
        .frame(height: 8)
    }

    private var color: Color {
        let theme = themeManager.currentTheme
        let baseColor = serviceType?.tintColor(for: theme) ?? theme.tertiaryAccent
        
        switch window.usageStatus {
        case .normal:
            return baseColor
        case .warning:
            return baseColor.opacity(0.8) // Keep provider color but tweak opacity, or use secondaryAccent if we strictly want orange warnings. Let's keep provider mapping distinct for pastel.
        case .critical:
            return theme.error
        }
    }
}
