import Foundation
import WebKit
import AppKit

// MARK: - 登录窗口的导航代理

class LoginWindowNavigationDelegate: NSObject, WKNavigationDelegate {
    var onLoginSuccess: (() -> Void)?
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.location.href") { urlString, _ in
            if let url = urlString as? String {
                if url.contains("/workspace/") {
                    print("✅ OpenCode 登录成功！")
                    if let window = webView.window {
                        window.close()
                    }
                    NotificationCenter.default.post(name: .openCodeLoginSuccess, object: nil)
                    self.onLoginSuccess?()
                }
            }
        }
    }
}

extension Notification.Name {
    static let openCodeLoginSuccess = Notification.Name("openCodeLoginSuccess")
    static let openCodeDataRefreshed = Notification.Name("openCodeDataRefreshed")
}
