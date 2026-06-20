import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    
    @State private var deepSeekKey: String = ""
    @State private var tavilyKey: String = ""
    @State private var refreshInterval: Double = 300
    @State private var showDeepSeekKey: Bool = false
    @State private var showTavilyKey: Bool = false
    @State private var saveMessage: String = ""
    @State private var showMessage: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题
            HStack {
                Text("⚙️ 设置")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            
            Divider()
            
            // DeepSeek 设置
            GroupBox("🐋 DeepSeek") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("API Key（用于获取余额）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        if showDeepSeekKey {
                            TextField("sk-...", text: $deepSeekKey)
                        } else {
                            SecureField("sk-...", text: $deepSeekKey)
                        }
                        
                        Button(action: { showDeepSeekKey.toggle() }) {
                            Image(systemName: showDeepSeekKey ? "eye.slash" : "eye")
                        }
                    }
                    
                    Text("获取方式: platform.deepseek.com → API Keys → 创建")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // Tavily 设置
            GroupBox("🔍 Tavily") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("API Key（用于获取用量）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        if showTavilyKey {
                            TextField("tvly-...", text: $tavilyKey)
                        } else {
                            SecureField("tvly-...", text: $tavilyKey)
                        }
                        
                        Button(action: { showTavilyKey.toggle() }) {
                            Image(systemName: showTavilyKey ? "eye.slash" : "eye")
                        }
                    }
                    
                    Text("获取方式: app.tavily.com → API Keys → 复制")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // 刷新间隔
            GroupBox("⏱️ 刷新间隔") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Slider(value: $refreshInterval, in: 60...1800, step: 60)
                        Text("\(Int(refreshInterval / 60)) 分钟")
                            .frame(width: 60)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Divider()
            
            // 保存按钮
            HStack {
                if showMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                
                Spacer()
                
                Button("保存") {
                    saveSettings()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding()
        .frame(width: 420, height: 460)
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        deepSeekKey = KeychainHelper.get(key: "deepseek_api_key") ?? ""
        tavilyKey = KeychainHelper.get(key: "tavily_api_key") ?? ""
        
        if let interval = UserDefaults.standard.object(forKey: "refreshInterval") as? Double {
            refreshInterval = interval
        }
    }
    
    private func saveSettings() {
        KeychainHelper.save(key: "deepseek_api_key", value: deepSeekKey)
        KeychainHelper.save(key: "tavily_api_key", value: tavilyKey)
        UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
        
        withAnimation {
            saveMessage = "✅ 已保存"
            showMessage = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showMessage = false
            }
        }
        
        Task {
            await dataStore.refreshAll()
        }
    }
}
