import AppKit
import WebKit
import Foundation


// MARK: - OpenCode 服务

class OpenCodeService: NSObject, WKNavigationDelegate {
    // RPC 函数哈希（SolidStart server$ 函数签名）
    private let rpcHashes: [String: String] = [
        "lite.subscription.get": "c7389bd0e731f80f49593e5ee53835475f4e28594dd6bd83eb229bab753498cd",
        "go.referral.get": "2a0b2fef5fd2ec9eff0cb5d4955e4ada4eece21fac85591ed4c09630168d4844",
        "go.referral.usagePreview": "46625df0aecf05f270f7ae4612cde374d11350c8abaf8649027572228b8af150"
    ]
    
    private var fetchWebView: WKWebView?
    private var fetchCompletion: ((OpenCodeUsage?) -> Void)?
    private var fetchTimeoutTimer: Timer?
    private let defaultTimeout: TimeInterval = 30
    private var fetchLoginWindow: NSWindow?
    private let loginDelegate = LoginWindowNavigationDelegate()
    
    // 新增：JS 消息处理器和捕获的数据
    private var scriptMessageHandler: OpenCodeScriptMessageHandler?
    private var capturedAPIData: [String: [String: Any]] = [:]
    private var capturedPageText: String = ""
    
    static let shared = OpenCodeService()


    
    // MARK: - Cookie 获取
    
    /// 从 WKWebsiteDataStore 获取指定域名的 cookie
    private func getCookies(for domain: String) async -> [HTTPCookie] {
        return await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let filtered = cookies.filter { $0.domain.contains(domain) }
                continuation.resume(returning: filtered)
            }
        }
    }
    
    // MARK: - RPC 调用
    
    /// 向 OpenCode SolidStart RPC 端点发送请求
    private func callRPC(hash: String, body: Any) async -> Data? {
        guard let url = URL(string: "https://opencode.ai/_server?id=\(hash)") else {
            print("❌ OpenCode RPC URL 无效")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // 从 HTTPCookieStorage 获取 cookie（WKWebView 登录后 cookie 会同步到这里）
        let cookieStorage = HTTPCookieStorage.shared
        let cookies = cookieStorage.cookies(for: URL(string: "https://opencode.ai")!) ?? []
        if cookies.isEmpty {
            print("⚠️ OpenCode RPC: HTTPCookieStorage 没有 cookie")
            // 再试 WKWebsiteDataStore
            let wkCookies = await getCookies(for: "opencode.ai")
            if wkCookies.isEmpty {
                print("⚠️ OpenCode RPC: 两个 cookie store 都没有 cookie，需要登录")
                return nil
            }
            let cookieHeader = wkCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        } else {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("📡 OpenCode RPC 请求: \(url.lastPathComponent)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse {
                let logMsg = "📡 RPC status:\(httpResp.statusCode) body:\(String(data: data, encoding: .utf8)?.prefix(500) ?? "nil")"
            print(logMsg)
            if httpResp.statusCode != 200 {
                return nil
            }
            }
            return data
        } catch {
            print("❌ OpenCode RPC 请求失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - RPC 响应解析
    
    /// 解析 SolidStart server$ 函数返回格式 [errorOrNull, result]
    private func parseRPCResponse(_ data: Data) -> OpenCodeRPCResponse? {
        // 格式 1: [null, {usagePercent: ..., resetInSec: ..., ...}]
        if let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count >= 2 {
            if let resultObj = json[1] as? [String: Any] {
                let knownKeys: Set<String> = ["usagePercent", "resetInSec", "plan", "totalUsed", "totalLimit", "remaining", "useBalance"]
                let hasKnownKey = resultObj.keys.contains { knownKeys.contains($0) }
                
                if hasKnownKey,
                    let resultData = try? JSONSerialization.data(withJSONObject: resultObj) {
                    if let parsed = try? JSONDecoder().decode(OpenCodeRPCResponse.self, from: resultData) {
                        return parsed
                    }
                }
            }
        }
        
        // 格式 2: 直接是 {usagePercent: ..., ...}
        if let parsed = try? JSONDecoder().decode(OpenCodeRPCResponse.self, from: data) {
            return parsed
        }
        
        return nil
    }
    
    // MARK: - 获取用量数据（入口）
    
    func fetchUsage(urlString: String) async -> OpenCodeUsage? {
        
        // 同步检查 HTTPCookieStorage（WKWebView 登录后 cookie 会同步到这里）
        let ocURL = URL(string: "https://opencode.ai")!
        let httpCookies = HTTPCookieStorage.shared.cookies(for: ocURL) ?? []
        
        if httpCookies.isEmpty {
            return OpenCodeUsage(needsLogin: true, status: .noCookies)
        }
        
        let workspaceID = extractWorkspaceID(from: urlString)
        
        // 2. 先试 RPC
        if let wid = workspaceID, let rpcData = await callUsagePreviewRPC(workspaceID: wid) {
            print("✅ OpenCode RPC 成功获取数据")
            return OpenCodeUsage(
                useBalance: rpcData.useBalance ?? false,
                status: .success,
                rpcUsagePercent: rpcData.usagePercent,
                rpcResetInSec: rpcData.resetInSec,
                rpcPlan: rpcData.plan,
                rpcTotalUsed: rpcData.totalUsed,
                rpcTotalLimit: rpcData.totalLimit,
                rpcRemaining: rpcData.remaining
            )
        }
        
        // 3. RPC 失败，回退到 WKWebView 页面抓取
        print("⚠️ OpenCode RPC 失败，回退到页面抓取")
        let webViewResult = await fetchUsageViaWebView(urlString: urlString)
        
        if let result = webViewResult {
            // WebView 抓取成功，检查是否有实际数据
            let hasData = result.rpcUsagePercent != nil || result.rpcRemaining != nil || result.rpcPlan != nil
                || result.rollingPercent != nil || result.weeklyPercent != nil || result.monthlyPercent != nil
            if hasData {
                var r = result
                r.status = .success
                return r
            }
            // 有结果但没有有用数据 → fetchFailed
            var r = result
            r.status = .fetchFailed
            return r
        }
        
        // 4. 全部失败
        print("❌ OpenCode 所有获取方式均失败")
        return OpenCodeUsage(needsLogin: true, status: .fetchFailed)
    }
    
    private func callUsagePreviewRPC(workspaceID: String) async -> OpenCodeRPCResponse? {
        // 调用 go.referral.usagePreview
        guard let previewHash = rpcHashes["go.referral.usagePreview"] else {
            print("❌ OpenCode 找不到 usagePreview 的 RPC 哈希")
            return nil
        }
        
        if let data = await callRPC(hash: previewHash, body: [workspaceID]) {
            if let result = parseRPCResponse(data) {
                return result
            }
        }
        
        // 再试 go.referral.get
        guard let getHash = rpcHashes["go.referral.get"] else {
            print("❌ OpenCode 找不到 referral.get 的 RPC 哈希")
            return nil
        }
        
        if let data = await callRPC(hash: getHash, body: [workspaceID]) {
            if let result = parseRPCResponse(data) {
                return result
            }
        }
        
        return nil
    }
    
    /// 从 URL 路径中提取 workspace ID
    private func extractWorkspaceID(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let components = url.pathComponents
        if let wrkIndex = components.firstIndex(of: "workspace"),
            wrkIndex + 1 < components.count {
            let candidate = components[wrkIndex + 1]
            if candidate.hasPrefix("wrk_") {
                return candidate
            }
        }
        return nil
    }
    
    // MARK: - WKWebView 页面抓取（后备方案）
    
    private func fetchUsageViaWebView(urlString: String) async -> OpenCodeUsage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                self.cleanupFetch()
                self.capturedAPIData = [:]
                self.capturedPageText = ""
                
                let config = WKWebViewConfiguration()
                config.websiteDataStore = WKWebsiteDataStore.default()
                
                // 添加 JS 消息处理器
                let messageHandler = OpenCodeScriptMessageHandler(service: self)
                self.scriptMessageHandler = messageHandler
                config.userContentController.add(messageHandler, name: "openCodeData")
                
                // 注入 JS 拦截 fetch/XHR 并实时发送到 native
                let interceptScript = WKUserScript(
                    source: """
                        (function() {
                            if (window.__ocInit) return;
                            window.__ocInit = true;
                            window.__ocCaptured = [];
                            
                            function sendToNative(type, data, url) {
                                try {
                                    window.webkit.messageHandlers.openCodeData.postMessage({
                                        type: type,
                                        data: data,
                                        url: url || ''
                                    });
                                } catch(e) {}
                            }
                            
                            // 拦截 fetch
                            const origFetch = window.fetch;
                            window.fetch = async function(...args) {
                                const url = typeof args[0] === 'string' ? args[0] : (args[0]?.url || '');
                                const resp = await origFetch.apply(this, args);
                                if (url.includes('/_server') || url.includes('usage') || url.includes('subscription') || url.includes('balance') || url.includes('billing') || url.includes('plan') || url.includes('remaining') || url.includes('reset')) {
                                    const clone = resp.clone();
                                    try {
                                        const text = await clone.text();
                                        window.__ocCaptured.push({url, text});
                                        sendToNative('captured_api', text.substring(0, 10000), url);
                                    } catch(e) {}
                                }
                                return resp;
                            };
                            
                            // 拦截 XHR
                            const origOpen = XMLHttpRequest.prototype.open;
                            XMLHttpRequest.prototype.open = function(method, url) {
                                this._ocUrl = typeof url === 'string' ? url : (url?.toString() || '');
                                return origOpen.apply(this, arguments);
                            };
                            const origSend = XMLHttpRequest.prototype.send;
                            XMLHttpRequest.prototype.send = function(...args) {
                                this.addEventListener('load', function() {
                                    const url = this._ocUrl || '';
                                    if (url.includes('/_server') || url.includes('usage') || url.includes('subscription') || url.includes('balance') || url.includes('billing') || url.includes('plan') || url.includes('remaining') || url.includes('reset')) {
                                        const text = this.responseText || '';
                                        window.__ocCaptured.push({url, text});
                                        sendToNative('captured_api', text.substring(0, 10000), url);
                                    }
                                });
                                return origSend.apply(this, args);
                            };
                            
                            // 定时检查页面文本
                            setTimeout(function() {
                                try {
                                    const t = document.body ? document.body.innerText.substring(0, 10000) : '';
                                    sendToNative('page_text', t);
                                } catch(e) {}
                            }, 3000);
                            setTimeout(function() {
                                try {
                                    const t = document.body ? document.body.innerText.substring(0, 10000) : '';
                                    sendToNative('page_text', t);
                                } catch(e) {}
                            }, 8000);
                            setTimeout(function() {
                                try {
                                    const t = document.body ? document.body.innerText.substring(0, 10000) : '';
                                    sendToNative('page_text', t);
                                } catch(e) {}
                            }, 15000);
                        })();
                    """,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
                config.userContentController.addUserScript(interceptScript)
                
                self.fetchWebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
                self.fetchWebView?.navigationDelegate = self
                self.fetchCompletion = { result in
                    continuation.resume(returning: result)
                }
                
                self.fetchTimeoutTimer = Timer.scheduledTimer(withTimeInterval: self.defaultTimeout, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    print("⏰ OpenCode fetch timeout")
                    self.finishFetch(usage: nil)
                }
                
                guard let url = URL(string: urlString) else {
                    print("❌ OpenCode URL 无效")
                    self.finishFetch(usage: nil)
                    return
                }
                
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                self.fetchWebView?.load(request)
            }
        }
    }
    
    // MARK: - 登录窗口
    
    func showLoginWindow(urlString: String, onSuccess: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
            self.loginDelegate.onLoginSuccess = onSuccess
            webView.navigationDelegate = self.loginDelegate
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "OpenCode 登录"
            window.contentView = webView
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.isReleasedWhenClosed = false
            
            self.fetchLoginWindow = window
            
            if let url = URL(string: urlString) {
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    // MARK: - 内部方法
    
    private func cleanupFetch() {
        fetchTimeoutTimer?.invalidate()
        fetchTimeoutTimer = nil
        fetchWebView?.navigationDelegate = nil
        // 卸下 JS 消息处理器，WKWebView 会强持有 handler
        fetchWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "openCodeData")
        fetchWebView = nil
        fetchCompletion = nil
        capturedAPIData = [:]
        capturedPageText = ""
        scriptMessageHandler = nil
    }
    
    private func finishFetch(usage: OpenCodeUsage?) {
        fetchTimeoutTimer?.invalidate()
        fetchTimeoutTimer = nil
        
        if let completion = self.fetchCompletion {
            self.fetchCompletion = nil
            completion(usage)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.fetchWebView?.navigationDelegate = nil
            self?.fetchWebView = nil
            self?.capturedAPIData = [:]
            self?.capturedPageText = ""
            self?.scriptMessageHandler = nil
        }
    }
    
    // MARK: - JS 消息处理
    
    func handleScriptMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        
        if type == "captured_api" {
            guard let dataStr = body["data"] as? String,
                  let url = body["url"] as? String,
                  let data = dataStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // 也可能是数组格式 [null, {...}]
                if let dataStr = body["data"] as? String,
                    let url = body["url"] as? String,
                    let data = dataStr.data(using: .utf8),
                    let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
                    jsonArray.count >= 2,
                    let resultObj = jsonArray[1] as? [String: Any] {
                    capturedAPIData[url] = resultObj
                    print("📡 OpenCode API 拦截（数组格式）: \(url)")
                }
                return
            }
            capturedAPIData[url] = json
            print("📡 OpenCode API 拦截: \(url)")
            
            // 尝试立即解析提取
            if let usage = parseCapturedAPIData() {
                print("✅ OpenCode API 数据解析成功！")
                finishFetch(usage: usage)
            }
        }
        
if type == "extract_result" {
            guard let dataStr = body["data"] as? String,
                  let data = dataStr.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            
            let rollingPercent = parsed["rollingPercent"] as? Double
            let rollingReset = parsed["rollingReset"] as? String
            let weeklyPercent = parsed["weeklyPercent"] as? Double
            let weeklyReset = parsed["weeklyReset"] as? String
            let monthlyPercent = parsed["monthlyPercent"] as? Double
            let monthlyReset = parsed["monthlyReset"] as? String
            
            let hasThreeUsage = rollingPercent != nil || weeklyPercent != nil || monthlyPercent != nil
            
            if hasThreeUsage {
                print("📊 extract_result: rolling=\(rollingPercent ?? -1)%, weekly=\(weeklyPercent ?? -1)%, monthly=\(monthlyPercent ?? -1)%")
                let usage = OpenCodeUsage(
                    rollingPercent: rollingPercent,
                    rollingReset: rollingReset,
                    weeklyPercent: weeklyPercent,
                    weeklyReset: weeklyReset,
                    monthlyPercent: monthlyPercent,
                    monthlyReset: monthlyReset
                )
                finishFetch(usage: usage)
            }
        }
        
        if type == "page_text" {
            capturedPageText = body["data"] as? String ?? ""
        }
    }
    
    // MARK: - 解析捕获的 API 数据
    
    private func parseCapturedAPIData() -> OpenCodeUsage? {
        for (_, json) in capturedAPIData {
            // 尝试直接解析为 RPC 响应
            if let data = try? JSONSerialization.data(withJSONObject: json) {
                if let rpcResponse = try? JSONDecoder().decode(OpenCodeRPCResponse.self, from: data) {
                    if rpcResponse.usagePercent != nil || rpcResponse.remaining != nil || rpcResponse.plan != nil {
                        print("📊 解析到 RPC 数据: usagePercent=\(rpcResponse.usagePercent ?? -1), remaining=\(rpcResponse.remaining ?? -1), plan=\(rpcResponse.plan ?? "?")")
                        return OpenCodeUsage(
                            useBalance: rpcResponse.useBalance ?? false,
                            rpcUsagePercent: rpcResponse.usagePercent,
                            rpcResetInSec: rpcResponse.resetInSec,
                            rpcPlan: rpcResponse.plan,
                            rpcTotalUsed: rpcResponse.totalUsed,
                            rpcTotalLimit: rpcResponse.totalLimit,
                            rpcRemaining: rpcResponse.remaining
                        )
                    }
                }
            }
        }
        return nil
    }
    
    // MARK: - 从页面文本中提取数据（纯文本方式）
    
    private func parseTextForUsageData() -> OpenCodeUsage? {
        let text = capturedPageText
        guard !text.isEmpty else { return nil }
        
        // 过滤空行
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        var rollingPercent: Double?
        var rollingReset: String?
        var weeklyPercent: Double?
        var weeklyReset: String?
        var monthlyPercent: Double?
        var monthlyReset: String?
        
        for i in 0..<lines.count {
            let line = lines[i]
            
            // 匹配滚动用量
            if (line.contains("滚动") || line.lowercased().contains("rolling")) && i + 1 < lines.count {
                let nextLine = lines[i + 1]
                if let range = nextLine.range(of: "(\\d+)%", options: .regularExpression) {
                    let numStr = String(nextLine[range]).replacingOccurrences(of: "%", with: "")
                    rollingPercent = Double(numStr)
                    // 向下搜索重置时间
                    for j in (i + 2)..<min(i + 4, lines.count) {
                        if lines[j].contains("重置") || lines[j].lowercased().contains("reset") {
                            rollingReset = lines[j].replacingOccurrences(of: "重置于 ", with: "").replacingOccurrences(of: "重置于", with: "").trimmingCharacters(in: .whitespaces)
                            break
                        }
                    }
                }
            }
            // 匹配每周用量
            else if (line.contains("每周") || line.lowercased().contains("weekly")) && i + 1 < lines.count {
                let nextLine = lines[i + 1]
                if let range = nextLine.range(of: "(\\d+)%", options: .regularExpression) {
                    let numStr = String(nextLine[range]).replacingOccurrences(of: "%", with: "")
                    weeklyPercent = Double(numStr)
                    for j in (i + 2)..<min(i + 4, lines.count) {
                        if lines[j].contains("重置") || lines[j].lowercased().contains("reset") {
                            weeklyReset = lines[j].replacingOccurrences(of: "重置于 ", with: "").replacingOccurrences(of: "重置于", with: "").trimmingCharacters(in: .whitespaces)
                            break
                        }
                    }
                }
            }
            // 匹配每月用量
            else if (line.contains("每月") || line.lowercased().contains("monthly")) && i + 1 < lines.count {
                let nextLine = lines[i + 1]
                if let range = nextLine.range(of: "(\\d+)%", options: .regularExpression) {
                    let numStr = String(nextLine[range]).replacingOccurrences(of: "%", with: "")
                    monthlyPercent = Double(numStr)
                    for j in (i + 2)..<min(i + 4, lines.count) {
                        if lines[j].contains("重置") || lines[j].lowercased().contains("reset") {
                            monthlyReset = lines[j].replacingOccurrences(of: "重置于 ", with: "").replacingOccurrences(of: "重置于", with: "").trimmingCharacters(in: .whitespaces)
                            break
                        }
                    }
                }
            }
        }
        
        
        if rollingPercent != nil || weeklyPercent != nil || monthlyPercent != nil {
            return OpenCodeUsage(
                rollingPercent: rollingPercent,
                rollingReset: rollingReset,
                weeklyPercent: weeklyPercent,
                weeklyReset: weeklyReset,
                monthlyPercent: monthlyPercent,
                monthlyReset: monthlyReset
            )
        }
        
        return nil
    }
    // MARK: - 多轮提取
    private var extractionAttemptCount = 0
    private let maxExtractionAttempts = 3

    private func startExtractionLoop(webView: WKWebView) {
        extractionAttemptCount = 0
        
        // 先等 3 秒让页面 hydration
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, webView === self.fetchWebView else { return }
            self.performExtractionAttempt(webView: webView, delayIndex: 0)
        }
        
        // 再等 8 秒
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self, webView === self.fetchWebView else { return }
            self.performExtractionAttempt(webView: webView, delayIndex: 1)
        }
        
        // 最后等 15 秒
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, webView === self.fetchWebView else { return }
            self.performExtractionAttempt(webView: webView, delayIndex: 2)
        }
    }
    
    private func performExtractionAttempt(webView: WKWebView, delayIndex: Int) {
        extractionAttemptCount += 1
        
        // 1. 先看有没有拦截到的 API 数据
        if !capturedAPIData.isEmpty {
            print("📡 第\(extractionAttemptCount)次提取: 使用 API 数据")
            if let usage = parseCapturedAPIData() {
                finishFetch(usage: usage)
                return
            }
        }
        
        // 2. 看页面文本是否能解析出数据
        if !capturedPageText.isEmpty {
            print("📝 第\(extractionAttemptCount)次提取: 解析页面文本")
            if let usage = parseTextForUsageData() {
                finishFetch(usage: usage)
                return
            }
        }
        
        // 3. 用 JS 从 DOM 提取
        print("🔍 第\(extractionAttemptCount)次提取: 注入 JS 提取")
        extractData(webView: webView, isFinalAttempt: delayIndex >= 2)
    }
    
    // MARK: - WKNavigationDelegate（后台抓取）
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.fetchWebView else { return }
        
        webView.evaluateJavaScript("window.location.href") { [weak self] urlString, _ in
            guard let self = self else { return }
            
            let url = urlString as? String ?? ""
            
            // 检测是否是登录页 — 综合检查 URL 关键词
            let loginUrlKeywords = ["/auth/", "/login", "/signin", "/oauth", "/authorize", "openauth", "open-auth"]
            let isLoginPage = loginUrlKeywords.contains { url.contains($0.lowercased()) }
            
            if isLoginPage {
                print("⚠️ OpenCode 需要登录（检测到登录页 URL: \(url)）")
                self.finishFetch(usage: OpenCodeUsage(
                    usagePercentages: [],
                    bodyText: "",
                    useBalance: false,
                    needsLogin: true
                ))
                return
            }
            
            // 加载的是目标页面或其子页面，启动多轮提取
            print("✅ OpenCode 页面加载完成: \(url)")
            self.startExtractionLoop(webView: webView)
        }
    }
    
    private func extractData(webView: WKWebView, isFinalAttempt: Bool = false) {
        let extractJS = """
            (function() {
                try {
                    const result = {};
                    
                    // 1. 从拦截的 API 数据中找结构化信息
                    const captured = window.__ocCaptured || [];
                    for (const item of captured) {
                        try {
                            const parsed = JSON.parse(item.text);
                            if (parsed && typeof parsed === 'object') {
                                if (parsed.usagePercent !== undefined || parsed.resetInSec !== undefined || parsed.plan !== undefined || parsed.remaining !== undefined || parsed.totalLimit !== undefined) {
                                    result.apiData = parsed;
                                    break;
                                }
                                // 也可能是 [null, {...}] 格式
                                if (Array.isArray(parsed) && parsed.length >= 2) {
                                    const obj = parsed[1];
                                    if (obj && typeof obj === 'object' && (obj.usagePercent !== undefined || obj.remaining !== undefined || obj.plan !== undefined)) {
                                        result.apiData = obj;
                                        break;
                                    }
                                }
                            }
                        } catch(e) {}
                    }
                    
                    // 2. 提取页面文本中的用量信息
                    const bodyText = document.body ? document.body.innerText : '';
                    result.bodyText = bodyText.substring(0, 8000);
                    
                    // 把 bodyText 发送到 native 调试
                    try {
                        window.webkit.messageHandlers.openCodeData.postMessage({
                            data: bodyText.substring(0, 2000)
                        });
                    } catch(e) {}
                    // 3. 解析三种用量：滚动用量、每周用量、每月用量
                    // 先过滤空行
                    const cleanLines = bodyText.split('\n').map(l => l.trim()).filter(l => l.length > 0);
                    
                    for (let i = 0; i < cleanLines.length; i++) {
                        const line = cleanLines[i];
                        
                        // 匹配"滚动用量"或"Rolling"关键词
                        if (/滚动|rolling/i.test(line) && i + 1 < cleanLines.length) {
                            const pctMatch = cleanLines[i + 1].match(/(\\d+)%/);
                            if (pctMatch) {
                                result.rollingPercent = parseFloat(pctMatch[1]);
                                // 找重置时间
                                for (let j = i + 2; j < Math.min(i + 4, cleanLines.length); j++) {
                                    if (/重置|reset/i.test(cleanLines[j])) {
                                        result.rollingReset = cleanLines[j].replace(/重置于\\s*/, '').trim();
                                        break;
                                    }
                                }
                            }
                        }
                        // 匹配"每周用量"或"Weekly"关键词
                        else if (/每周|weekly/i.test(line) && i + 1 < cleanLines.length) {
                            const pctMatch = cleanLines[i + 1].match(/(\\d+)%/);
                            if (pctMatch) {
                                result.weeklyPercent = parseFloat(pctMatch[1]);
                                for (let j = i + 2; j < Math.min(i + 4, cleanLines.length); j++) {
                                    if (/重置|reset/i.test(cleanLines[j])) {
                                        result.weeklyReset = cleanLines[j].replace(/重置于\\s*/, '').trim();
                                        break;
                                    }
                                }
                            }
                        }
                        // 匹配"每月用量"或"Monthly"关键词
                        else if (/每月|monthly/i.test(line) && i + 1 < cleanLines.length) {
                            const pctMatch = cleanLines[i + 1].match(/(\\d+)%/);
                            if (pctMatch) {
                                result.monthlyPercent = parseFloat(pctMatch[1]);
                                for (let j = i + 2; j < Math.min(i + 4, cleanLines.length); j++) {
                                    if (/重置|reset/i.test(cleanLines[j])) {
                                        result.monthlyReset = cleanLines[j].replace(/重置于\\s*/, '').trim();
                                        break;
                                    }
                                }
                            }
                        }
                    }
                    
                    result.needsLogin = false;
                    result.url = window.location.href;
                    result.hasUsageData = bodyText.includes('%') || remaining !== null || plan !== null;
                    
                                        // 发送结果到 native
                    try {
                        window.webkit.messageHandlers.openCodeData.postMessage({
                            type: 'extract_result',
                            data: JSON.stringify(result)
                        });
                    } catch(e) {}
                    return JSON.stringify(result);
                } catch(e) {
                    return JSON.stringify({ error: e.message, needsLogin: false });
                }
            })()
        """
        
        webView.evaluateJavaScript(extractJS) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ OpenCode JS 执行失败: \(error.localizedDescription)")
                if isFinalAttempt {
                    self.finishFetch(usage: nil)
                }
                return
            }
            
            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if isFinalAttempt {
                    self.finishFetch(usage: nil)
                }
                return
            }
            
            UserDefaults.standard.synchronize()
            
            if parsed["error"] as? String != nil {
                print("❌ OpenCode JS 错误: \(parsed["error"] as? String ?? "")")
                if isFinalAttempt {
                    self.finishFetch(usage: nil)
                }
                return
            }
            
            // 检查是否从 API 数据中获取到了
            if let apiData = parsed["apiData"] as? [String: Any] {
                print("📡 JS 在 API 数据中找到结构化信息")
                let usage = OpenCodeUsage(
                    useBalance: apiData["useBalance"] as? Bool ?? false,
                    rpcUsagePercent: apiData["usagePercent"] as? Double,
                    rpcResetInSec: apiData["resetInSec"] as? Int,
                    rpcPlan: apiData["plan"] as? String,
                    rpcTotalUsed: apiData["totalUsed"] as? Int,
                    rpcTotalLimit: apiData["totalLimit"] as? Int,
                    rpcRemaining: apiData["remaining"] as? Int
                )
                self.finishFetch(usage: usage)
                return
            }
            
            
            // 从 DOM 中提取的数据
            let rollingPercent = parsed["rollingPercent"] as? Double
            let rollingReset = parsed["rollingReset"] as? String
            let weeklyPercent = parsed["weeklyPercent"] as? Double
            let weeklyReset = parsed["weeklyReset"] as? String
            let monthlyPercent = parsed["monthlyPercent"] as? Double
            let monthlyReset = parsed["monthlyReset"] as? String
            
            let hasThreeUsage = rollingPercent != nil || weeklyPercent != nil || monthlyPercent != nil
            
            if hasThreeUsage {
                print("📊 JS 提取到三种用量: rolling=\(rollingPercent ?? -1)%, weekly=\(weeklyPercent ?? -1)%, monthly=\(monthlyPercent ?? -1)%")
                let usage = OpenCodeUsage(
                    rollingPercent: rollingPercent,
                    rollingReset: rollingReset,
                    weeklyPercent: weeklyPercent,
                    weeklyReset: weeklyReset,
                    monthlyPercent: monthlyPercent,
                    monthlyReset: monthlyReset
                )
                self.finishFetch(usage: usage)
                return
            }
            
            // 最终尝试也没数据
            if isFinalAttempt {
                print("⚠️ OpenCode 多次提取均未找到数据")
                let usage = OpenCodeUsage(
                    usagePercentages: parsed["usagePercentages"] as? [Int] ?? [],
                    bodyText: parsed["bodyText"] as? String ?? "",
                    useBalance: parsed["useBalance"] as? Bool ?? false,
                    needsLogin: false
                )
                self.finishFetch(usage: usage)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.fetchWebView else { return }
        print("❌ OpenCode 导航失败: \(error.localizedDescription)")
        finishFetch(usage: nil)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.fetchWebView else { return }
        print("❌ OpenCode 初始导航失败: \(error.localizedDescription)")
        finishFetch(usage: nil)
    }
}
