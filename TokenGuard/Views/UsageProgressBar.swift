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
                    .fill(shapeStyle)
                    // Show REMAINING: invert percentUsed so bar shrinks as usage grows
                    .frame(width: max(0, min(1, 1.0 - (window.percentUsed ?? 0))) * geometry.size.width)
                    .shadow(color: (serviceType?.tintColor(for: themeManager.currentTheme) ?? themeManager.currentTheme.tertiaryAccent).opacity(0.6), radius: 4, x: 0, y: 0)
            }
        }
        .frame(height: 8)
    }

    private var shapeStyle: AnyShapeStyle {
        let theme = themeManager.currentTheme
        let baseGradient = serviceType?.tintGradient(for: theme) ?? LinearGradient(colors: [theme.tertiaryAccent, theme.tertiaryAccent], startPoint: .leading, endPoint: .trailing)
        let baseColor = serviceType?.tintColor(for: theme) ?? theme.tertiaryAccent
        
        switch window.usageStatus {
        case .normal:
            return theme.id == "luminous" ? AnyShapeStyle(baseGradient) : AnyShapeStyle(baseColor)
        case .warning:
            return theme.id == "luminous" ? AnyShapeStyle(baseGradient.opacity(0.8)) : AnyShapeStyle(baseColor.opacity(0.8))
        case .critical:
            return AnyShapeStyle(theme.error)
        }
    }
}
