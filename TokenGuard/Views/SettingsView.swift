import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(UsagePollingEngine.self) private var pollingEngine
    
    @AppStorage("providerOrderStr") private var providerOrderStr: String = "codex,claude,gemini,antigravity,custom"
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("globalRefreshIntervalMins") private var refreshIntervalMins: Int = 15
    
    @State private var orderedServices: [ServiceType] = []
    @State private var launchAtLoginError: String?

    var body: some View {
        @Bindable var bindableThemeManager = themeManager
        let theme = themeManager.currentTheme
        
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(theme.textPrimary)

                Text("Adjust how TokenGuard looks, refreshes, and organizes providers.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textSecondary.opacity(0.9))
            }

            // Section: Appearance
            VStack(alignment: .leading, spacing: 12) {
                Text("THEME")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(theme.textSecondary)
                
                ThemeSelectorView(themeManager: bindableThemeManager)
            }

            // Section: Startup
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Launch", theme: theme)
                
                HStack {
                    Text("Launch at login")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel("Launch at login")
                }
                .padding(10)
                .background(settingsRowBackground(for: theme))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(settingsBorder(for: theme), lineWidth: 1))
                .onChange(of: launchAtLogin) { _, newValue in
                    launchAtLoginError = nil
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLoginError = error.localizedDescription
                        launchAtLogin = !newValue
                    }
                }
                
                if let error = launchAtLoginError {
                    Text(error)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.error)
                        .padding(.horizontal, 4)
                        .accessibilityLabel(error)
                }
            }
            
            // Section: Data
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Updates", theme: theme)
                
                HStack {
                    Text("Refresh Interval")
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
                    .accessibilityLabel("Refresh interval")
                }
                .padding(10)
                .background(settingsRowBackground(for: theme))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(settingsBorder(for: theme), lineWidth: 1))
                .onChange(of: refreshIntervalMins) { _, _ in
                    pollingEngine.restartPollingLoop()
                }
            }
            
            // Section: Provider Order
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionHeader("Provider Order", theme: theme)
                    Spacer()
                    Text("Use arrows to reorder")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .accessibilityLabel("Use arrows to reorder providers")
                }
                
                VStack(spacing: 0) {
                    ForEach(Array(orderedServices.enumerated()), id: \.element) { index, service in
                        HStack(spacing: 10) {
                            Image(systemName: service.iconName)
                                .font(.system(size: 12))
                                .rotationEffect(.degrees(service.rotationAngle))
                                .foregroundStyle(service.tintColor(for: theme))
                                .frame(width: 18)
                            
                            Text(service.rawValue.capitalized)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                                
                            Spacer()

                            HStack(spacing: 8) {
                                reorderButton(systemName: "chevron.up", isDisabled: index == 0, theme: theme) {
                                    move(service, by: -1)
                                }

                                reorderButton(systemName: "chevron.down", isDisabled: index == orderedServices.count - 1, theme: theme) {
                                    move(service, by: 1)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        
                        if index < orderedServices.count - 1 {
                            Divider()
                                .background(theme.border)
                                .padding(.horizontal, 10)
                        }
                    }
                }
                .background(settingsRowBackground(for: theme))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(settingsBorder(for: theme), lineWidth: 1))
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
        .preferredColorScheme(themeManager.currentTheme.isLight ? .light : .dark)
        .environment(\.colorScheme, themeManager.currentTheme.isLight ? .light : .dark)
        .tint(theme.primaryAccent)
    }
    
    @ViewBuilder
    private func sectionHeader(_ title: String, theme: Theme) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.textPrimary.opacity(0.8))
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func reorderButton(systemName: String, isDisabled: Bool, theme: Theme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isDisabled ? theme.textSecondary.opacity(0.3) : theme.textPrimary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(theme.isLight ? theme.surfaceContainerHigh.opacity(0.5) : theme.surfaceContainerHigh.opacity(0.45))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel(systemName == "chevron.up" ? "Move provider up" : "Move provider down")
        .accessibilityHint("Reorders the provider list")
    }

    private func move(_ service: ServiceType, by offset: Int) {
        guard let index = orderedServices.firstIndex(of: service) else { return }
        let destination = index + offset
        guard orderedServices.indices.contains(destination) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            orderedServices.swapAt(index, destination)
            persistProviderOrder()
        }
    }

    private func persistProviderOrder() {
        providerOrderStr = orderedServices.map { $0.rawValue }.joined(separator: ",")
    }

    private func settingsRowBackground(for theme: Theme) -> Color {
        theme.isLight ? theme.surfaceContainerHigh.opacity(0.75) : theme.surfaceContainerHigh.opacity(0.35)
    }

    private func settingsBorder(for theme: Theme) -> Color {
        theme.isLight ? theme.border.opacity(0.85) : theme.border
    }
}

struct ThemeSelectorView: View {
    @Bindable var themeManager: ThemeManager
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Theme.all) { theme in
                ThemeCardView(theme: theme, isSelected: themeManager.selectedThemeId == theme.id)
                    .onTapGesture {
                        themeManager.selectedThemeId = theme.id
                    }
            }
        }
    }
}

struct ThemeCardView: View {
    let theme: Theme
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Preview Area
            VStack(alignment: .leading, spacing: 12) {
                // Top Bar Mock
                HStack(spacing: 8) {
                    Circle()
                        .fill(theme.primaryAccent)
                        .frame(width: 6, height: 6)
                    
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(theme.surfaceContainerHigh)
                            .frame(height: 4)
                        Capsule()
                            .fill(theme.primaryAccent)
                            .frame(width: 40, height: 4)
                    }
                    
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    // Icon Mock
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.surfaceContainerHigh)
                            .frame(width: 24, height: 24)
                        Circle()
                            .strokeBorder(theme.primaryAccent, lineWidth: 2)
                            .frame(width: 12, height: 12)
                    }
                    
                    // Text Lines Mock
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule()
                            .fill(theme.textPrimary)
                            .frame(width: 60, height: 3)
                        Capsule()
                            .fill(theme.textSecondary)
                            .frame(width: 80, height: 3)
                    }
                }
                
                // Bottom Pills Mock
                HStack(spacing: 6) {
                    Spacer()
                    Capsule()
                        .fill(theme.primaryAccent)
                        .frame(width: 40, height: 4)
                    Capsule()
                        .fill(theme.secondaryAccent)
                        .frame(width: 40, height: 4)
                }
                .padding(.top, 4)
            }
            .padding(12)
            .background(theme.backgroundMain)
            
            // Info Area
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text(theme.tagline)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.primaryAccent)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor)) // Adaptive native background for info area
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? theme.primaryAccent : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
