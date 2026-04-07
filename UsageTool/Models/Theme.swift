import SwiftUI

public struct Theme: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    
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
    
    public init(id: String, name: String, backgroundMain: Color, surface: Color, surfaceContainer: Color, surfaceContainerHigh: Color, textPrimary: Color, textSecondary: Color, primaryAccent: Color, secondaryAccent: Color, tertiaryAccent: Color, border: Color, error: Color) {
        self.id = id
        self.name = name
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
        name: "Vantage Tracker",
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
    
    public static let cyberpunk = Theme(
        id: "cyberpunk",
        name: "Cyberpunk",
        backgroundMain: Color(hex: "#0e0e0e"),
        surface: Color(hex: "#0e0e0e"),
        surfaceContainer: Color(hex: "#131313"),
        surfaceContainerHigh: Color(hex: "#1a1919"),
        textPrimary: Color(hex: "#ffffff"),
        textSecondary: Color(hex: "#adaaaa"),
        primaryAccent: Color(hex: "#ff7cf5"),
        secondaryAccent: Color(hex: "#00fbfb"),
        tertiaryAccent: Color(hex: "#8eff71"),
        border: Color(white: 1.0, opacity: 0.1),
        error: Color(hex: "#ff6e84")
    )
    
    public static let luminous = Theme(
        id: "luminous",
        name: "Luminous",
        backgroundMain: Color(hex: "#0f172a"),
        surface: Color(hex: "#0f172a"),
        surfaceContainer: Color(hex: "#1e293b"),
        surfaceContainerHigh: Color(hex: "#334155"),
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
        name: "Nordic Frost",
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
    
    public static let all: [Theme] = [.vantage, .cyberpunk, .luminous, .nordicFrost]
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
