import SwiftUI

enum NavigationTab: String, CaseIterable {
    case usage = "USAGE"
    case limits = "LIMITS"
    case history = "HISTORY"
}

struct MainPopoverView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager
    
    @State private var selectedTab: NavigationTab = .usage
    @State private var showSettings = false // Drives inline settings display if clicked from header
    @State private var isAddingAccount = false
    @Namespace private var animationNameSpace

    @AppStorage("providerOrderStr") private var providerOrderStr: String = "codex,claude,gemini,antigravity,custom"

    var body: some View {
        @Bindable var bindableThemeManager = themeManager
        let theme = themeManager.currentTheme
        
        VStack(spacing: 0) {
            // Header: tabs on left, actions on right
            HStack(spacing: 0) {
                // Navigation tabs
                HStack(spacing: 2) {
                    ForEach(NavigationTab.allCases, id: \.self) { tab in
                        headerTabButton(title: tab.rawValue, isSelected: selectedTab == tab && !showSettings && !isAddingAccount, theme: theme) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showSettings = false
                                isAddingAccount = false
                                selectedTab = tab
                            }
                        }
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        Task { await pollingEngine.refreshAll() }
                    }) {
                        if pollingEngine.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .light))
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textSecondary)
                    
                    Menu {
                        Picker("Theme", selection: $bindableThemeManager.selectedThemeId) {
                            ForEach(Theme.all) { t in
                                Text(t.name).tag(t.id)
                            }
                        }
                    } label: {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 13, weight: .light))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textSecondary)

                    Button(action: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isAddingAccount = true
                            showSettings = false
                        }
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13, weight: .light))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textSecondary)
                    
                    Button(action: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showSettings.toggle()
                            if showSettings { isAddingAccount = false }
                        }
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .light))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(showSettings ? theme.primaryAccent : theme.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.backgroundMain.opacity(0.95))
            .background(.ultraThinMaterial)
            .border(width: 1, edges: [.bottom], color: theme.border)
            .zIndex(1)

            // Main Content Area
            if showSettings {
                // Item 8: explicitly inject environments so SettingsView is safe if ever detached
                ScrollView {
                    SettingsView()
                        .environment(accountStore)
                        .environment(pollingEngine)
                        .environment(themeManager)
                        .padding(16)
                }
                .scrollIndicators(.hidden)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if !accountStore.accounts.isEmpty {
                            GlobalUsageHeroView()
                        }
                        
                        // Router Content
                        Group {
                            if isAddingAccount {
                                InlineAddAccountView(
                                    onCancel: {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            isAddingAccount = false
                                        }
                                    },
                                    onComplete: { 
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            isAddingAccount = false
                                            selectedTab = .usage
                                        }
                                    }
                                )
                            } else if selectedTab == .usage {
                                if accountStore.accounts.isEmpty {
                                    Button(action: {
                                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            isAddingAccount = true
                                        }
                                    }) {
                                        VStack(spacing: 16) {
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 32, weight: .ultraLight))
                                                .symbolRenderingMode(.hierarchical)
                                            Text("No accounts configured yet. Click to add.")
                                        }
                                        .foregroundStyle(theme.textSecondary)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 40)
                                } else {
                                    VStack(alignment: .leading, spacing: 24) {
                                        let orderKeys = providerOrderStr.components(separatedBy: ",")
                                        let sortedTypes = ServiceType.allCases.sorted { a, b in
                                            let idxA = orderKeys.firstIndex(of: a.rawValue) ?? 999
                                            let idxB = orderKeys.firstIndex(of: b.rawValue) ?? 999
                                            return idxA < idxB
                                        }
                                        let serviceTypes = sortedTypes.filter { serviceType in
                                            accountStore.accounts.contains { $0.serviceType == serviceType }
                                        }
                                        ForEach(serviceTypes, id: \.self) { serviceType in
                                            ServiceSectionView(
                                                serviceType: serviceType,
                                                accounts: accountStore.accounts.filter { $0.serviceType == serviceType }
                                            )
                                        }
                                    }
                                }
                            } else if selectedTab == .limits {
                                LimitsView()
                            } else if selectedTab == .history {
                                HistoryView()
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isAddingAccount)
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            
            // Footer
            HStack {
                Text(appVersion)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textSecondary.opacity(0.4))

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("QUIT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(theme.textSecondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(theme.backgroundMain)
            .border(width: 1, edges: [.top], color: theme.border)
        }
        .background(theme.backgroundMain)
        .ignoresSafeArea()
    }
    
    // Item 7: pull version from Bundle
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }

    @ViewBuilder
    private func headerTabButton(title: String, isSelected: Bool, theme: Theme, action: @escaping () -> Void) -> some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            action()
        }) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(theme.surfaceContainerHigh)
                                .matchedGeometryEffect(id: "TabHighlight", in: animationNameSpace)
                        }
                    }
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// Helper extension to draw borders on specific edges
extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }
            
            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }
            
            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }
            
            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}

struct GlobalUsageHeroView: View {
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        let theme = themeManager.currentTheme
        let totalProgress = calculateGlobalProgress()
        
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("OVERALL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(theme.textSecondary)
                
                Text("\(Int((1.0 - totalProgress) * 100))%")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                
                Text("AVG. REMAINING")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(theme.textSecondary.opacity(0.7))
            }
            
            Spacer()
            
            ZStack {
                CyberDialGraphic(
                    progress: totalProgress,
                    theme: theme
                )
                .frame(width: 60, height: 60)
                
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.secondaryAccent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.surfaceContainerHigh.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.border, lineWidth: 1)
        )
    }
    
    private func calculateGlobalProgress() -> Double {
        var totalPercent = 0.0
        var windowCount = 0
        
        for state in pollingEngine.accountStates.values {
            guard let snapshot = state.snapshot else { continue }
            for window in snapshot.windows {
                if let percent = window.percentUsed {
                    totalPercent += percent
                    windowCount += 1
                } else if let limit = window.limit, limit > 0 {
                    totalPercent += (window.used / limit)
                    windowCount += 1
                }
            }
        }
        
        return windowCount > 0 ? (totalPercent / Double(windowCount)) : 0.0
    }
}

struct CyberDialGraphic: View {
    var progress: Double // 0 to 1
    var theme: Theme
    
    var body: some View {
        ZStack {
            // Outer dashed container
            Circle()
                .stroke(theme.surfaceContainerHigh, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(width: 80, height: 80)
                
            // Inner thick background track
            Circle()
                .stroke(theme.surfaceContainerHigh.opacity(0.5), lineWidth: 8)
                .frame(width: 64, height: 64)
            
            // The live draining capacity ring
            let remaining = CGFloat(max(0, 1.0 - min(progress, 1.0)))
            Circle()
                .trim(from: 0, to: remaining)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [theme.tertiaryAccent, theme.primaryAccent]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.6), value: remaining)
                .frame(width: 64, height: 64)
                .shadow(color: theme.primaryAccent.opacity(0.8), radius: 6, x: 0, y: 0)
                
            // Center crosshairs
            Path { path in
                path.move(to: CGPoint(x: 40, y: 35))
                path.addLine(to: CGPoint(x: 40, y: 45))
                path.move(to: CGPoint(x: 35, y: 40))
                path.addLine(to: CGPoint(x: 45, y: 40))
            }
            .stroke(theme.secondaryAccent.opacity(0.5), lineWidth: 1)
        }
    }
}

// MARK: - LIMITS VIEW FRONTEND

struct LimitsView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("API CAPACITIES")
                    .font(.system(size: 14, weight: .black))
                    .tracking(1.0)
                    .foregroundStyle(theme.textPrimary)
                
                Text("Maximum hard limits established by the providers.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 16)
            
            // Capabilities List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(filteredServices, id: \.self) { serviceType in
                        let accounts = accountStore.accounts.filter { $0.serviceType == serviceType }
                        if !accounts.isEmpty {
                            providerLimitsCard(serviceType: serviceType, accounts: accounts, theme: theme)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .padding(.top, 16)
    }

    private var filteredServices: [ServiceType] {
        ServiceType.allCases.filter { type in
            accountStore.accounts.contains(where: { $0.serviceType == type })
        }
    }

    @ViewBuilder
    private func providerLimitsCard(serviceType: ServiceType, accounts: [Account], theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Provider Header
            HStack(spacing: 6) {
                Image(systemName: serviceType.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(serviceType.tintColor(for: theme))
                Text(serviceType.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            .padding(.bottom, 4)
            
            // Extracted Limits
            ForEach(accounts) { account in
                if let snapshot = pollingEngine.accountStates[account.id]?.snapshot {
                    ForEach(snapshot.windows) { window in
                        HStack {
                            Text(window.label ?? window.windowType.defaultLabel)
                                .font(.system(size: 9, weight: .bold))
                                .textCase(.uppercase)
                                .foregroundStyle(theme.textSecondary)
                            
                            Spacer()
                            
                            if let limit = window.limit {
                                Text("\(IntegerFormatStyle<Int>().format(Int(limit)))\(window.unit.suffix)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(theme.secondaryAccent)
                            } else {
                                Text("UNLIMITED")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(theme.tertiaryAccent)
                            }
                        }
                        .padding(8)
                        .background(theme.surfaceContainerHigh.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    Text("Fetching capacities for \(account.name)...")
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(theme.textSecondary.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(theme.surfaceContainerHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

// MARK: - HISTORY VIEW FRONTEND

struct HistoryView: View {
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AccountStore.self) private var accountStore

    // Mock recent events based on active data and resets
    private var simulatedEvents: [HistoryEvent] {
        var events: [HistoryEvent] = []
        for account in accountStore.accounts {
            guard let state = pollingEngine.accountStates[account.id], let snapshot = state.snapshot else { continue }
            
            // Add a "Checked" event
            events.append(HistoryEvent(
                date: snapshot.timestamp,
                title: "Usage snapshot captured",
                accountName: account.name,
                serviceType: account.serviceType,
                type: .check
            ))
            
            for window in snapshot.windows {
                if let percent = window.percentUsed, percent < 0.20 {
                    // Under 20% remaining
                    events.append(HistoryEvent(
                        date: snapshot.timestamp.addingTimeInterval(-3600), // fuzzy past
                        title: "\(window.label ?? window.windowType.defaultLabel) approaching cap",
                        accountName: account.name,
                        serviceType: account.serviceType,
                        type: .warning
                    ))
                }
                
                if let limit = window.limit, window.used >= limit {
                    events.append(HistoryEvent(
                        date: snapshot.timestamp.addingTimeInterval(-1200),
                        title: "Hard limit reached",
                        accountName: account.name,
                        serviceType: account.serviceType,
                        type: .critical
                    ))
                }
            }
        }
        return events.sorted(by: { $0.date > $1.date }) // Newest first
    }

    var body: some View {
        let theme = themeManager.currentTheme
        let events = simulatedEvents

        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("EVENT LOG")
                    .font(.system(size: 14, weight: .black))
                    .tracking(1.0)
                    .foregroundStyle(theme.textPrimary)
                
                Text("Recent capacity warnings and sync events.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 16)
            
            if events.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(theme.textSecondary.opacity(0.5))
                    Text("No recent events")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 12) {
                                // Timeline indicator
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(event.color(theme: theme))
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 4)
                                    
                                    Rectangle()
                                        .fill(theme.border)
                                        .frame(width: 1)
                                        .padding(.vertical, 4)
                                }
                                
                                // Event Content
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: event.serviceType.iconName)
                                            .font(.system(size: 9))
                                            .foregroundStyle(event.serviceType.tintColor(for: theme))
                                        
                                        Text(event.accountName.uppercased())
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(theme.textSecondary)
                                        
                                        Spacer()
                                        
                                        Text(timeAgo(for: event.date))
                                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                                            .foregroundStyle(theme.textSecondary.opacity(0.6))
                                    }
                                    
                                    Text(event.title)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(theme.textPrimary)
                                }
                                .padding(.bottom, 8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 16)
    }
    
    private func timeAgo(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Mock Data Models

fileprivate struct HistoryEvent: Identifiable {
    let id = UUID()
    let date: Date
    let title: String
    let accountName: String
    let serviceType: ServiceType
    let type: EventType
    
    enum EventType {
        case check
        case warning
        case critical
    }
    
    func color(theme: Theme) -> Color {
        switch type {
        case .check: return theme.tertiaryAccent.opacity(0.6)
        case .warning: return theme.secondaryAccent
        case .critical: return theme.error
        }
    }
}
