import SwiftUI

public struct Theme: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let tagline: String
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
    public let quaternaryAccent: Color
    
    // Functional
    public let border: Color
    public let error: Color
    
    public init(id: String, name: String, tagline: String, isLight: Bool = false, backgroundMain: Color, surface: Color, surfaceContainer: Color, surfaceContainerHigh: Color, textPrimary: Color, textSecondary: Color, primaryAccent: Color, secondaryAccent: Color, tertiaryAccent: Color, quaternaryAccent: Color? = nil, border: Color, error: Color) {
        self.id = id
        self.name = name
        self.tagline = tagline
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
        self.quaternaryAccent = quaternaryAccent ?? primaryAccent
        self.border = border
        self.error = error
    }
}

extension Theme {
    public static let luminous = Theme(
        id: "luminous",
        name: "Luminous",
        tagline: "AIReady boardroom",
        backgroundMain: Color(hex: "#0a0f1a"),
        surface: Color(hex: "#0a0f1a"),
        surfaceContainer: Color(hex: "#0d1220"),
        surfaceContainerHigh: Color(hex: "#1a2133"),
        textPrimary: Color(hex: "#ffffff"),
        textSecondary: Color(hex: "#34d6ff"),   // AIReady Teal — replaces grey
        primaryAccent: Color(hex: "#34d6ff"),
        secondaryAccent: Color(hex: "#ff6b2c"),
        tertiaryAccent: Color(hex: "#ff9a60"),
        quaternaryAccent: Color(hex: "#d94010"),
        border: Color(white: 1.0, opacity: 0.10),
        error: Color(hex: "#ff4d4d")
    )
    
    public static let nordicFrost = Theme(
        id: "nordicFrost",
        name: "Nordic Frost",
        tagline: "Cool blue dark",
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
        name: "Obsidian Silver",
        tagline: "Pure high contrast",
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
        name: "Mint Terminal",
        tagline: "Hacker green",
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
        name: "Clean Minimal",
        tagline: "Bright monochrome",
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

    
    public static let paper = Theme(
        id: "paper",
        name: "Paper",
        tagline: "Warm light · ink accent",
        isLight: true,
        backgroundMain: Color(hex: "#f4efe6"),
        surface: Color(hex: "#fbf7ee"),
        surfaceContainer: Color(hex: "#fbf7ee"),
        surfaceContainerHigh: Color(hex: "#f0e9d8"),
        textPrimary: Color(hex: "#17140f"),
        textSecondary: Color(hex: "#5e574a"),
        primaryAccent: Color(hex: "#c85a2b"),
        secondaryAccent: Color(hex: "#e07340"),
        tertiaryAccent: Color(hex: "#2f6ea8"),
        quaternaryAccent: Color(hex: "#3e8a52"),
        border: Color(red: 20/255.0, green: 16/255.0, blue: 10/255.0, opacity: 0.14),
        error: Color(hex: "#a8322b")
    )
    
    public static let all: [Theme] = [
        .nordicFrost, .luminous, .obsidianSilver, .mintTerminal,
        .minimalLight, .paper
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
