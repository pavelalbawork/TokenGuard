import SwiftUI

@Observable
public class ThemeManager {
    public var selectedThemeId: String {
        didSet {
            UserDefaults.standard.set(selectedThemeId, forKey: "selectedThemeId")
            updateTheme()
        }
    }
    
    public var currentTheme: Theme = .nordicFrost
    
    @MainActor public static let shared = ThemeManager()
    
    private init() {
        self.selectedThemeId = UserDefaults.standard.string(forKey: "selectedThemeId") ?? Theme.nordicFrost.id
        updateTheme()
    }
    
    private func updateTheme() {
        if let theme = Theme.all.first(where: { $0.id == selectedThemeId }) {
            self.currentTheme = theme
        } else {
            // Fallback gracefully if an old invalid theme ID is in UserDefaults
            self.currentTheme = .nordicFrost
            self.selectedThemeId = Theme.nordicFrost.id
        }
    }
    
    public func setTheme(_ theme: Theme) {
        selectedThemeId = theme.id
    }
}
