import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var showSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Text("🤖 AI 用量监控")
                    .font(.headline)
                Spacer()
                if dataStore.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            
            Divider()
            
            // DeepSeek 数据
            UsageCard(
                icon: "🐋",
                title: "DeepSeek",
                color: .purple
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
                        .foregroundColor(.secondary)
                } else {
                    Text("暂无数据")
                        .foregroundColor(.secondary)
                    Text("请在设置中配置 DeepSeek API Key")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Divider()
            
            // Tavily 数据
            UsageCard(
                icon: "🔍",
                title: "Tavily",
                color: .cyan
            ) {
                if let tv = dataStore.tavilyUsage {
                    UsageRow(label: "计划", value: tv.plan)
                    UsageRow(label: "月度额度", value: "\(tv.monthlyLimit)")
                    UsageRow(label: "已用", value: "\(tv.creditsUsed)")
                    UsageRow(label: "剩余", value: "\(tv.remaining)")
                } else {
                    Text("暂无数据")
                        .foregroundColor(.secondary)
                    Text("请在设置中配置 Tavily API Key")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Divider()
            
            // OpenCode GO 数据
            UsageCard(
                icon: "🔄",
                title: "OpenCode GO",
                color: .orange
            ) {
                switch dataStore.openCodeStatus {
                case .notConfigured:
                    Text("未配置")
                        .foregroundColor(.secondary)
                    Text("请在设置中配置 OpenCode 工作区")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                case .noCookies:
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("⚠️")
                            Text("登录已过期")
                                .foregroundColor(.orange)
                                .fontWeight(.medium)
                        }
                        Text("Cookie 已失效，需要重新登录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("重新登录") {
                            let url = UserDefaults.standard.string(forKey: "openCodeWorkspaceURL") ?? ""
                            OpenCodeService.shared.showLoginWindow(urlString: url) {
                                Task { await dataStore.refreshAll() }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                case .needsLogin:
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("⚠️")
                            Text("需要登录")
                                .foregroundColor(.orange)
                                .fontWeight(.medium)
                        }
                        Text("被重定向到了登录页")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("重新登录") {
                            let url = UserDefaults.standard.string(forKey: "openCodeWorkspaceURL") ?? ""
                            OpenCodeService.shared.showLoginWindow(urlString: url) {
                                Task { await dataStore.refreshAll() }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                case .fetchFailed:
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("❌")
                            Text("数据获取失败")
                                .foregroundColor(.red)
                                .fontWeight(.medium)
                        }
                        Text("RPC 和页面抓取均失败，可能需要重新登录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("重新登录") {
                            let url = UserDefaults.standard.string(forKey: "openCodeWorkspaceURL") ?? ""
                            OpenCodeService.shared.showLoginWindow(urlString: url) {
                                Task { await dataStore.refreshAll() }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                case .success:
                    if let oc = dataStore.openCodeUsage {
                        // 三种用量显示
                        if let rolling = oc.rollingPercent {
                            UsageRow(label: "滚动用量", value: "\(Int(rolling))%")
                            if let reset = oc.rollingReset {
                                Text("重置于 \(reset)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let weekly = oc.weeklyPercent {
                            UsageRow(label: "每周用量", value: "\(Int(weekly))%")
                            if let reset = oc.weeklyReset {
                                Text("重置于 \(reset)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let monthly = oc.monthlyPercent {
                            UsageRow(label: "每月用量", value: "\(Int(monthly))%")
                            if let reset = oc.monthlyReset {
                                Text("重置于 \(reset)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 如果没有解析到三种用量，显示旧格式
                        if oc.rollingPercent == nil && oc.weeklyPercent == nil && oc.monthlyPercent == nil {
                            if let pct = oc.rpcUsagePercent {
                                UsageRow(label: "用量", value: "\(Int(pct))%")
                            } else if !oc.usagePercentages.isEmpty {
                                UsageRow(label: "用量", value: "\(oc.usagePercentages.first!)%")
                            } else {
                                UsageRow(label: "状态", value: "已订阅")
                            }
                        }
                        
                        if oc.useBalance {
                            Text("已启用余额补充")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Divider()
            
            // 刷新时间
            if let time = dataStore.lastRefreshTime {
                Text("上次刷新: \(time, style: .time)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // 操作按钮
            HStack {
                Button("刷新") {
                    Task {
                        await dataStore.refreshAll()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Spacer()
                
                Button("设置") {
                    SettingsWindowController.shared.show(with: dataStore)
                }
                
                Spacer()
                
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding()
        .frame(width: 320)
    }
}

struct UsageCard<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(icon)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            content
        }
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct UsageRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}
