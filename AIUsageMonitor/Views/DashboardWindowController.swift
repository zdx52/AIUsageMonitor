import SwiftUI
import WebKit

// MARK: - Hindsight 原生看板窗口控制器

class DashboardWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    
    static let shared = DashboardWindowController()
    
    private var webView: WKWebView?
    
    func show() {
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        createWindow()
    }
    
    private func createWindow() {
        let config = WKWebViewConfiguration()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        self.webView = webView
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Hindsight 看板"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        window.contentView = webView
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        
        loadDashboard()
    }
    
    private func loadDashboard() {
        guard let webView = self.webView else { return }
        let t = Int(Date().timeIntervalSince1970 * 1000)
        if let url = URL(string: "http://localhost:9999/?_t=\(t)") {
            webView.load(URLRequest(url: url))
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ Hindsight 原生看板加载完成")
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ 看板加载失败: \(error.localizedDescription)")
        retryLoad()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ 看板加载失败(预加载): \(error.localizedDescription)")
        retryLoad()
    }
    
    private var retryCount = 0
    private func retryLoad() {
        let delay = min(1.0 * pow(1.5, Double(retryCount)), 10.0)
        retryCount += 1
        print("🔄 \(Int(delay))s 后重试加载 (第\(retryCount)次)...")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, let webView = self.webView else { return }
            let t = Int(Date().timeIntervalSince1970 * 1000)
            if let url = URL(string: "http://localhost:9999/?_t=\(t)") {
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        webView?.loadHTMLString("", baseURL: nil)
        webView = nil
    }
}
