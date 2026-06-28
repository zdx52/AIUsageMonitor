import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showSettings = false
    @State private var refreshID = UUID()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 标题
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("AI 用量监控")
                        .font(.headline)
                    Spacer()
                    Text("v\(appVersion)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if dataStore.isLoading {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
                // 渐变装饰条
                LinearGradient(
                    colors: [.purple, .cyan, .orange],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 2)
                .clipShape(Capsule())
                .padding(.top, 8)
            }
            .padding(.bottom, 2)
            
            // MARK: - DeepSeek 数据
            if UserDefaults.standard.bool(forKey: "showDeepSeek") {
                UsageCard(
                    icon: "waveform.path.ecg",
                    title: "DeepSeek",
                    iconColor: .purple,
                    backgroundColor: deepSeekBackgroundColor
                ) {
                    if let ds = dataStore.deepSeekBalance {
                        UsageRow(label: "总余额", value: "¥\(String(format: "%.2f", ds.totalBalance))")
                        UsageRow(label: "赠送余额", value: "¥\(String(format: "%.2f", ds.grantedBalance))")
                        UsageRow(label: "充值余额", value: "¥\(String(format: "%.2f", ds.toppedUpBalance))")
                        if ds.todayCost > 0 {
                            UsageRow(label: "今日消耗", value: "¥\(String(format: "%.2f", ds.todayCost))")
                        }
                        Text("货币: \(ds.currency)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        
                        if ds.totalBalance < 5 {
                            Label("余额不足，请尽快充值", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if ds.totalBalance < 20 {
                            Label("余额偏低", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("暂无数据")
                            .foregroundStyle(.secondary)
                        Text("请在设置中配置 DeepSeek API Key")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            // MARK: - Tavily 数据
            if UserDefaults.standard.bool(forKey: "showTavily") {
                UsageCard(
                    icon: "magnifyingglass",
                    title: "Tavily",
                    iconColor: .cyan,
                    backgroundColor: .cyan.opacity(0.1)
                ) {
                    if let tv = dataStore.tavilyUsage {
                        UsageRow(label: "计划", value: tv.plan)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("已用/总额度")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(tv.creditsUsed)/\(tv.monthlyLimit)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            ProgressBar(
                                percentage: tv.monthlyLimit > 0
                                    ? Double(tv.creditsUsed) / Double(tv.monthlyLimit) * 100
                                    : 0
                            )
                        }
                        
                        UsageRow(label: "剩余", value: "\(tv.remaining)")
                    } else {
                        Text("暂无数据")
                            .foregroundStyle(.secondary)
                        Text("请在设置中配置 Tavily API Key")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            // MARK: - OpenCode GO 数据
            if UserDefaults.standard.bool(forKey: "showOpenCode") {
                UsageCard(
                    icon: "arrow.triangle.2.circlepath",
                    title: "OpenCode GO",
                    iconColor: .orange,
                    backgroundColor: .orange.opacity(0.1)
                ) {
                    switch dataStore.openCodeStatus {
                    case .notConfigured:
                        Text("未配置")
                            .foregroundStyle(.secondary)
                        Text("请在设置中配置 OpenCode 工作区")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                    case .noCookies:
                        VStack(alignment: .leading, spacing: 6) {
                            Label("登录已过期", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .fontWeight(.medium)
                            Text("请在登录窗口中完成 GitHub/Google 登录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("在 App 内登录") {
                                let url = UserDefaults.standard.string(forKey: "openCodeWorkspaceURL") ?? ""
                                dataStore.isOpenCodeLoggingIn = true
                                SettingsWindowController.shared.show(with: dataStore)
                                OpenCodeService.shared.showLoginWindow(urlString: url) { success in
                                    if success {
                                        Task {
                                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                                            await dataStore.refreshAll()
                                        }
                                    }
                                    dataStore.isOpenCodeLoggingIn = false
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(dataStore.isOpenCodeLoggingIn)
                        }
                        
                    case .needsLogin:
                        VStack(alignment: .leading, spacing: 6) {
                            Label("需要登录", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .fontWeight(.medium)
                            Text("请在登录窗口中完成 GitHub/Google 登录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("在 App 内登录") {
                                let url = UserDefaults.standard.string(forKey: "openCodeWorkspaceURL") ?? ""
                                dataStore.isOpenCodeLoggingIn = true
                                SettingsWindowController.shared.show(with: dataStore)
                                OpenCodeService.shared.showLoginWindow(urlString: url) { success in
                                    if success {
                                        Task {
                                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                                            await dataStore.refreshAll()
                                        }
                                    }
                                    dataStore.isOpenCodeLoggingIn = false
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(dataStore.isOpenCodeLoggingIn)
                        }
                        
                    case .fetchFailed:
                        VStack(alignment: .leading, spacing: 6) {
                            Label("数据获取失败", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .fontWeight(.medium)
                            Text("请在登录窗口中使用 GitHub 或 Google 登录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("在 App 内登录") {
                                let url = UserDefaults.standard.string(forKey: "openCodeWorkspaceURL") ?? ""
                                dataStore.isOpenCodeLoggingIn = true
                                SettingsWindowController.shared.show(with: dataStore)
                                OpenCodeService.shared.showLoginWindow(urlString: url) { success in
                                    if success {
                                        Task {
                                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                                            await dataStore.refreshAll()
                                        }
                                    }
                                    dataStore.isOpenCodeLoggingIn = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(dataStore.isOpenCodeLoggingIn)
                        }
                        
                    case .success:
                        if let oc = dataStore.openCodeUsage {
                            if let rolling = oc.rollingPercent {
                                UsageProgressRow(label: "滚动用量", percentage: rolling)
                                if let reset = oc.rollingReset {
                                    Text("重置于 \(reset)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            
                            if let weekly = oc.weeklyPercent {
                                UsageProgressRow(label: "每周用量", percentage: weekly)
                                if let reset = oc.weeklyReset {
                                    Text("重置于 \(reset)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            
                            if let monthly = oc.monthlyPercent {
                                UsageProgressRow(label: "每月用量", percentage: monthly)
                                if let reset = oc.monthlyReset {
                                    Text("重置于 \(reset)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            
                            if oc.rollingPercent == nil && oc.weeklyPercent == nil && oc.monthlyPercent == nil {
                                if let pct = oc.rpcUsagePercent {
                                    UsageProgressRow(label: "用量", percentage: pct)
                                } else if !oc.usagePercentages.isEmpty {
                                    UsageProgressRow(label: "用量", percentage: Double(oc.usagePercentages.first!))
                                } else {
                                    UsageRow(label: "状态", value: "已订阅")
                                }
                            }
                            
                            if oc.useBalance {
                                Label("已启用余额补充", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            
            // 刷新时间
            if let time = dataStore.lastRefreshTime {
                Text("上次刷新: \(time, style: .time)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            // 操作按钮
            HStack {
                Button(action: {
                    Task {
                        await dataStore.refreshAll()
                    }
                }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Spacer()
                
                Button(action: {
                    SettingsWindowController.shared.show(with: dataStore)
                }) {
                    Label("设置", systemImage: "gearshape")
                        .font(.caption)
                }
                
                Spacer()
                
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Label("退出", systemImage: "power")
                        .font(.caption)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding()
        .frame(width: 320)
    }
    
    // MARK: - DeepSeek 背景色（余额预警）
    
    private var deepSeekBackgroundColor: Color {
        guard let ds = dataStore.deepSeekBalance else {
            return .purple.opacity(0.1)
        }
        if ds.totalBalance < 5 {
            return .red.opacity(0.12)
        } else if ds.totalBalance < 20 {
            return .orange.opacity(0.12)
        }
        return .purple.opacity(0.1)
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?.?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

// MARK: - 卡片组件

struct UsageCard<Content: View>: View {
    let icon: String
    let title: String
    let iconColor: Color
    var backgroundColor: Color = Color(.controlBackgroundColor)
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(iconColor.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - 行组件

struct UsageRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.footnote)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - 进度条行（标签 + 进度条 + 百分比）

struct UsageProgressRow: View {
    let label: String
    let percentage: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(percentage))%")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            ProgressBar(percentage: percentage)
        }
    }
}

// MARK: - 进度条组件

struct ProgressBar: View {
    let percentage: Double
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.separatorColor).opacity(0.3))
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: geo.size.width * clampedPercentage / 100)
                    .animation(.easeInOut(duration: 0.6), value: clampedPercentage)
            }
        }
        .frame(height: 8)
    }
    
    private var clampedPercentage: Double {
        min(max(percentage, 0), 100)
    }
    
    private var barColor: Color {
        if percentage >= 80 { return .red.opacity(0.8) }
        if percentage >= 50 { return .orange.opacity(0.8) }
        return .green.opacity(0.8)
    }
}
