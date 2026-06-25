import AppKit
import WebKit
import Foundation

// MARK: - OpenCode 服务（编排 RPC + WebView 回退）

class OpenCodeService: NSObject {
    
    static let shared = OpenCodeService()
    
    private let rpcClient = OpenCodeRPCClient()
    private let webScraper = OpenCodeWebViewScraper()
    private let loginDelegate = LoginWindowNavigationDelegate()
    private var fetchLoginWindow: NSWindow?

    // MARK: - 获取用量数据（入口）
    
    func fetchUsage(urlString: String) async -> OpenCodeUsage? {
        
        // 同步检查 HTTPCookieStorage（WKWebView 登录后 cookie 会同步到这里）
        let ocURL = URL(string: "https://opencode.ai")!
        let httpCookies = HTTPCookieStorage.shared.cookies(for: ocURL) ?? []
        
        if httpCookies.isEmpty {
            return OpenCodeUsage(needsLogin: true, status: .noCookies)
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
        
        // 4. 全部失败
        print("❌ OpenCode 所有获取方式均失败")
        return OpenCodeUsage(needsLogin: true, status: .fetchFailed)
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
}
