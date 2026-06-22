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
                            Text("💡 在 App 内登录（自动保存登录态）：")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Button("在 App 内登录") {
                                startLogin()
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
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Text("登录成功后窗口会自动关闭，数据会自动刷新")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("提示: 登录一次后，重启 App 也无需重新登录。更换账号或工作区修改 URL 后重新登录即可")
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
    }
    
    private func saveSettings() {
        KeychainHelper.save(key: "deepseek_api_key", value: deepSeekKey)
        KeychainHelper.save(key: "tavily_api_key", value: tavilyKey)
        UserDefaults.standard.set(openCodeURL, forKey: "openCodeWorkspaceURL")
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
    
    private func startLogin() {
        isLoggingIn = true
        loginMessage = ""
        
        // 先保存 URL
        UserDefaults.standard.set(openCodeURL, forKey: "openCodeWorkspaceURL")
        
        OpenCodeService.shared.showLoginWindow(urlString: openCodeURL) {
            DispatchQueue.main.async {
                isLoggingIn = false
                loginMessage = "✅ 登录成功！数据已刷新"
                
                // 触发数据刷新
                Task {
                    await dataStore.refreshAll()
                }
            }
        }
    }
}
