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
        
        // 3. RPC 失败，回退到 WKWebView 页面抓取
        print("⚠️ OpenCode RPC 失败，回退到页面抓取")
        let webViewResult = await webScraper.fetchUsageViaWebView(urlString: urlString)
        
        if let result = webViewResult {
            let hasData = result.rpcUsagePercent != nil || result.rpcRemaining != nil || result.rpcPlan != nil
                || result.rollingPercent != nil || result.weeklyPercent != nil || result.monthlyPercent != nil
            if hasData {
                var r = result
                r.status = .success
                return r
            }
            var r = result
            r.status = .fetchFailed
            return r
        }
        
        print("❌ OpenCode 所有获取方式均失败")
        return OpenCodeUsage(needsLogin: true, status: .fetchFailed)
    }
    
    // MARK: - WKWebView 登录窗口
    
    func showLoginWindow(urlString: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 关闭已有窗口
            if let existingWindow = self.fetchLoginWindow {
                existingWindow.close()
                self.fetchLoginWindow = nil
            }
            
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore.default()
            
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
            
            // 登录成功或失败时都回调
            self.loginDelegate.onLoginSuccess = {
                self.fetchLoginWindow = nil
                completion(true)
            }
            self.loginDelegate.onLoginFailed = {
                self.fetchLoginWindow = nil
                completion(false)
            }
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
            window.delegate = self
            
            self.fetchLoginWindow = window
            
            if let url = URL(string: urlString) {
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === self.fetchLoginWindow else { return }
        print("🔒 OpenCode 登录窗口被用户关闭")
        self.fetchLoginWindow = nil
        self.loginDelegate.onLoginFailed?()
    }
    
    // MARK: - 在系统浏览器中打开（备用）
    
    func openInBrowser(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        print("🌐 已打开系统浏览器: \(urlString)")
    }
}
