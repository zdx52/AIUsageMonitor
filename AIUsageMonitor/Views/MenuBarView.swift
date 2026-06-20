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
