import SwiftUI

public struct Theme: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isLight: Bool
    
    // Backgrounds
    public let backgroundMain: Color
    public let surface: Color
    public let surfaceContainer: Color
    public let surfaceContainerHigh: Color
    
    // Texts
    public let textPrimary: Color
    public let textSecondary: Color
    
    // Accents
    public let primaryAccent: Color
    public let secondaryAccent: Color
    public let tertiaryAccent: Color
    
    // Functional
    public let border: Color
    public let error: Color
    
    public init(id: String, name: String, isLight: Bool = false, backgroundMain: Color, surface: Color, surfaceContainer: Color, surfaceContainerHigh: Color, textPrimary: Color, textSecondary: Color, primaryAccent: Color, secondaryAccent: Color, tertiaryAccent: Color, border: Color, error: Color) {
        self.id = id
        self.name = name
        self.isLight = isLight
        self.backgroundMain = backgroundMain
        self.surface = surface
        self.surfaceContainer = surfaceContainer
        self.surfaceContainerHigh = surfaceContainerHigh
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.primaryAccent = primaryAccent
        self.secondaryAccent = secondaryAccent
        self.tertiaryAccent = tertiaryAccent
        self.border = border
        self.error = error
    }
}

extension Theme {
    public static let luminous = Theme(
        id: "luminous",
        name: "Dark: Luminous",
        backgroundMain: Color(hex: "#030c14"),
        surface: Color(hex: "#030c14"),
        surfaceContainer: Color(hex: "#0a192f"),
        surfaceContainerHigh: Color(hex: "#112240"),
        textPrimary: Color(hex: "#f1f5f9"),
        textSecondary: Color(hex: "#94a3b8"),
        primaryAccent: Color(hex: "#f97316"),
        secondaryAccent: Color(hex: "#94a3b8"),
        tertiaryAccent: Color(hex: "#f97316"),
        border: Color(white: 1.0, opacity: 0.05),
        error: Color(hex: "#ef4444")
    )
    
    public static let nordicFrost = Theme(
        id: "nordicFrost",
        name: "Dark: Nordic Frost",
        backgroundMain: Color(hex: "#080e1a"),
        surface: Color(hex: "#080e1a"),
        surfaceContainer: Color(hex: "#0f172a"),
        surfaceContainerHigh: Color(hex: "#1e293b"),
        textPrimary: Color(hex: "#f0f9ff"),
        textSecondary: Color(hex: "#bae6fd"),
        primaryAccent: Color(hex: "#00d4ff"),
        secondaryAccent: Color(hex: "#7dd3fc"),
        tertiaryAccent: Color(hex: "#38bdf8"),
        border: Color(white: 1.0, opacity: 0.05),
        error: Color(hex: "#ff5252")
    )

    public static let obsidianSilver = Theme(
        id: "obsidianSilver",
        name: "Dark: Obsidian Silver",
        backgroundMain: Color(hex: "#0a0a0a"),
        surface: Color(hex: "#0a0a0a"),
        surfaceContainer: Color(hex: "#141414"),
        surfaceContainerHigh: Color(hex: "#1f1f1f"),
        textPrimary: Color(hex: "#ffffff"),
        textSecondary: Color(hex: "#a3a3a3"),
        primaryAccent: Color(hex: "#e5e5e5"),
        secondaryAccent: Color(hex: "#d4d4d4"),
        tertiaryAccent: Color(hex: "#ffffff"),
        border: Color(white: 1.0, opacity: 0.08),
        error: Color(hex: "#ef4444")
    )
    
    public static let mintTerminal = Theme(
        id: "mintTerminal",
        name: "Dark: Mint Terminal",
        backgroundMain: Color(hex: "#18181b"),
        surface: Color(hex: "#18181b"),
        surfaceContainer: Color(hex: "#27272a"),
        surfaceContainerHigh: Color(hex: "#3f3f46"),
        textPrimary: Color(hex: "#f4f4f5"),
        textSecondary: Color(hex: "#a1a1aa"),
        primaryAccent: Color(hex: "#50b86a"), // Softer Mint Green
        secondaryAccent: Color(hex: "#8ccfa0"), // Lighter Softer Mint
        tertiaryAccent: Color(hex: "#398a4e"), // Darker Mint
        border: Color(white: 1.0, opacity: 0.08),
        error: Color(hex: "#f87171")
    )

    // MARK: - Light Themes
    
    public static let minimalLight = Theme(
        id: "minimalLight",
        name: "Light: Clean Minimal",
        isLight: true,
        backgroundMain: Color(hex: "#ffffff"),
        surface: Color(hex: "#ffffff"),
        surfaceContainer: Color(hex: "#f9f9f9"),
        surfaceContainerHigh: Color(hex: "#f0f0f0"),
        textPrimary: Color(hex: "#111111"),
        textSecondary: Color(hex: "#3f3f46"),
        primaryAccent: Color(hex: "#000000"),
        secondaryAccent: Color(hex: "#333333"),
        tertiaryAccent: Color(hex: "#52525b"),
        border: Color(hex: "#b8b8b8"),
        error: Color(hex: "#d93025")
    )
    
    public static let burgundyLight = Theme(
        id: "burgundyLight",
        name: "Light: Burgundy Minimal",
        isLight: true,
        backgroundMain: Color(hex: "#b8b2b4"),     // Very dark gray for a light theme
        surface: Color(hex: "#cfc9cb"),            // Elevated lighter gray
        surfaceContainer: Color(hex: "#a6a0a2"),   // Deep inset background
        surfaceContainerHigh: Color(hex: "#969092"),
        textPrimary: Color(hex: "#140c0d"),        // Near black
        textSecondary: Color(hex: "#3d2d31"),      // Extremely dark grey/brown
        primaryAccent: Color(hex: "#800020"),      // Burgundy
        secondaryAccent: Color(hex: "#b30030"),    // Lighter burgundy
        tertiaryAccent: Color(hex: "#4d0013"),     // Darker burgundy
        border: Color(hex: "#8a8386"),
        error: Color(hex: "#b91c1c")
    )
    
    public static let all: [Theme] = [
        .luminous, .nordicFrost, .obsidianSilver, .mintTerminal,
        .minimalLight, .burgundyLight
    ]
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
