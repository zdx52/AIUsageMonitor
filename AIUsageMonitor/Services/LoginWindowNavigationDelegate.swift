import Foundation
import WebKit
import AppKit

// MARK: - 登录窗口的导航代理

class LoginWindowNavigationDelegate: NSObject, WKNavigationDelegate {
    var onLoginSuccess: (() -> Void)?
    var onLoginFailed: (() -> Void)?
    private var loginCheckTimer: Timer?
    private var webView: WKWebView?
    var loginAlreadyDetected = false  // 防止 windowWillClose 重复回调
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url?.absoluteString {
            print("🌐 OpenCode 开始加载: \(url)")
        }
        // 更新窗口标题为正在加载
        webView.window?.title = "OpenCode 登录 - 加载中..."
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.webView = webView
        print("🌐 OpenCode 页面加载完成: \(webView.url?.absoluteString ?? "?")")
        
        // 延迟一点检查，确保页面完全渲染
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkLoginStatus(webView: webView)
        }
        
        // 启动定时器轮询检测登录状态（防止客户端路由不触发 didFinish）
        startLoginPolling(webView: webView)
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        // 跟踪服务器端重定向
        if let url = webView.url?.absoluteString {
            print("🔀 OpenCode 重定向: \(url)")
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ OpenCode 子页面加载失败: \(error.localizedDescription)")
        webView.window?.title = "OpenCode 登录 - 加载失败: \(error.localizedDescription)"
        // 不中断登录流程，子页面加载失败不影响整体 OAuth 流程
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ OpenCode 页面跳转失败: \(error.localizedDescription)")
        webView.window?.title = "OpenCode 登录 - 连接失败: \(error.localizedDescription)"
        // 在页面中显示错误和浏览器备选方案
        let errorHTML = """
        <html><body style="font-family:-apple-system;padding:40px;text-align:center;background:#f5f5f5">
        <h2 style="color:#888">⚠️ 页面加载失败</h2>
        <p style="color:#666;font-size:14px">\(error.localizedDescription)</p>
        <p style="color:#999;font-size:12px;margin-top:20px">请尝试在系统浏览器中登录</p>
        </body></html>
        """
        webView.loadHTMLString(errorHTML, baseURL: nil)
    }
    
    private func checkLoginStatus(webView: WKWebView) {
        // 方法1: 检查 URL 是否包含 workspace
        if let url = webView.url?.absoluteString {
            if url.contains("/workspace/") {
                print("✅ OpenCode 登录成功！（URL 检测）")
                onLoginDetected(webView: webView)
                return
            }
        }
        
        // 方法2: 检查是否已从 auth 页面跳转回 opencode.ai，且有 cookie
        if let url = webView.url?.absoluteString {
            let isOnOAuthPage = url.contains("/auth/") || url.contains("/login") || url.contains("/signin")
                || url.contains("/authorize") || url.contains("openauth")
            
            if !isOnOAuthPage && url.contains("opencode.ai") {
                // 已离开登录页且回到了 opencode.ai → 检查 cookie
                checkCookiesAndConfirm(webView: webView)
            }
        }
    }
    
    private func checkCookiesAndConfirm(webView: WKWebView) {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            let hasAnyCookie = cookies.contains { $0.domain.contains("opencode.ai") }
            
            if hasAnyCookie {
                // 有 cookie 说明登录成功
                print("✅ OpenCode 登录成功！（Cookie 检测）")
                self.onLoginDetected(webView: webView)
            }
        }
    }
    
    private func startLoginPolling(webView: WKWebView) {
        loginCheckTimer?.invalidate()
        loginCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // 检查 URL
            if let url = webView.url?.absoluteString {
                if url.contains("/workspace/") {
                    print("✅ OpenCode 登录成功！（轮询检测）")
                    self.onLoginDetected(webView: webView)
                    return
                }
            }
            
            // 尝试执行 JS 检测页面内容是否包含用量数据
            webView.evaluateJavaScript("document.body?.innerText?.includes('%') ?? false") { [weak self] result, _ in
                guard let self = self,
                      let hasPercent = result as? Bool,
                      hasPercent else { return }
                
                // 页面内容包含 % 符号，可能是用量数据
                if let url = webView.url?.absoluteString,
                   url.contains("opencode.ai") {
                    print("✅ OpenCode 登录成功！（页面数据检测）")
                    self.onLoginDetected(webView: webView)
                }
            }
        }
    }
    
    private func onLoginDetected(webView: WKWebView) {
        loginAlreadyDetected = true
        cleanup()
        
        // 立即将 WKWebView 的 cookie 同步到 HTTPCookieStorage
        // 确保后续 refreshAll 能直接找到 cookie
        let panelWindow = webView.window
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies where cookie.domain.contains("opencode.ai") {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            DispatchQueue.main.async {
                panelWindow?.close()
                NotificationCenter.default.post(name: .openCodeLoginSuccess, object: nil)
                self.onLoginSuccess?()
            }
        }
    }
    
    private func handleLoginFailed() {
        cleanup()
        NotificationCenter.default.post(name: .openCodeLoginFailed, object: nil)
        onLoginFailed?()
    }
    
    private func cleanup() {
        loginCheckTimer?.invalidate()
        loginCheckTimer = nil
        webView = nil
    }
    
    deinit {
        cleanup()
    }
}

extension Notification.Name {
    static let openCodeLoginSuccess = Notification.Name("openCodeLoginSuccess")
    static let openCodeLoginFailed = Notification.Name("openCodeLoginFailed")
    static let openCodeDataRefreshed = Notification.Name("openCodeDataRefreshed")
}
