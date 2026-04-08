import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager
    
    @AppStorage("providerOrderStr") private var providerOrderStr: String = "codex,claude,antigravity,custom"
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("globalRefreshIntervalMins") private var refreshIntervalMins: Int = 15
    
    @State private var orderedServices: [ServiceType] = []

    var body: some View {
        let theme = themeManager.currentTheme
        
        VStack(alignment: .leading, spacing: 16) {
            // Section: Startup
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Startup", theme: theme)
                
                HStack {
                    Text("Launch at login")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
                .padding(10)
                .background(theme.surfaceContainerHigh.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
                .onChange(of: launchAtLogin) { _, newValue in
                    if newValue {
                        try? SMAppService.mainApp.register()
                    } else {
                        try? SMAppService.mainApp.unregister()
                    }
                }
            }
            
            // Section: Data
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Data", theme: theme)
                
                HStack {
                    Text("Background Refresh")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Picker("", selection: $refreshIntervalMins) {
                        Text("1 min").tag(1)
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(10)
                .background(theme.surfaceContainerHigh.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            }
            
            // Section: Provider Order
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Provider Display Order", theme: theme)
                
                VStack(spacing: 0) {
                    ForEach(Array(orderedServices.enumerated()), id: \.element) { index, service in
                        HStack(spacing: 10) {
                            Image(systemName: service.iconName)
                                .font(.system(size: 12))
                                .foregroundStyle(service.tintColor(for: theme))
                                .frame(width: 18)
                            
                            Text(service.rawValue.capitalized)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                                
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Button(action: { moveUp(service) }) {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(index == 0 ? theme.textSecondary.opacity(0.2) : theme.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(index == 0)
                                
                                Button(action: { moveDown(service) }) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(index == orderedServices.count - 1 ? theme.textSecondary.opacity(0.2) : theme.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(index == orderedServices.count - 1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        
                        if index < orderedServices.count - 1 {
                            Divider()
                                .background(theme.border)
                                .padding(.horizontal, 10)
                        }
                    }
                }
                .background(theme.surfaceContainerHigh.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            }
        }
        .onAppear {
            let orderKeys = providerOrderStr.components(separatedBy: ",")
            var sorted = ServiceType.allCases.sorted { a, b in
                let idxA = orderKeys.firstIndex(of: a.rawValue) ?? 999
                let idxB = orderKeys.firstIndex(of: b.rawValue) ?? 999
                return idxA < idxB
            }
            for type in ServiceType.allCases {
                if !sorted.contains(type) { sorted.append(type) }
            }
            orderedServices = sorted
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    
    @ViewBuilder
    private func sectionHeader(_ title: String, theme: Theme) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(theme.textSecondary)
    }
    
    private func moveUp(_ service: ServiceType) {
        guard let index = orderedServices.firstIndex(of: service), index > 0 else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            orderedServices.swapAt(index, index - 1)
            providerOrderStr = orderedServices.map { $0.rawValue }.joined(separator: ",")
        }
    }
    
    private func moveDown(_ service: ServiceType) {
        guard let index = orderedServices.firstIndex(of: service), index < orderedServices.count - 1 else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            orderedServices.swapAt(index, index + 1)
            providerOrderStr = orderedServices.map { $0.rawValue }.joined(separator: ",")
        }
    }
}
