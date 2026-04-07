import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager
    
    @AppStorage("providerOrderStr") private var providerOrderStr: String = "codex,claude,gemini,antigravity,custom"
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("globalRefreshIntervalMins") private var refreshIntervalMins: Int = 15
    
    @State private var orderedServices: [ServiceType] = []

    var body: some View {
        let theme = themeManager.currentTheme
        
        VStack(spacing: 0) {
            Text("General Settings")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                
            List {
                Section(header: Text("Startup").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.textSecondary)) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .onChange(of: launchAtLogin) { newValue in
                            if newValue {
                                try? SMAppService.mainApp.register()
                            } else {
                                try? SMAppService.mainApp.unregister()
                            }
                        }
                }
                .listRowBackground(theme.surfaceContainerHigh.opacity(0.3))
                
                Section(header: Text("Data").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.textSecondary)) {
                    Picker("Background Refresh", selection: $refreshIntervalMins) {
                        Text("Every 1 minute").tag(1)
                        Text("Every 5 minutes").tag(5)
                        Text("Every 15 minutes").tag(15)
                        Text("Every 30 minutes").tag(30)
                        Text("Every 1 hour").tag(60)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    // We don't dynamically update interval of polling yet as it requires pollingEngine changes,
                    // but we will persist it and polling engine could read fromUserDefaults.
                }
                .listRowBackground(theme.surfaceContainerHigh.opacity(0.3))

                Section(header: Text("Provider Display Order (Drag to Reorder)").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.textSecondary)) {
                    ForEach(orderedServices, id: \.self) { service in
                        HStack {
                            Image(systemName: service.iconName)
                                .font(.system(size: 12))
                                .foregroundStyle(service.tintColor(for: theme))
                                .frame(width: 20)
                            
                            Text(service.rawValue.capitalized)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                                
                            Spacer()
                            
                            HStack(spacing: 8) {
                                Button(action: { moveUp(service) }) {
                                    Image(systemName: "chevron.up")
                                        .foregroundStyle(theme.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(orderedServices.first == service)
                                
                                Button(action: { moveDown(service) }) {
                                    Image(systemName: "chevron.down")
                                        .foregroundStyle(theme.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(orderedServices.last == service)
                            }
                        }
                        .listRowBackground(theme.surfaceContainerHigh.opacity(0.3))
                    }
                }
            }
            .listStyle(.sidebar)
            .background(theme.backgroundMain)
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            let orderKeys = providerOrderStr.components(separatedBy: ",")
            var sorted = ServiceType.allCases.sorted { a, b in
                let idxA = orderKeys.firstIndex(of: a.rawValue) ?? 999
                let idxB = orderKeys.firstIndex(of: b.rawValue) ?? 999
                return idxA < idxB
            }
            // Ensure all are present
            for type in ServiceType.allCases {
                if !sorted.contains(type) { sorted.append(type) }
            }
            orderedServices = sorted
            
            // Sync toggle UI with actual OS state
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    
    private func moveUp(_ service: ServiceType) {
        guard let index = orderedServices.firstIndex(of: service), index > 0 else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        withAnimation_Settings {
            orderedServices.swapAt(index, index - 1)
            providerOrderStr = orderedServices.map { $0.rawValue }.joined(separator: ",")
        }
    }
    
    private func moveDown(_ service: ServiceType) {
        guard let index = orderedServices.firstIndex(of: service), index < orderedServices.count - 1 else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        withAnimation_Settings {
            orderedServices.swapAt(index, index + 1)
            providerOrderStr = orderedServices.map { $0.rawValue }.joined(separator: ",")
        }
    }
    
    private func withAnimation_Settings(_ body: () -> Void) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            body()
        }
    }
}
