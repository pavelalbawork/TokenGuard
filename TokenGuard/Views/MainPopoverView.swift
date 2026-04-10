import SwiftUI

enum NavigationTab: String, CaseIterable {
    case usage = "USAGE"
    case accounts = "ACCOUNTS"
    case settings = "SETTINGS"
}

struct MainPopoverView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine
    @Environment(ThemeManager.self) private var themeManager
    
    @State private var selectedTab: NavigationTab = .usage
    @State private var isAddingAccount = false
    @Namespace private var animationNameSpace

    @AppStorage("providerOrderStr") private var providerOrderStr: String = "codex,claude,gemini,antigravity,custom"

    var body: some View {
        let theme = themeManager.currentTheme
        
        VStack(spacing: 0) {
            // Header: tabs on left, actions on right
            HStack(spacing: 0) {
                // Navigation tabs
                HStack(spacing: 4) {
                    ForEach(NavigationTab.allCases, id: \.self) { tab in
                        headerTabButton(title: tab.rawValue, isSelected: selectedTab == tab && !isAddingAccount, theme: theme) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Refresh usage")

                    Button(action: {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isAddingAccount = true
                        }
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13, weight: .light))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Add account")
                    
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.isLight ? theme.backgroundMain : theme.backgroundMain.opacity(0.95))
            .background(.ultraThinMaterial)
            .border(width: 1, edges: [.bottom], color: theme.border)
            .zIndex(1)

            // Main Content Area
            ScrollView {
                VStack(spacing: 16) {
                    if !heroServiceTypes.isEmpty {
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
                                VStack(alignment: .leading, spacing: 22) {
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
                            PopoverAccountEditScreen()
                        } else if selectedTab == .settings {
                            SettingsView()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isAddingAccount)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            
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
                .accessibilityLabel("Quit TokenGuard")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(theme.backgroundMain)
            .border(width: 1, edges: [.top], color: theme.border)
        }
        .background(theme.backgroundMain)
        .ignoresSafeArea()
    }
    
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }

    private var heroServiceTypes: [ServiceType] {
        accountStore.accounts.reduce(into: Set<ServiceType>()) { partialResult, account in
            partialResult.insert(account.serviceType)
        }
        .intersection([.codex, .claude, .gemini, .antigravity])
        .sorted { $0.rawValue < $1.rawValue }
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
                .padding(.horizontal, 12)
                .frame(height: 34)
                .frame(minWidth: 80)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(theme.surfaceContainerHigh)
                                .matchedGeometryEffect(id: "TabHighlight", in: animationNameSpace)
                        }
                    }
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title.capitalized) tab")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct PopoverAccountEditScreen: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.currentTheme

        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ACCOUNTS")
                    .font(.system(size: 14, weight: .black))
                    .tracking(1.0)
                    .foregroundStyle(theme.textPrimary)

                Text("Manage linked accounts and optional display names.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 12) {
                ForEach(accountStore.accounts) { account in
                    PopoverAccountEditRow(account: account, theme: theme)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .padding(.top, 16)
    }
}

struct PopoverAccountEditRow: View {
    let account: Account
    let theme: Theme

    @Environment(AccountStore.self) private var accountStore
    @Environment(UsagePollingEngine.self) private var pollingEngine

    @State private var alias: String = ""
    @State private var isDeleteConfirmationPresented = false
    @State private var mutationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: account.serviceType.iconName)
                    .rotationEffect(.degrees(account.serviceType.rotationAngle))
                    .foregroundStyle(account.serviceType.tintColor(for: theme))
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.serviceType.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                    Text(account.consumerEmail ?? account.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                }
                Spacer()

                Button(action: { isDeleteConfirmationPresented = true }) {
                    Image(systemName: "trash")
                        .foregroundStyle(theme.error.opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ALIAS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.textSecondary)

                TextField("Enter Alias (Optional)", text: $alias)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .padding(8)
                    .background(theme.isLight ? theme.surfaceContainer : theme.backgroundMain)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
                    .onChange(of: alias) { _, newValue in
                        updateAlias(newValue)
                    }

                if let mutationError {
                    Text(mutationError)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.error)
                }
            }
        }
        .padding(12)
        .background(theme.isLight ? theme.surfaceContainerHigh : theme.surfaceContainerHigh.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border, lineWidth: 1))
        .alert("Delete account?", isPresented: $isDeleteConfirmationPresented) {
            Button("Delete", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved account and its local state.")
        }
        .onAppear {
            alias = account.alias ?? ""
        }
    }

    private func updateAlias(_ value: String) {
        var updated = account
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.alias = trimmed.isEmpty ? nil : trimmed

        do {
            try accountStore.update(updated)
            mutationError = nil
        } catch {
            mutationError = "Could not save alias: \(error.localizedDescription)"
        }
    }

    private func deleteAccount() {
        do {
            try pollingEngine.deleteAccount(account)
            mutationError = nil
        } catch {
            mutationError = "Could not delete account: \(error.localizedDescription)"
        }
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

    @AppStorage("providerOrderStr") private var providerOrderStr: String = "codex,claude,gemini,antigravity,custom"

    var body: some View {
        let theme = themeManager.currentTheme
        let (codex, claude, gemini, ag) = calculateMetrics()

        let orderKeys = providerOrderStr.components(separatedBy: ",")
        let presentServices = Set(accountStore.accounts.map(\.serviceType))
        let sortedServices = [ServiceType.codex, ServiceType.claude, ServiceType.gemini, ServiceType.antigravity]
            .filter { presentServices.contains($0) }
            .sorted { a, b in
            let idxA = orderKeys.firstIndex(of: a.rawValue) ?? 999
            let idxB = orderKeys.firstIndex(of: b.rawValue) ?? 999
            return idxA < idxB
        }

        HStack(alignment: .top, spacing: 10) {
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
                        baseColor: ServiceType.codex.tintColor(for: theme).opacity(0.3),
                        accentColor: ServiceType.codex.tintColor(for: theme)
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
                        baseColor: ServiceType.claude.tintColor(for: theme).opacity(0.3),
                        accentColor: ServiceType.claude.tintColor(for: theme)
                    )
                    .frame(maxWidth: .infinity)
                } else if service == .gemini {
                    UnifiedConcentricGauge(
                        title: "GEMINI",
                        icon: ServiceType.gemini.iconName,
                        outerLabel: "PRO",
                        middleLabel: "FLASH",
                        innerLabel: "LITE",
                        metrics: gemini,
                        theme: theme,
                        baseColor: ServiceType.gemini.tintColor(for: theme).opacity(0.3),
                        accentColor: ServiceType.gemini.tintColor(for: theme)
                    )
                    .frame(maxWidth: .infinity)
                } else if service == .antigravity {
                    UnifiedConcentricGauge(
                        title: "AG",
                        icon: ServiceType.antigravity.iconName,
                        outerLabel: "CLAUDE",
                        middleLabel: "PRO",
                        innerLabel: "FLASH",
                        metrics: ag,
                        theme: theme,
                        baseColor: ServiceType.antigravity.tintColor(for: theme).opacity(0.3),
                        accentColor: ServiceType.antigravity.tintColor(for: theme),
                        rotation: ServiceType.antigravity.rotationAngle
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.isLight ? theme.surfaceContainer : theme.surfaceContainerHigh.opacity(0.3)) // Ultra luxury finish
        )
    }

    private func calculateMetrics() -> (codex: ProviderMetrics, claude: ProviderMetrics, gemini: ProviderMetrics, ag: ProviderMetrics) {
        var c_shortTot = 0.0, c_shortCnt = 0, c_longTot = 0.0, c_longCnt = 0
        var cl_shortTot = 0.0, cl_shortCnt = 0, cl_longTot = 0.0, cl_longCnt = 0
        var g_proTot = 0.0, g_proCnt = 0
        var g_flashTot = 0.0, g_flashCnt = 0
        var g_liteTot = 0.0, g_liteCnt = 0
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
            } else if account.serviceType == .gemini {
                for window in snapshot.windows {
                    guard let progress = window.percentUsed, let label = window.label else { continue }
                    if label == "PRO" {
                        g_proTot += progress; g_proCnt += 1
                    } else if label == "FLASH" {
                        g_flashTot += progress; g_flashCnt += 1
                    } else if label == "LITE" {
                        g_liteTot += progress; g_liteCnt += 1
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

        let gemini = ProviderMetrics(
            outerTerm: g_proCnt > 0 ? (g_proTot / Double(g_proCnt)) : nil,
            middleTerm: g_flashCnt > 0 ? (g_flashTot / Double(g_flashCnt)) : nil,
            innerTerm: g_liteCnt > 0 ? (g_liteTot / Double(g_liteCnt)) : nil
        )

        let ag = ProviderMetrics(
            outerTerm: ag_claudeCnt > 0 ? (ag_claudeTot / Double(ag_claudeCnt)) : nil,
            middleTerm: ag_geminiProCnt > 0 ? (ag_geminiProTot / Double(ag_geminiProCnt)) : nil,
            innerTerm: ag_geminiFlashCnt > 0 ? (ag_geminiFlashTot / Double(ag_geminiFlashCnt)) : nil
        )

        return (codex, claude, gemini, ag)
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
        
        VStack(spacing: 10) {
            ZStack {
                // Background Tracks
                Circle()
                    .stroke(theme.surfaceContainerHigh.opacity(0.3), lineWidth: 4.5)
                    .frame(width: 70, height: 70)
                Circle()
                    .stroke(theme.surfaceContainerHigh.opacity(0.4), lineWidth: 3.5)
                    .frame(width: 56, height: 56)
                if metrics.innerTerm != nil {
                    Circle()
                        .stroke(theme.surfaceContainerHigh.opacity(0.5), lineWidth: 2.5)
                        .frame(width: 44, height: 44)
                }
                
                // Center Symbol
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
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
                        .stroke(midRingColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: midRingColor.opacity(0.3), radius: 2, x: 0, y: 0)
                }
                
                // Middle Ring
                Circle()
                    .trim(from: 0.0, to: middleRemaining)
                    .stroke(midRingColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: midRingColor.opacity(0.4), radius: 3, x: 0, y: 0)
                
                // Outer Ring
                Circle()
                    .trim(from: 0.0, to: outerRemaining)
                    .stroke(
                        LinearGradient(colors: [baseColor, accentColor], startPoint: .bottom, endPoint: .top),
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                    )
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accentColor.opacity(0.6), radius: 4, x: 0, y: 0)
            }
            .frame(width: 70, height: 70)
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(theme.textPrimary)
                
                if let outer = metrics.outerTerm, let outerLbl = outerLabel {
                    HStack(spacing: 3) {
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
                    HStack(spacing: 3) {
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
                    HStack(spacing: 3) {
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
