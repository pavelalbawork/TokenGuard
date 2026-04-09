import SwiftUI

enum NavigationTab: String, CaseIterable {
    case usage = "USAGE"
    case accounts = "ACCOUNTS"
}

struct MainPopoverView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager
    
    @State private var selectedTab: NavigationTab = .usage
    @State private var showSettings = false // Drives inline settings display if clicked from header
    @State private var isAddingAccount = false
    @Namespace private var animationNameSpace

    @AppStorage("providerOrderStr") private var providerOrderStr: String = "codex,claude,antigravity,custom"

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
            .background(theme.isLight ? theme.backgroundMain : theme.backgroundMain.opacity(0.95))
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
                            } else if selectedTab == .accounts {
                                AccountEditScreen()
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

// MARK: - HERO VIEW
struct GlobalUsageHeroView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager
    
    struct ProviderMetrics {
        var outerTerm: Double?
        var middleTerm: Double?
        var innerTerm: Double?
        var isMiddleGrayedOut: Bool = false
    }

    @AppStorage("providerOrderStr") private var providerOrderStr: String = "codex,claude,antigravity,custom"

    var body: some View {
        let theme = themeManager.currentTheme
        let (codex, claude, ag) = calculateMetrics()

        let orderKeys = providerOrderStr.components(separatedBy: ",")
        let sortedServices = [ServiceType.codex, ServiceType.claude, ServiceType.antigravity].sorted { a, b in
            let idxA = orderKeys.firstIndex(of: a.rawValue) ?? 999
            let idxB = orderKeys.firstIndex(of: b.rawValue) ?? 999
            return idxA < idxB
        }

        HStack(alignment: .top, spacing: 20) {
            ForEach(sortedServices, id: \.self) { service in
                if service == .codex {
                    UnifiedConcentricGauge(
                        title: "CODEX",
                        icon: "terminal",
                        outerLabel: "WK",
                        middleLabel: "5H",
                        innerLabel: nil,
                        metrics: codex,
                        theme: theme,
                        baseColor: theme.primaryAccent.opacity(0.3),
                        accentColor: theme.primaryAccent
                    )
                    .frame(maxWidth: .infinity)
                } else if service == .claude {
                    UnifiedConcentricGauge(
                        title: "CLAUDE",
                        icon: "asterisk",
                        outerLabel: "WK",
                        middleLabel: "5H",
                        innerLabel: nil,
                        metrics: claude,
                        theme: theme,
                        baseColor: theme.primaryAccent.opacity(0.3),
                        accentColor: theme.primaryAccent.opacity(0.8)
                    )
                    .frame(maxWidth: .infinity)
                } else if service == .antigravity {
                    UnifiedConcentricGauge(
                        title: "AG",
                        icon: ServiceType.antigravity.iconName,
                        outerLabel: "CLAUDE",
                        middleLabel: "GEMINI PRO",
                        innerLabel: "GEMINI FLASH",
                        metrics: ag,
                        theme: theme,
                        baseColor: theme.primaryAccent.opacity(0.3),
                        accentColor: theme.primaryAccent.opacity(0.6),
                        rotation: ServiceType.antigravity.rotationAngle
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.isLight ? theme.surfaceContainer : theme.surfaceContainerHigh.opacity(0.3)) // Ultra luxury finish
        )
    }

    private func calculateMetrics() -> (codex: ProviderMetrics, claude: ProviderMetrics, ag: ProviderMetrics) {
        var c_shortTot = 0.0, c_shortCnt = 0, c_longTot = 0.0, c_longCnt = 0
        var cl_shortTot = 0.0, cl_shortCnt = 0, cl_longTot = 0.0, cl_longCnt = 0
        var ag_claudeTot = 0.0, ag_claudeCnt = 0
        var ag_geminiProTot = 0.0, ag_geminiProCnt = 0
        var ag_geminiFlashTot = 0.0, ag_geminiFlashCnt = 0

        for account in accountStore.accounts {
            guard let state = pollingEngine.accountStates[account.id], let snapshot = state.snapshot else { continue }
            
            if account.serviceType == .codex || account.serviceType == .claude {
                var weeklyProgress: Double = 0.0
                var shortProgress: Double = 0.0
                var hasShort = false
                var hasWeekly = false
                
                for window in snapshot.windows {
                    guard let progress = window.percentUsed else { continue }
                    if window.windowType == .weekly {
                        weeklyProgress = progress
                        hasWeekly = true
                    } else if window.windowType == .rolling5h {
                        shortProgress = progress
                        hasShort = true
                    }
                }
                
                if hasShort {
                    if hasWeekly && weeklyProgress >= 1.0 {
                        shortProgress = 1.0
                    }
                    if account.serviceType == .codex {
                        c_shortTot += shortProgress; c_shortCnt += 1
                    } else {
                        cl_shortTot += shortProgress; cl_shortCnt += 1
                    }
                }
                
                if hasWeekly {
                    if account.serviceType == .codex {
                        c_longTot += weeklyProgress; c_longCnt += 1
                    } else {
                        cl_longTot += weeklyProgress; cl_longCnt += 1
                    }
                }
            } else if account.serviceType == .antigravity {
                for window in snapshot.windows {
                    guard let progress = window.percentUsed else { continue }
                    if window.label == "Anthropic (Claude)" {
                        ag_claudeTot += progress; ag_claudeCnt += 1
                    } else if window.label == "Gemini Pro" {
                        ag_geminiProTot += progress; ag_geminiProCnt += 1
                    } else if window.label == "Gemini Flash" {
                        ag_geminiFlashTot += progress; ag_geminiFlashCnt += 1
                    }
                }
            }
        }

        var codex = ProviderMetrics(
            outerTerm: c_longCnt > 0 ? (c_longTot / Double(c_longCnt)) : nil,
            middleTerm: c_shortCnt > 0 ? (c_shortTot / Double(c_shortCnt)) : nil
        )
        if let outer = codex.outerTerm, outer >= 1.0 { codex.isMiddleGrayedOut = true }

        var claude = ProviderMetrics(
            outerTerm: cl_longCnt > 0 ? (cl_longTot / Double(cl_longCnt)) : nil,
            middleTerm: cl_shortCnt > 0 ? (cl_shortTot / Double(cl_shortCnt)) : nil
        )
        if let outer = claude.outerTerm, outer >= 1.0 { claude.isMiddleGrayedOut = true }

        let ag = ProviderMetrics(
            outerTerm: ag_claudeCnt > 0 ? (ag_claudeTot / Double(ag_claudeCnt)) : nil,
            middleTerm: ag_geminiProCnt > 0 ? (ag_geminiProTot / Double(ag_geminiProCnt)) : nil,
            innerTerm: ag_geminiFlashCnt > 0 ? (ag_geminiFlashTot / Double(ag_geminiFlashCnt)) : nil
        )

        return (codex, claude, ag)
    }
}

// MARK: - GAUGE COMPONENTS

struct UnifiedConcentricGauge: View {
    let title: String
    let icon: String
    let outerLabel: String?
    let middleLabel: String?
    let innerLabel: String?
    let metrics: GlobalUsageHeroView.ProviderMetrics
    let theme: Theme
    let baseColor: Color
    let accentColor: Color
    var rotation: Double = 0
    
    @State private var isBreathing = false
    
    var body: some View {
        let innerVal = metrics.innerTerm ?? 0.0
        let middleVal = metrics.middleTerm ?? 0.0
        let outerVal = metrics.outerTerm ?? 0.0
        
        let innerRemaining = CGFloat(max(0, 1.0 - min(innerVal, 1.0)))
        let middleRemaining = CGFloat(max(0, 1.0 - min(middleVal, 1.0)))
        let outerRemaining = CGFloat(max(0, 1.0 - min(outerVal, 1.0)))
        
        let pulseDuration = max(0.5, 3.0 * (1.0 - min(middleVal, 1.0)))
        let midRingColor = metrics.isMiddleGrayedOut ? theme.surfaceContainerHigh.opacity(0.8) : baseColor
        
        VStack(spacing: 12) {
            ZStack {
                // Background Tracks
                Circle()
                    .stroke(theme.surfaceContainerHigh.opacity(0.3), lineWidth: 6)
                    .frame(width: 84, height: 84)
                Circle()
                    .stroke(theme.surfaceContainerHigh.opacity(0.4), lineWidth: 4)
                    .frame(width: 68, height: 68)
                if metrics.innerTerm != nil {
                    Circle()
                        .stroke(theme.surfaceContainerHigh.opacity(0.5), lineWidth: 3)
                        .frame(width: 54, height: 54)
                }
                
                // Center Symbol
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(
                        LinearGradient(colors: [baseColor, accentColor], startPoint: .bottomLeading, endPoint: .topTrailing)
                    )
                    .shadow(color: accentColor.opacity(0.3), radius: 6, x: 0, y: 0)
                    .rotationEffect(.degrees(rotation))
                    .scaleEffect(isBreathing ? 1.05 : 0.95)
                    .opacity(isBreathing ? 1.0 : 0.6)
                    .animation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true), value: isBreathing)
                    .onAppear {
                        isBreathing = true
                    }
                
                // Inner Ring
                if metrics.innerTerm != nil {
                    Circle()
                        .trim(from: 0.0, to: innerRemaining)
                        .stroke(midRingColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 54, height: 54)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: midRingColor.opacity(0.3), radius: 2, x: 0, y: 0)
                }
                
                // Middle Ring
                Circle()
                    .trim(from: 0.0, to: middleRemaining)
                    .stroke(midRingColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 68, height: 68)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: midRingColor.opacity(0.4), radius: 3, x: 0, y: 0)
                
                // Outer Ring
                Circle()
                    .trim(from: 0.0, to: outerRemaining)
                    .stroke(
                        LinearGradient(colors: [baseColor, accentColor], startPoint: .bottom, endPoint: .top),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 84, height: 84)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accentColor.opacity(0.6), radius: 4, x: 0, y: 0)
            }
            .frame(width: 84, height: 84)
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(theme.textPrimary)
                
                if let outer = metrics.outerTerm, let outerLbl = outerLabel {
                    HStack(spacing: 4) {
                        Text("\(Int(max(0, 1.0 - outer) * 100))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                        Text(outerLbl)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.0)
                    }
                    .foregroundStyle(accentColor)
                }
                if let middle = metrics.middleTerm, let middleLbl = middleLabel {
                    let color = metrics.isMiddleGrayedOut ? theme.textSecondary.opacity(0.5) : accentColor.opacity(0.8)
                    HStack(spacing: 4) {
                        Text("\(Int(max(0, 1.0 - middle) * 100))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                        Text(middleLbl)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.0)
                    }
                    .foregroundStyle(color)
                }
                if let inner = metrics.innerTerm, let innerLbl = innerLabel {
                    let color = metrics.isMiddleGrayedOut ? theme.textSecondary.opacity(0.3) : accentColor.opacity(0.6)
                    HStack(spacing: 4) {
                        Text("\(Int(max(0, 1.0 - inner) * 100))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                        Text(innerLbl)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.0)
                    }
                    .foregroundStyle(color)
                }
            }
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
                    .rotationEffect(.degrees(serviceType.rotationAngle))
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
                                Text("UNKNOWN")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                        .padding(8)
                        .background(theme.isLight ? theme.surfaceContainer : theme.surfaceContainerHigh.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    Text("Fetching capacities...")
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(theme.textSecondary.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(theme.isLight ? theme.surfaceContainerHigh : theme.surfaceContainerHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}
