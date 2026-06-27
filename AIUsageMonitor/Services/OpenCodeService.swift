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
        
        // 有 cookie → 直接用 URLSession 请求页面 HTML（比 WKWebView 快且可靠）
        if let result = await fetchPageViaURLSession(urlString: urlString, cookies: allCookies) {
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
        if let usage = findUsageData(in: bodyText) {
            return usage
        }
        
        return OpenCodeUsage(needsLogin: true, status: .fetchFailed)
    }
    
    private func findUsageData(in text: String) -> OpenCodeUsage? {
        var rollingPercent: Double?
        var weeklyPercent: Double?
        var monthlyPercent: Double?
        
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
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
        
        if rollingPercent != nil || weeklyPercent != nil || monthlyPercent != nil {
            return OpenCodeUsage(rollingPercent: rollingPercent, weeklyPercent: weeklyPercent, monthlyPercent: monthlyPercent)
        }
        return nil
    }
    
    // MARK: - HTML 解析
    
    private func extractJSONFromHTML(_ html: String) -> [String: Any]? {
        // 查找 __NEXT_DATA__ 或类似的内嵌 JSON
        // SolidJS 可能把初始状态放在 script 标签中
        let patterns = [
            "window.__INITIAL_STATE__\\s*=\\s*(\\{.+?\\});",
            "window.__DATA__\\s*=\\s*(\\{.+?\\});",
            "<script[^>]*>\\s*window\\.__[A-Z_]+__\\s*=\\s*(\\{.+?\\})\\s*<\\/script>",
            "\"usagePercent\":\\s*([\\d.]+)",
            "\"remaining\":\\s*(\\d+)",
            "\"plan\":\\s*\"([^\"]+)\"",
        ]
        
        for pattern in patterns {
            if let range = html.range(of: pattern, options: .regularExpression) {
                let match = String(html[range])
                print("📊 匹配到: \(match.prefix(100))")
            }
        }
        
        // 更简单的: 搜索 { 开始 } 结束的 JSON
        guard let startIdx = html.range(of: "\\{")?.lowerBound,
              let endIdx = html.range(of: "\\}")?.upperBound else { return nil }
        
        return nil
    }
    
    private func parseCapturedJSON(_ json: [String: Any]) -> OpenCodeUsage? {
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
