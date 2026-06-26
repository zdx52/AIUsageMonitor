import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    
    @State private var deepSeekKey: String = ""
    @State private var tavilyKey: String = ""
    @State private var refreshInterval: Double = 300
    @State private var showDeepSeekKey: Bool = false
    @State private var showTavilyKey: Bool = false
    @State private var openCodeURL: String = ""
    @State private var saveMessage: String = ""
    @State private var showMessage: Bool = false
    @State private var isLoggingIn: Bool = false
    @State private var loginMessage: String = ""
    @State private var showDeepSeek: Bool = true
    @State private var showTavily: Bool = true
    @State private var showOpenCode: Bool = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题
                HStack {
                    Text("⚙️ 设置")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    if showMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                    Button("保存") {
                        saveSettings()
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    Button("关闭") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
                
                Divider()
                
                // MARK: - 显示设置
                GroupBox("👁️ 显示设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("选择在菜单栏弹窗中显示哪些内容")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Toggle("DeepSeek 余额", isOn: $showDeepSeek)
                        Toggle("Tavily 用量", isOn: $showTavily)
                        Toggle("OpenCode GO 用量", isOn: $showOpenCode)
                    }
                    .padding(.vertical, 4)
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
                
                // OpenCode 设置
                GroupBox("🔄 OpenCode GO") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("工作区 URL（用于获取剩余用量）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("https://opencode.ai/workspace/.../go", text: $openCodeURL)
                            .textFieldStyle(.roundedBorder)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("💡 在 App 内登录 OpenCode（使用 GitHub / Google 账号）：")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Button("在 App 内登录") {
                                isLoggingIn = true
                                loginMessage = ""
                                UserDefaults.standard.set(openCodeURL, forKey: "openCodeWorkspaceURL")
                                OpenCodeService.shared.showLoginWindow(urlString: openCodeURL) { success in
                                    DispatchQueue.main.async {
                                        isLoggingIn = false
                                        if success {
                                            loginMessage = "✅ 登录成功！数据已刷新"
                                            Task { await dataStore.refreshAll() }
                                        } else {
                                            loginMessage = "⚠️ 登录取消或失败，请重试"
                                        }
                                    }
                                }
                            }
                            .disabled(openCodeURL.isEmpty || isLoggingIn)
                            .buttonStyle(.bordered)
                            
                            if isLoggingIn {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("登录窗口中...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if !loginMessage.isEmpty {
                                Text(loginMessage)
                                    .font(.caption)
                                    .foregroundColor(loginMessage.contains("✅") ? .green : .secondary)
                            }
                        }
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
            }
            .padding()
        }
        .frame(width: 480)
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        deepSeekKey = KeychainHelper.get(key: "deepseek_api_key") ?? ""
        tavilyKey = KeychainHelper.get(key: "tavily_api_key") ?? ""
        openCodeURL = UserDefaults.standard.string(forKey: "openCodeWorkspaceURL") ?? ""
        
        if let interval = UserDefaults.standard.object(forKey: "refreshInterval") as? Double {
            refreshInterval = interval
        }
        
        showDeepSeek = UserDefaults.standard.object(forKey: "showDeepSeek") as? Bool ?? true
        showTavily = UserDefaults.standard.object(forKey: "showTavily") as? Bool ?? true
        showOpenCode = UserDefaults.standard.object(forKey: "showOpenCode") as? Bool ?? true
    }
    
    private func saveSettings() {
        KeychainHelper.save(key: "deepseek_api_key", value: deepSeekKey)
        KeychainHelper.save(key: "tavily_api_key", value: tavilyKey)
        UserDefaults.standard.set(openCodeURL, forKey: "openCodeWorkspaceURL")
        UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
        UserDefaults.standard.set(showDeepSeek, forKey: "showDeepSeek")
        UserDefaults.standard.set(showTavily, forKey: "showTavily")
        UserDefaults.standard.set(showOpenCode, forKey: "showOpenCode")
        
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
    
    // startLogin() 已移除，改用「在浏览器中登录」+「检查登录状态」
}
