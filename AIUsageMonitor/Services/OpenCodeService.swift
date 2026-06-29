import AppKit
import WebKit
import Foundation

// MARK: - OpenCode 服务

class OpenCodeService: NSObject, NSWindowDelegate {
    
    static let shared = OpenCodeService()
    
    private let rpcClient = OpenCodeRPCClient()
    private let webScraper = OpenCodeWebViewScraper()
    private let loginDelegate = LoginWindowNavigationDelegate()
    private var loginPanel: NSPanel?
    
    // 预创建的 WKWebView（复用，避免每次都重新启动 WebContent 进程）
    private lazy var loginWebView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        wv.navigationDelegate = self.loginDelegate
        return wv
    }()
    
    // MARK: - 获取用量数据（入口）
    
    func fetchUsage(urlString: String) async -> OpenCodeUsage? {
        let ocURL = URL(string: "https://opencode.ai")!
        let httpCookies = HTTPCookieStorage.shared.cookies(for: ocURL) ?? []
        var allCookies: [HTTPCookie] = httpCookies
        
        if httpCookies.isEmpty {
            let wkCookies = await rpcClient.getCookies(for: "opencode.ai")
            allCookies = wkCookies
            if wkCookies.isEmpty {
                return OpenCodeUsage(needsLogin: true, status: .noCookies)
            }
        }
        
        // 并行获取：RPC 数据 + 页面文本
        let workspaceID = rpcClient.extractWorkspaceID(from: urlString)
        
        async let rpcResult: OpenCodeRPCResponse? = tryRPC(workspaceID: workspaceID)
        
        async let pageResult: OpenCodeUsage? = fetchPageViaURLSession(urlString: urlString, cookies: allCookies)
        
        let rpcData = await rpcResult
        let pageUsage = await pageResult
        
        // 优先使用 RPC 数据（含 resetInSec），再补充页面提取的百分比
        if let rpc = rpcData, rpc.usagePercent != nil || rpc.remaining != nil || rpc.plan != nil || rpc.resetInSec != nil {
            print("✅ OpenCode RPC: \(rpc)")
            var usage = OpenCodeUsage(
                useBalance: rpc.useBalance ?? false,
                rpcUsagePercent: rpc.usagePercent,
                rpcResetInSec: rpc.resetInSec,
                rpcPlan: rpc.plan,
                rpcTotalUsed: rpc.totalUsed,
                rpcTotalLimit: rpc.totalLimit,
                rpcRemaining: rpc.remaining
            )
            usage.status = .success
            return usage
        }
        
        // RPC 失败 → 用页面文本数据
        if let page = pageUsage, page.rollingPercent != nil || page.weeklyPercent != nil || page.monthlyPercent != nil {
            print("✅ OpenCode 页面文本数据: \(page)")
            var result = page
            result.status = .success
            
            // 如果页面文本没拿到 resetInSec，用轻量 WebView 补充（快速抓取 RPC）
            if result.rpcResetInSec == nil || result.rpcResetInSec == 0 {
                print("⏳ 补充: WebView 快速抓取 RPC 数据...")
                webScraper.defaultTimeout = 8
                if let webResult = await webScraper.fetchUsageViaWebView(urlString: urlString),
                   let secs = webResult.rpcResetInSec, secs > 0 {
                    result.rpcResetInSec = secs
                    print("✅ WebView 补充 resetInSec: \(secs)秒")
                }
            }
            return result
        }
        
        // URLSession 失败 → 回退到 WebView 抓取
        print("⏳ OpenCode 回退到 WebView 抓取（15 秒超时）")
        webScraper.defaultTimeout = 15
        let result = await webScraper.fetchUsageViaWebView(urlString: urlString)
        
        guard let r = result else {
            return OpenCodeUsage(needsLogin: true, status: .fetchFailed)
        }
        
        let hasData = r.rpcUsagePercent != nil || r.rpcRemaining != nil || r.rpcPlan != nil
            || r.rollingPercent != nil || r.weeklyPercent != nil || r.monthlyPercent != nil
        
        if hasData {
            var res = r
            res.status = .success
            return res
        }
        
        if r.needsLogin {
            return OpenCodeUsage(needsLogin: true, status: .noCookies)
        }
        
        return OpenCodeUsage(needsLogin: true, status: .fetchFailed)
    }
    
    // MARK: - OpenCode 数据获取优化
    
    /// RPC 调用（仅当 workspaceID 有效时）
    private func tryRPC(workspaceID: String?) async -> OpenCodeRPCResponse? {
        guard let wid = workspaceID else { return nil }
        return await rpcClient.callUsagePreviewRPC(workspaceID: wid)
    }
    
    // MARK: - URLSession 直接请求页面（不依赖 WKWebView）
    
    private func fetchPageViaURLSession(urlString: String, cookies: [HTTPCookie]) async -> OpenCodeUsage? {
        guard let url = URL(string: urlString) else { return nil }
        
        // 把 WKWebView 的 cookie 存入 shared 存储，URLSession 会自动使用
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = true
        
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResp = response as? HTTPURLResponse,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        print("📄 URLSession 状态码: \(httpResp.statusCode), 页面: \(html.count) 字节")
        
        // 检查是否被重定向到登录页
        if let finalURL = httpResp.url?.absoluteString {
            print("📄 最终 URL: \(finalURL)")
            if finalURL.contains("/auth/") || finalURL.contains("/login") || finalURL.contains("/authorize") {
                print("⚠️ OpenCode 被重定向到登录页")
                return OpenCodeUsage(needsLogin: true, status: .noCookies)
            }
        }
        
        // 在 HTML 中搜索用量数据 - 直接文本搜索
        let bodyText = stripHTML(html)
        print("📄 文本内容(前500): \(bodyText.prefix(500))")
        
        // 所有可能的匹配模式
        if var usage = findUsageData(in: bodyText) {
            print("📊 文本提取结果: rolling=\(usage.rollingPercent ?? -1) weekly=\(usage.weeklyPercent ?? -1) monthly=\(usage.monthlyPercent ?? -1) resetSec=\(usage.rpcResetInSec ?? -1)")
            // 如果文本提取到了百分比但没倒计时，再从 HTML JSON 中补充
            if usage.rpcResetInSec == nil || usage.rpcResetInSec == 0 {
                if let jsonData = extractJSONFromHTML(html) {
                    print("📊 JSON 数据: \(jsonData)")
                    if let secs = jsonData["resetInSec"] as? Int, secs > 0 {
                        usage.rpcResetInSec = secs
                        print("📊 JSON 补充 resetInSec: \(secs)秒")
                    }
                }
            }
            return usage
        }
        
        // 文本解析失败 → 尝试 JSON
        if let jsonData = extractJSONFromHTML(html) {
            let pct = jsonData["usagePercent"] as? Double
            let secs = jsonData["resetInSec"] as? Int
            let remaining = jsonData["remaining"] as? Int
            let plan = jsonData["plan"] as? String
            if pct != nil || secs != nil || remaining != nil || plan != nil {
                print("📊 JSON 直接解析成功")
                return OpenCodeUsage(
                    rpcUsagePercent: pct,
                    rpcResetInSec: secs,
                    rpcPlan: plan,
                    rpcRemaining: remaining
                )
            }
        }
        
        return OpenCodeUsage(needsLogin: true, status: .fetchFailed)
    }
    
    private func findUsageData(in text: String) -> OpenCodeUsage? {
        var rollingPercent: Double?
        var weeklyPercent: Double?
        var monthlyPercent: Double?
        var rollingReset: String?
        var weeklyReset: String?
        var monthlyReset: String?
        var rpcResetInSec: Int?
        
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        // 第一遍：提取三个用量百分比
        for i in 0..<lines.count {
            let line = lines[i]
            let keywords = ["滚动", "rolling", "每周", "weekly", "每月", "monthly", "用量", "usage", "剩余", "remaining", "已用", "used", "limit", "额度"]
            let hasKeyword = keywords.contains { line.localizedCaseInsensitiveContains($0) }
            
            if hasKeyword {
                // 当前行或下一行找百分比
                for checkLine in [line, i+1 < lines.count ? lines[i+1] : ""] {
                    if let regex = try? NSRegularExpression(pattern: "(\\d+(\\.\\d+)?)%"),
                       let match = regex.firstMatch(in: checkLine, range: NSRange(location: 0, length: checkLine.utf16.count)),
                       let range = Range(match.range(at: 1), in: checkLine) {
                        let val = Double(checkLine[range]) ?? 0
                        if line.localizedCaseInsensitiveContains("滚动") || line.localizedCaseInsensitiveContains("rolling") {
                            rollingPercent = val
                        } else if line.localizedCaseInsensitiveContains("每周") || line.localizedCaseInsensitiveContains("weekly") {
                            weeklyPercent = val
                        } else if line.localizedCaseInsensitiveContains("每月") || line.localizedCaseInsensitiveContains("monthly") {
                            monthlyPercent = val
                        } else if rollingPercent == nil {
                            rollingPercent = val
                        }
                    }
                }
            }
        }
        
        // 第二遍：按页面中出现的顺序提取所有重置时间，依次分配给滚动/每周/每月
        var resetIndex = 0
        for line in lines {
            if line.localizedCaseInsensitiveContains("重置") || line.localizedCaseInsensitiveContains("剩余") {
                let cleanTL = line
                    .replacingOccurrences(of: "重置于", with: "")
                    .replacingOccurrences(of: "重置", with: "")
                    .replacingOccurrences(of: "剩余", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !cleanTL.isEmpty {
                    if resetIndex == 0 { rollingReset = cleanTL }
                    else if resetIndex == 1 { weeklyReset = cleanTL }
                    else if resetIndex == 2 { monthlyReset = cleanTL }
                    resetIndex += 1
                    
                    // 同时计算总秒数
                    var totalSec = 0
                    if let dMatch = try? NSRegularExpression(pattern: "(\\d+)\\s*(天|day)", options: .caseInsensitive),
                       let m = dMatch.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)),
                       let dr = Range(m.range(at: 1), in: line) {
                        totalSec += (Int(line[dr]) ?? 0) * 86400
                    }
                    if let hMatch = try? NSRegularExpression(pattern: "(\\d+)\\s*(小时|hour|h|hr)", options: .caseInsensitive),
                       let m = hMatch.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)),
                       let hr = Range(m.range(at: 1), in: line) {
                        totalSec += (Int(line[hr]) ?? 0) * 3600
                    }
                    if let mMatch = try? NSRegularExpression(pattern: "(\\d+)\\s*(分钟|min|m)(?!o)", options: .caseInsensitive),
                       let m = mMatch.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)),
                       let mr = Range(m.range(at: 1), in: line) {
                        totalSec += (Int(line[mr]) ?? 0) * 60
                    }
                    if totalSec > 0 { rpcResetInSec = totalSec }
                }
            }
        }
        
        if rollingPercent != nil || weeklyPercent != nil || monthlyPercent != nil {
            return OpenCodeUsage(
                rpcResetInSec: rpcResetInSec,
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
    
    // MARK: - HTML 解析
    
    private func extractJSONFromHTML(_ html: String) -> [String: Any]? {
        // 先在 HTML 中搜索 resetInSec / usagePercent 等关键字段
        let knownKeys = ["resetInSec", "usagePercent", "remaining", "plan", "totalLimit", "totalUsed", "useBalance"]
        
        // 搜索包含这些字段的 JSON 对象: { "key": value, ... }
        for key in knownKeys {
            let pattern = "\\\"\(key)\\\"\\s*:\\s*(\\d+(\\.\\d+)?|true|false|\\\"[^\\\"]*\\\")"
            if let _ = html.range(of: pattern, options: .regularExpression) {
                // 找到了已知字段 → 尝试提取整个 JSON 块
                // 往前找 { 或 [，往后匹配到对应的 } 或 ]
                break
            }
        }
        
        // 搜索 script 标签内的完整 JSON 对象
        let jsonPatterns = [
            "window\\.__[A-Z_]+__\\s*=\\s*(\\{.+?\\});",
            "\"usagePercent\"\\s*:\\s*[\\d.]+[^}]+\\}",
            "\\{[^}]*\"resetInSec\"[^}]*\\}",
            "\\{[^}]*\"usagePercent\"[^}]*\\}",
        ]
        
        for pattern in jsonPatterns {
            if let range = html.range(of: pattern, options: .regularExpression) {
                let jsonStr = String(html[range])
                // 提取 JSON 部分 (去掉 var name = 前缀)
                var cleaned = jsonStr
                if let eqRange = jsonStr.range(of: "=") {
                    cleaned = String(jsonStr[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                // 去掉末尾的 ;
                if cleaned.hasSuffix(";") { cleaned = String(cleaned.dropLast()) }
                // 去掉尾部冗余
                if let closeIdx = cleaned.lastIndex(of: "}") {
                    cleaned = String(cleaned[...closeIdx])
                }
                if let data = cleaned.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("📊 JSON 解析成功: \(json)")
                    return json
                }
            }
        }
        
        // 最后尝试: 直接搜索 resetInSec 数字
        if let resetRange = html.range(of: "\"resetInSec\"\\s*:\\s*(\\d+)", options: .regularExpression),
           let colonRange = html[resetRange].range(of: ":") {
            let numStr = html[resetRange][colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
            if let secs = Int(numStr) {
                print("📊 直接提取 resetInSec: \(secs)")
                return ["resetInSec": secs]
            }
        }
        
        return nil
    }
    
    private func stripHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
              let text = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) else {
            // 简单正则剥离
            let noTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            return noTags.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.string
    }
    
    private func parseTextForUsage(_ text: String) -> OpenCodeUsage? {
        // 找百分比和数字模式
        var rollingPercent: Double?
        var weeklyPercent: Double?
        var monthlyPercent: Double?
        
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        for i in 0..<lines.count {
            let line = lines[i]
            
            if line.localizedCaseInsensitiveContains("滚动") || line.localizedCaseInsensitiveContains("rolling") {
                if i + 1 < lines.count,
                   let regex = try? NSRegularExpression(pattern: "(\\d+)%"),
                   let match = regex.firstMatch(in: lines[i+1], range: NSRange(location: 0, length: lines[i+1].utf16.count)),
                   let range = Range(match.range(at: 1), in: lines[i+1]) {
                    rollingPercent = Double(lines[i+1][range])
                }
            }
            if line.localizedCaseInsensitiveContains("每周") || line.localizedCaseInsensitiveContains("weekly") {
                if i + 1 < lines.count,
                   let regex = try? NSRegularExpression(pattern: "(\\d+)%"),
                   let match = regex.firstMatch(in: lines[i+1], range: NSRange(location: 0, length: lines[i+1].utf16.count)),
                   let range = Range(match.range(at: 1), in: lines[i+1]) {
                    weeklyPercent = Double(lines[i+1][range])
                }
            }
            if line.localizedCaseInsensitiveContains("每月") || line.localizedCaseInsensitiveContains("monthly") {
                if i + 1 < lines.count,
                   let regex = try? NSRegularExpression(pattern: "(\\d+)%"),
                   let match = regex.firstMatch(in: lines[i+1], range: NSRange(location: 0, length: lines[i+1].utf16.count)),
                   let range = Range(match.range(at: 1), in: lines[i+1]) {
                    monthlyPercent = Double(lines[i+1][range])
                }
            }
        }
        
        if rollingPercent != nil || weeklyPercent != nil || monthlyPercent != nil {
            print("📊 文本解析成功: \(rollingPercent ?? -1)% / \(weeklyPercent ?? -1)% / \(monthlyPercent ?? -1)%")
            return OpenCodeUsage(
                rollingPercent: rollingPercent,
                weeklyPercent: weeklyPercent,
                monthlyPercent: monthlyPercent
            )
        }
        
        return nil
    }
    
    // MARK: - WKWebView 登录（复用已初始化的 WKWebView，启动快）
    
    func showLoginWindow(urlString: String, completion: @escaping (Bool) -> Void) {
        if let existing = loginPanel {
            existing.close()
            loginPanel = nil
        }
        
        // WKWebView 已预创建并初始化（loginWebView lazy），直接复用
        let webView = loginWebView
        
        // 重置状态
        loginDelegate.loginAlreadyDetected = false
        loginDelegate.onLoginSuccess = { [weak self] in
            DispatchQueue.main.async {
                self?.loginPanel?.close()
                self?.loginPanel = nil
                completion(true)
            }
        }
        loginDelegate.onLoginFailed = { [weak self] in
            DispatchQueue.main.async {
                self?.loginPanel?.close()
                self?.loginPanel = nil
                completion(false)
            }
        }
        webView.navigationDelegate = loginDelegate
        
        // 创建面板（快速，WKWebView 已就绪）
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "OpenCode 登录"
        panel.contentView = webView
        panel.center()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        
        self.loginPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSWindow,
              panel === self.loginPanel else { return }
        self.loginPanel = nil
        if !loginDelegate.loginAlreadyDetected {
            loginDelegate.onLoginFailed?()
        }
    }
    
    // MARK: - 浏览器登录（备用）
    
    func closeLoginWindow() {
        loginPanel?.close()
        loginPanel = nil
    }
    
    func openLoginInBrowser(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        print("🌐 已在系统浏览器中打开: \\(urlString)")
    }
}
