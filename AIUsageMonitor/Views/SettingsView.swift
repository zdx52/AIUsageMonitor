import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    
    @State private var deepSeekKey: String = ""
    @State private var tavilyKey: String = ""
    @State private var miniMaxSubscriptionKey: String = ""
    @State private var refreshInterval: Double = 300
    @State private var showDeepSeekKey: Bool = false
    @State private var showTavilyKey: Bool = false
    @State private var showMiniMaxKey: Bool = false
    @State private var openCodeURL: String = ""
    @State private var saveMessage: String = ""
    @State private var showMessage: Bool = false
    @State private var loginMessage: String = ""
    @State private var showDeepSeek: Bool = true
    @State private var showTavily: Bool = true
    @State private var showMiniMax: Bool = true
    @State private var showMiniMaxVideo: Bool = false
    @State private var showOpenRouter: Bool = true
    @State private var showOpenRouterKey: Bool = false
    @State private var openRouterKey: String = ""
    @State private var showOpenCode: Bool = true
    @State private var showHindsight: Bool = true
    
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
                    Text("v\(Bundle.main.appVersionString)")
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
                        Toggle("MiniMax Token Plan", isOn: $showMiniMax)
                        Toggle("OpenRouter 用量", isOn: $showOpenRouter)
                        Toggle("OpenCode GO 用量", isOn: $showOpenCode)
                        Toggle("Hindsight 记忆", isOn: $showHindsight)
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
                
                // OpenRouter 设置
                GroupBox("🌐 OpenRouter") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Management Key（用于查询账户充值/用量；普通 API Key 无权限）")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            if showOpenRouterKey {
                                TextField("sk-or-v1-...", text: $openRouterKey)
                            } else {
                                SecureField("sk-or-v1-...", text: $openRouterKey)
                            }

                            Button(action: { showOpenRouterKey.toggle() }) {
                                Image(systemName: showOpenRouterKey ? "eye.slash" : "eye")
                            }
                        }

                        Text("获取方式: openrouter.ai → Settings → Keys → 创建 Management Key")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("⚠️ 需要 Management Key；普通 API Key 调用用量接口会返回 403")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 4)
                }

                // MiniMax Token Plan 设置
                GroupBox("✨ MiniMax (中国)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("订阅 Key（用于查询 Token Plan 用量，非按量付费 API Key）")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            if showMiniMaxKey {
                                TextField("eyJ...", text: $miniMaxSubscriptionKey)
                            } else {
                                SecureField("eyJ...", text: $miniMaxSubscriptionKey)
                            }

                            Button(action: { showMiniMaxKey.toggle() }) {
                                Image(systemName: showMiniMaxKey ? "eye.slash" : "eye")
                            }
                        }

                        Text("获取方式: platform.minimaxi.com → 订阅付费 → Token Plan → 查看订阅 Key（JWT 格式，以 eyJ 开头）")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("⚠️ 仅支持订阅 Key；按量计费 API Key 不互通（官方明确不可混用）")
                            .font(.caption2)
                            .foregroundColor(.orange)

                        Divider()

                        Toggle("显示 video 模型用量", isOn: $showMiniMaxVideo)
                            .help("video 模型（独立计费）默认隐藏，勾选后在菜单栏 MiniMax 卡片中显示")
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
                            Text("💡 登录 OpenCode（使用 GitHub / Google 账号）：")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                Button("🔐 快速登录") {
                                    UserDefaults.standard.set(openCodeURL, forKey: "openCodeWorkspaceURL")
                                    OpenCodeService.shared.showLoginWindow(urlString: openCodeURL) { success in
                                        DispatchQueue.main.async {
                                            if success {
                                                loginMessage = "✅ 登录成功！数据已刷新"
                                                Task {
                                                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                                                    await dataStore.refreshAll()
                                                }
                                            } else {
                                                loginMessage = "⚠️ 登录取消"
                                            }
                                        }
                                    }
                                }
                                .disabled(openCodeURL.isEmpty)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                
                                Button("🌐 浏览器") {
                                    UserDefaults.standard.set(openCodeURL, forKey: "openCodeWorkspaceURL")
                                    OpenCodeService.shared.openLoginInBrowser(urlString: openCodeURL)
                                }
                                .disabled(openCodeURL.isEmpty)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button("✅ 检测") {
                                    Task { await dataStore.refreshAll() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            if !loginMessage.isEmpty {
                                Text(loginMessage)
                                    .font(.caption)
                                    .foregroundColor(loginMessage.contains("✅") ? .green : .orange)
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
        miniMaxSubscriptionKey = KeychainHelper.get(key: "minimax_subscription_key") ?? ""
        openRouterKey = KeychainHelper.get(key: "openrouter_management_key") ?? ""
        openCodeURL = UserDefaults.standard.string(forKey: "openCodeWorkspaceURL") ?? ""

        if let interval = UserDefaults.standard.object(forKey: "refreshInterval") as? Double {
            refreshInterval = interval
        }

        showDeepSeek = UserDefaults.standard.object(forKey: "showDeepSeek") as? Bool ?? true
        showTavily = UserDefaults.standard.object(forKey: "showTavily") as? Bool ?? true
        showMiniMax = UserDefaults.standard.object(forKey: "showMiniMax") as? Bool ?? true
        showMiniMaxVideo = UserDefaults.standard.object(forKey: "showMiniMaxVideo") as? Bool ?? false
        showOpenRouter = UserDefaults.standard.object(forKey: "showOpenRouter") as? Bool ?? true
        showOpenCode = UserDefaults.standard.object(forKey: "showOpenCode") as? Bool ?? true
        showHindsight = UserDefaults.standard.object(forKey: "showHindsight") as? Bool ?? true
    }

    private func saveSettings() {
        KeychainHelper.save(key: "deepseek_api_key", value: deepSeekKey)
        KeychainHelper.save(key: "tavily_api_key", value: tavilyKey)
        KeychainHelper.save(key: "minimax_subscription_key", value: miniMaxSubscriptionKey)
        KeychainHelper.save(key: "openrouter_management_key", value: openRouterKey)
        UserDefaults.standard.set(openCodeURL, forKey: "openCodeWorkspaceURL")
        UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
        UserDefaults.standard.set(showDeepSeek, forKey: "showDeepSeek")
        UserDefaults.standard.set(showTavily, forKey: "showTavily")
        UserDefaults.standard.set(showMiniMax, forKey: "showMiniMax")
        UserDefaults.standard.set(showMiniMaxVideo, forKey: "showMiniMaxVideo")
        UserDefaults.standard.set(showOpenRouter, forKey: "showOpenRouter")
        UserDefaults.standard.set(showOpenCode, forKey: "showOpenCode")
        UserDefaults.standard.set(showHindsight, forKey: "showHindsight")
        
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
