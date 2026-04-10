import AppKit
import SwiftUI

@main
struct TokenGuardApp: App {
    @State private var accountStore: AccountStore
    @State private var keychainManager: KeychainManager
    @State private var pollingEngine: UsagePollingEngine
    @State private var themeManager = ThemeManager.shared

    init() {
        let store = AccountStore()
        let keychain = KeychainManager()
        _accountStore = State(initialValue: store)
        _keychainManager = State(initialValue: keychain)
        _pollingEngine = State(initialValue: UsagePollingEngine(accountStore: store, keychainManager: keychain))
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
                .frame(width: 400, height: 280)
        }
    }
    
    private func menuBarIcon() -> NSImage {
        let image = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: "TokenGuard")!
        image.isTemplate = true
        return image
    }
}
