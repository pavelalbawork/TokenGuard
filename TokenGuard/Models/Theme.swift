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
    public static let vantage = Theme(
        id: "vantage",
        name: "Classic: Vantage",
        backgroundMain: Color(hex: "#0d0a16"),
        surface: Color(hex: "#0d0a16"),
        surfaceContainer: Color(hex: "#15111e"),
        surfaceContainerHigh: Color(hex: "#1d1927"),
        textPrimary: Color(hex: "#e7e0eb"),
        textSecondary: Color(hex: "#c9c4d0"),
        primaryAccent: Color(hex: "#e0b6ff"),
        secondaryAccent: Color(hex: "#cbc2db"),
        tertiaryAccent: Color(hex: "#4edea3"),
        border: Color(white: 1.0, opacity: 0.05),
        error: Color(hex: "#ffb4ab")
    )
    
    public static let luminous = Theme(
        id: "luminous",
        name: "Classic: Luminous",
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
        name: "Classic: Nordic Frost",
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
        name: "New: Obsidian Silver",
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
    
    public static let royalAmethyst = Theme(
        id: "royalAmethyst",
        name: "New: Royal Amethyst",
        backgroundMain: Color(hex: "#130b1c"),
        surface: Color(hex: "#130b1c"),
        surfaceContainer: Color(hex: "#1e112c"),
        surfaceContainerHigh: Color(hex: "#2c1941"),
        textPrimary: Color(hex: "#f8f4fc"),
        textSecondary: Color(hex: "#bda8d6"),
        primaryAccent: Color(hex: "#ffd700"),
        secondaryAccent: Color(hex: "#e6c200"),
        tertiaryAccent: Color(hex: "#ffdf33"),
        border: Color(white: 1.0, opacity: 0.05),
        error: Color(hex: "#ff4d4d")
    )
    
    public static let mintTerminal = Theme(
        id: "mintTerminal",
        name: "New: Mint Terminal",
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

    // MARK: - Light Themes (MacOS Native)
    
    public static let systemLight = Theme(
        id: "systemLight",
        name: "Light: System Default",
        isLight: true,
        backgroundMain: Color(hex: "#f5f5f7"),
        surface: Color(hex: "#ffffff"),
        surfaceContainer: Color(hex: "#f2f2f7"),
        surfaceContainerHigh: Color(hex: "#e5e5ea"),
        textPrimary: Color(hex: "#000000"),
        textSecondary: Color(hex: "#3c3c43"),
        primaryAccent: Color(hex: "#007aff"), // Apple Blue
        secondaryAccent: Color(hex: "#005f99"),
        tertiaryAccent: Color(hex: "#4b3fd4"),
        border: Color(hex: "#8e8e93"),
        error: Color(hex: "#ff3b30")
    )
    
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
    
    public static let all: [Theme] = [
        .vantage, .luminous, .nordicFrost, .obsidianSilver, .royalAmethyst, .mintTerminal,
        .systemLight, .minimalLight
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
