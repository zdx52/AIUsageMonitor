import AppKit
import WebKit
import Foundation

// MARK: - OpenCode 服务

class OpenCodeService: NSObject, NSWindowDelegate {
    
    static let shared = OpenCodeService()
    
    private let rpcClient = OpenCodeRPCClient()
    private let webScraper = OpenCodeWebViewScraper()
    private let loginDelegate = LoginWindowNavigationDelegate()
    private var fetchLoginWindow: NSWindow?
    
    // MARK: - 获取用量数据（入口）
    
    func fetchUsage(urlString: String) async -> OpenCodeUsage? {
        // 检查 HTTPCookieStorage
        let ocURL = URL(string: "https://opencode.ai")!
        let httpCookies = HTTPCookieStorage.shared.cookies(for: ocURL) ?? []
        
        if httpCookies.isEmpty {
            // 再检查 WKWebView cookie store
            let wkCookies = await rpcClient.getCookies(for: "opencode.ai")
            if wkCookies.isEmpty {
                return OpenCodeUsage(needsLogin: true, status: .noCookies)
            }
        }
        
        let workspaceID = rpcClient.extractWorkspaceID(from: urlString)
        
        // 2. 先试 RPC
        if let wid = workspaceID, let rpcData = await rpcClient.callUsagePreviewRPC(workspaceID: wid) {
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
        
        // 3. RPC 失败，快速检查页面是否为登录页
        print("⚠️ OpenCode RPC 失败，快速检查登录状态")
        let isLogin = await checkIsLoginPage(urlString: urlString)
        
        if isLogin == true {
            // 是登录页 → cookie 过期
            return OpenCodeUsage(needsLogin: true, status: .noCookies)
        }
        
        // 4. 不是登录页（已登录）但 RPC 失败 → 用 WebView 抓取数据（10 秒超时）
        print("⚠️ OpenCode 已登录但 RPC 失败，尝试 WebView 抓取")
        webScraper.defaultTimeout = 10
        let webViewResult = await webScraper.fetchUsageViaWebView(urlString: urlString)
        
        if let result = webViewResult {
            let hasData = result.rpcUsagePercent != nil || result.rpcRemaining != nil || result.rpcPlan != nil
                || result.rollingPercent != nil || result.weeklyPercent != nil || result.monthlyPercent != nil
            if hasData {
                var r = result
                r.status = .success
                print("✅ OpenCode WebView 抓取成功")
                return r
            }
        }
        
        print("❌ OpenCode 所有获取方式均失败")
        return OpenCodeUsage(needsLogin: true, status: .fetchFailed)
    }
    
    // MARK: - 快速登录页检测（WKWebView 8 秒超时）
    
    /// 轻量 WKWebView 导航代理，仅用于检查页面是否为登录页
    class QuickLoginChecker: NSObject, WKNavigationDelegate {
        var onResult: ((Bool) -> Void)?
        var done = false
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !done else { return }
            done = true
            let url = webView.url?.absoluteString ?? ""
            let isLogin = url.contains("/auth/") || url.contains("/login") || url.contains("/signin")
            print("📡 OpenCode 页面检查: \(url.prefix(80)) → isLogin=\(isLogin)")
            webView.stopLoading()
            onResult?(isLogin)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !done else { return }
            done = true
            onResult?(false)
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !done else { return }
            done = true
            onResult?(false)
        }
    }
    
    private func checkIsLoginPage(urlString: String) async -> Bool? {
        guard let url = URL(string: urlString) else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let config = WKWebViewConfiguration()
                config.websiteDataStore = WKWebsiteDataStore.default()
                let webView = WKWebView(frame: .zero, configuration: config)
                webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
                
                let checker = QuickLoginChecker()
                checker.onResult = { isLogin in
                    continuation.resume(returning: isLogin)
                }
                webView.navigationDelegate = checker
                
                // 8 秒超时
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    if !checker.done {
                        checker.done = true
                        webView.stopLoading()
                        continuation.resume(returning: nil)
                    }
                }
                
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    // MARK: - WKWebView 登录窗口
    
    func showLoginWindow(urlString: String, completion: @escaping (Bool) -> Void) {
        // 关闭已有窗口
        if let existingWindow = fetchLoginWindow {
            existingWindow.close()
            fetchLoginWindow = nil
        }
        
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        // 设置桌面版 User Agent，部分站点需要
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        
        // 登录成功或失败时都回调
        loginDelegate.onLoginSuccess = { [weak self] in
            self?.fetchLoginWindow = nil
            completion(true)
        }
        loginDelegate.onLoginFailed = { [weak self] in
            self?.fetchLoginWindow = nil
            completion(false)
        }
        webView.navigationDelegate = loginDelegate
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenCode 登录"
        window.contentView = webView
        window.center()
        // 菜单栏应用(.accessory)需要显式激活才能显示窗口
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        fetchLoginWindow = window
        
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === self.fetchLoginWindow else { return }
        print("🔒 OpenCode 登录窗口被用户关闭")
        self.fetchLoginWindow = nil
        // 登录已自动检测成功时，不触发失败回调
        if !loginDelegate.loginAlreadyDetected {
            self.loginDelegate.onLoginFailed?()
        }
    }
    
    // MARK: - 在系统浏览器中打开（备用）
    
    func closeLoginWindow() {
        if let window = fetchLoginWindow {
            window.close()
        }
        fetchLoginWindow = nil
    }
    
    func openInBrowser(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        print("🌐 已打开系统浏览器: \(urlString)")
    }
}
