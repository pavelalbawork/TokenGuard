import SwiftUI

@Observable
public class ThemeManager {
    public var selectedThemeId: String {
        didSet {
            UserDefaults.standard.set(selectedThemeId, forKey: "selectedThemeId")
            updateTheme()
        }
    }
    
    public var currentTheme: Theme = .vantage
    
    @MainActor public static let shared = ThemeManager()
    
    private init() {
        self.selectedThemeId = UserDefaults.standard.string(forKey: "selectedThemeId") ?? Theme.vantage.id
        updateTheme()
    }
    
    private func updateTheme() {
        if let theme = Theme.all.first(where: { $0.id == selectedThemeId }) {
            self.currentTheme = theme
        } else {
            // Fallback gracefully if an old invalid theme ID is in UserDefaults
            self.currentTheme = .vantage
            self.selectedThemeId = Theme.vantage.id
        }
    }
    
    public func setTheme(_ theme: Theme) {
        selectedThemeId = theme.id
    }
}
