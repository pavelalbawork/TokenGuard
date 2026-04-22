import AppKit
import SwiftUI

@main
struct TokenGuardApp: App {
    @State private var accountStore: AccountStore
    @State private var keychainManager: KeychainManager
    @State private var pollingEngine: UsagePollingEngine
    @State private var themeManager = ThemeManager.shared

    init() {
        // Register UserDefaults fallbacks so the polling engine always sees a valid value,
        // even on a fresh install before the user has touched the Settings picker.
        // (AppStorage sets a SwiftUI-side default but does NOT write to UserDefaults,
        // so object(forKey:) would otherwise return nil and bypass the global interval.)
        UserDefaults.standard.register(defaults: [
            "globalRefreshIntervalMins": 15
        ])

        let store = AccountStore()
        let keychain = KeychainManager()
        let engine = UsagePollingEngine(accountStore: store, keychainManager: keychain)
        engine.start()
        _accountStore = State(initialValue: store)
        _keychainManager = State(initialValue: keychain)
        _pollingEngine = State(initialValue: engine)
    }

    private var worstStatusMaxRatio: Double {
        var maxRatio = 0.0
        for state in pollingEngine.accountStates.values {
            guard let snapshot = state.snapshot else { continue }
            for window in snapshot.windows {
                if let limit = window.limit, limit > 0 {
                    let ratio = window.used / limit
                    if ratio > maxRatio { maxRatio = ratio }
                }
            }
        }
        return maxRatio
    }

    var body: some Scene {
        MenuBarExtra {
            MainPopoverView()
                .environment(accountStore)
                .environment(pollingEngine)
                .environment(themeManager)
                .preferredColorScheme(themeManager.currentTheme.isLight ? .light : .dark)
                .frame(width: 400, height: 800)
                .onAppear {
                    pollingEngine.start()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSWorkspace.didWakeNotification
                    )
                ) { _ in
                    Task { await pollingEngine.refreshAll(force: true) }
                }
        } label: {
            Image(nsImage: menuBarIcon())
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(accountStore)
                .environment(pollingEngine)
                .environment(themeManager)
                .preferredColorScheme(themeManager.currentTheme.isLight ? .light : .dark)
                .frame(width: 400, height: 280)
        }
    }
    
    private func menuBarIcon() -> NSImage {
        let image = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: "TokenGuard")!
        image.isTemplate = true
        return image
    }
}
