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
                .frame(width: 360, height: 800)
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
            let ratio = worstStatusMaxRatio
            Image(nsImage: depletingShieldImage(ratio: ratio))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(accountStore)
                .environment(pollingEngine)
                .environment(themeManager)
                .frame(width: 420, height: 280)
        }
    }
    
    private func depletingShieldImage(ratio: Double) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw empty shield outline
            if let shield = NSImage(systemSymbolName: "shield", accessibilityDescription: nil) {
                shield.draw(in: rect)
            }
            
            let fillHeight = min(max(rect.height * CGFloat(1.0 - ratio), 0), rect.height)
            if fillHeight > 0, let shieldFill = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: nil) {
                NSGraphicsContext.current?.saveGraphicsState()
                
                // Clip bottom-up based on fill ratio
                let clipRect = NSRect(x: 0, y: 0, width: rect.width, height: fillHeight)
                NSBezierPath(rect: clipRect).addClip()
                
                // Draw the fill physically inset by 1.5 points so there is a guaranteed geometric gap 
                // between the fluid and the outer container walls.
                // This bypasses the macOS menu bar template alpha-dropping bug!
                shieldFill.draw(in: rect.insetBy(dx: 1.5, dy: 1.5))
                
                NSGraphicsContext.current?.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
