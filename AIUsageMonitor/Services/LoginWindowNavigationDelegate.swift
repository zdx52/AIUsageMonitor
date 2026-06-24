import Foundation
import WebKit
import AppKit

// MARK: - 登录窗口的导航代理

class LoginWindowNavigationDelegate: NSObject, WKNavigationDelegate {
    var onLoginSuccess: (() -> Void)?
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 提前捕获回调，避免闭包强持有 self
        let onSuccess = self.onLoginSuccess
        webView.evaluateJavaScript("window.location.href") { [weak self] urlString, _ in
            guard let self = self else { return }
            if let url = urlString as? String {
                if url.contains("/workspace/") {
                    print("✅ OpenCode 登录成功！")
                    if let window = webView.window {
                        window.close()
                    }
                    NotificationCenter.default.post(name: .openCodeLoginSuccess, object: nil)
                    onSuccess?()
                }
            }
        }
    }
}

extension Notification.Name {
    static let openCodeLoginSuccess = Notification.Name("openCodeLoginSuccess")
    static let openCodeDataRefreshed = Notification.Name("openCodeDataRefreshed")
}
