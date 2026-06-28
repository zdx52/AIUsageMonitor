import SwiftUI
import WebKit

// MARK: - Hindsight 看板窗口控制器

class DashboardWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    
    static let shared = DashboardWindowController()
    
    private var webView: WKWebView?
    private var proxyProcess: Process?
    private var proxyPipe: Pipe?
    private let proxyScript = "/Users/zdx52/Documents/Hermes/hindsight-dashboard/hindsight-server.py"
    private let proxyDir = "/Users/zdx52/Documents/Hermes/hindsight-dashboard/"
    
    func show() {
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        startProxy()
        createWindow()
    }
    
    // MARK: - 代理服务
    
    private func startProxy() {
        // 先清理已有进程和端口
        stopProxy()
        killPort8080()
        
        let pipe = Pipe()
        self.proxyPipe = pipe
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [proxyScript]
        process.currentDirectoryURL = URL(fileURLWithPath: proxyDir)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe // 捕获 stderr 用于调试
        
        process.terminationHandler = { [weak self] p in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let err = String(data: data, encoding: .utf8), !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("⚠️ 代理进程退出: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            DispatchQueue.main.async {
                self?.proxyProcess = nil
            }
        }
        
        do {
            try process.run()
            proxyProcess = process
            print("✅ 代理服务已启动 (pid: \(process.processIdentifier))")
        } catch {
            print("❌ 无法启动代理服务: \(error)")
            // 显示错误页面
            let errorHTML = "<html><body style='font-family:-apple-system;padding:40px;background:#1a1d27;color:#e1e4eb'><h2>⚠️ 代理服务启动失败</h2><p style='color:#8b8fa3'>\(error.localizedDescription)</p></body></html>"
            webView?.loadHTMLString(errorHTML, baseURL: nil)
        }
    }
    
    /// 清理占用 8080 端口的旧进程
    private func killPort8080() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-ti", "tcp:8080"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            if let pids = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !pids.isEmpty {
                for pid in pids.components(separatedBy: "\n") where !pid.isEmpty {
                    let killTask = Process()
                    killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                    killTask.arguments = ["-9", pid]
                    try killTask.run()
                    killTask.waitUntilExit()
                    print("🧹 已清理端口 8080 上的旧进程 pid=\(pid)")
                }
            }
        } catch {}
    }
    
    private func stopProxy() {
        proxyProcess?.terminate()
        proxyProcess = nil
        proxyPipe = nil
    }
    
    private func waitForProxy(completion: @escaping () -> Void) {
        // 最多等 5 秒，每秒检查一次 8080 端口
        var attempts = 0
        func check() {
            attempts += 1
            if attempts > 10 {
                print("⚠️ 代理服务启动超时，仍然尝试加载")
                completion()
                return
            }
            // 快速检查端口是否在监听
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            task.arguments = ["-ti", "tcp:8080"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    // 端口已被监听
                    completion()
                    return
                }
            } catch {}
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { check() }
        }
        check()
    }
    
    // MARK: - 窗口
    
    private func createWindow() {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Hindsight 看板"
        window.contentView = webView
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        
        // 等代理就绪后再加载
        waitForProxy { [weak self] in
            guard let self = self, let webView = self.webView else { return }
            if let url = URL(string: "http://localhost:8080/hindsight-dashboard.html") {
                print("📄 加载看板: \(url)")
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        print("📄 看板加载中...")
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ 看板加载完成")
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ 看板加载失败: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ 看板加载失败(预加载): \(error.localizedDescription)")
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        stopProxy()
        webView?.loadHTMLString("", baseURL: nil)
        webView = nil
    }
}
