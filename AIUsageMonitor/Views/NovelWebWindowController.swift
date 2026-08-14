import SwiftUI
import WebKit

/// 小说创作 Web 窗口控制器（内嵌 WKWebView 加载 localhost:8080）
class NovelWebWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {

    static let shared = NovelWebWindowController()

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
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "小说创作"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        window.contentView = webView
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        loadWeb()
    }

    private func loadWeb() {
        guard let webView = self.webView else { return }
        let t = Int(Date().timeIntervalSince1970 * 1000)
        if let url = URL(string: "http://localhost:8080/?_t=\(t)") {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ 小说 Web 加载完成")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ 小说 Web 加载失败: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ 小说 Web 加载失败(预加载): \(error.localizedDescription)")
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        webView?.loadHTMLString("", baseURL: nil)
        webView = nil
    }
}
