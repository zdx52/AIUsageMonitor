import SwiftUI
import WebKit

// MARK: - Hindsight 看板窗口控制器

class DashboardWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    
    static let shared = DashboardWindowController()
    
    private var webView: WKWebView?
    private var proxyProcess: Process?
    private var proxyPipe: Pipe?
    private let proxyScript = "hindsight-server.py"
    private let proxyDir: String = Bundle.main.resourcePath!
    private let upgradeScript = "/Users/zdx52/.hermes/scripts/hindsight-upgrade.sh"
    private var currentVer: String = "?.?.?"
    
    func show() {
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        startProxy()
        createWindow()
    }
    
    // MARK: - 升级逻辑
    
    private func runUpgrade() {
        webView?.evaluateJavaScript("document.getElementById('hs-upgrade-btn').textContent = '升级中...'; document.getElementById('hs-upgrade-btn').disabled = true") { _, _ in }
        webView?.evaluateJavaScript("document.getElementById('hs-status').textContent = '① 清理缓存 → ② 升级包 → ③ 重启服务...'; document.getElementById('hs-status').style.color = '#8b8fa3'") { _, _ in }
        
        DispatchQueue.global().async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [self?.upgradeScript ?? ""]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            
            do {
                try process.run()
                process.waitUntilExit()
                let success = process.terminationStatus == 0
                DispatchQueue.main.async {
                    self?.webView?.evaluateJavaScript(
                        "document.getElementById('hs-upgrade-btn').textContent = '一键升级'; " +
                        "document.getElementById('hs-upgrade-btn').disabled = false; " +
                        "document.getElementById('hs-status').textContent = '\(success ? "升级成功 ✅" : "升级失败 ❌")'; " +
                        "document.getElementById('hs-status').style.color = '\(success ? "#4ade80" : "#ef4444")'"
                    ) { _, _ in }
                    if success { self?.fetchVersionAndInject(); self?.checkForUpdates() }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.webView?.evaluateJavaScript(
                        "document.getElementById('hs-upgrade-btn').textContent = '一键升级'; " +
                        "document.getElementById('hs-upgrade-btn').disabled = false; " +
                        "document.getElementById('hs-status').textContent = '升级失败'; " +
                        "document.getElementById('hs-status').style.color = '#ef4444'"
                    ) { _, _ in }
                }
            }
        }
    }
    
    private func checkForUpdates() {
        // 先显示状态
        webView?.evaluateJavaScript("document.getElementById('hs-status').textContent = '正在查询 PyPI...'; document.getElementById('hs-status').style.color = '#8b8fa3'") { _, _ in }
        
        // 如果还没获取到当前版本，先获取
        if currentVer == "?.?.?" { fetchVersionSync() }
        
        // 加随机参数绕过 CDN 缓存，确保真正请求到 PyPI 源站
        let t = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = URL(string: "https://pypi.org/pypi/hindsight-api/json?_t=\(t)") else { return }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        
        let startTime = CFAbsoluteTimeGetCurrent()
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            DispatchQueue.main.async {
                if let error = error {
                    self.updateStatus("❌ 联网失败: \(error.localizedDescription.prefix(30))", color: "#ef4444")
                    return
                }
                guard let httpResp = response as? HTTPURLResponse,
                      (200...299).contains(httpResp.statusCode),
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let info = json["info"] as? [String: Any],
                      let latest = info["version"] as? String else {
                    self.updateStatus("❌ PyPI 返回 \((response as? HTTPURLResponse)?.statusCode ?? 0)", color: "#ef4444")
                    return
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                let now = formatter.string(from: Date())
                let cur = self.currentVer
                let urlStr = req.url?.absoluteString ?? ""
                print("📡 PyPI 查询完成 [\(elapsed)ms] \(httpResp.statusCode) local=\(cur) latest=\(latest)")
                if latest != cur && cur != "?.?.?" {
                    self.updateStatus("⬆ 新版本 \(latest)（当前 \(cur)）[\(elapsed)ms @\(now)]", color: "#fb923c")
                } else if cur == "?.?.?" {
                    self.updateStatus("PyPI: \(latest)（本地未知）[\(elapsed)ms @\(now)]", color: "#eab308")
                } else {
                    self.updateStatus("已是最新 (\(latest)) [\(elapsed)ms @\(now)]", color: "#4ade80")
                }
            }
        }.resume()
    }
    
    private func fetchVersionSync() {
        guard let url = URL(string: "http://localhost:9077/version") else { return }
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ver = json["api_version"] as? String {
            currentVer = ver
        }
    }
    
    private func updateStatus(_ text: String, color: String) {
        webView?.evaluateJavaScript(
            "document.getElementById('hs-status').textContent = '\(text)'; " +
            "document.getElementById('hs-status').style.color = '\(color)'"
        ) { _, _ in }
    }
    
    // MARK: - 代理服务
    
    private func startProxy() {
        stopProxy()
        killPort8080()
        
        let pipe = Pipe()
        self.proxyPipe = pipe
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [proxyScript]
        process.currentDirectoryURL = URL(fileURLWithPath: proxyDir)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = pipe
        
        process.terminationHandler = { [weak self] p in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let err = String(data: data, encoding: .utf8), !err.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("⚠️ 代理进程退出: \(err.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            DispatchQueue.main.async { self?.proxyProcess = nil }
        }
        
        do {
            try process.run()
            proxyProcess = process
            print("✅ 代理服务已启动 (pid: \(process.processIdentifier))")
        } catch {
            print("❌ 无法启动代理服务: \(error)")
        }
    }
    
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
                }
            }
        } catch {
            print("⚠️ 无法清理端口 8080: \(error.localizedDescription)")
        }
    }
    
    private func stopProxy() {
        proxyProcess?.terminate()
        proxyProcess = nil
        proxyPipe = nil
    }
    
    private func waitForProxy(completion: @escaping () -> Void) {
        var attempts = 0
        func check() {
            attempts += 1
            if attempts > 10 { completion(); return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            task.arguments = ["-ti", "tcp:8080"]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 { completion(); return }
            } catch {}
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { check() }
        }
        check()
    }
    
    // MARK: - 窗口
    
    private func createWindow() {
        let config = WKWebViewConfiguration()
        // 注册 JS 消息处理
        config.userContentController.add(self, name: "hsAction")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 480),
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
        
        waitForProxy { [weak self] in
            guard let self = self, let webView = self.webView else { return }
            if let url = URL(string: "http://localhost:8080/hindsight-dashboard.html") {
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ 看板加载完成")
        // 延迟注入，确保 DOM 完全就绪
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.injectToolbar()
            // 稍后读取控制台日志确认注入状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.webView?.evaluateJavaScript("JSON.stringify({bar:!!document.getElementById('hs-bar'),body:!!document.body,check:!!document.getElementById('hs-check-btn'),upgrade:!!document.getElementById('hs-upgrade-btn')})") { r, _ in
                    print("📋 注入状态: \(r ?? "nil")")
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ 看板加载失败: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ 看板加载失败(预加载): \(error.localizedDescription)")
    }
    
    private func injectToolbar() {
        fetchVersionAndInject()
        
        let js = """
        (function() {
            try {
                if (document.getElementById('hs-bar')) return;
                console.log('hs: inject toolbar start');
                
                var bar = document.createElement('div');
                bar.id = 'hs-bar';
                bar.style.cssText = 'display:flex;align-items:center;gap:10px;padding:8px 18px;background:rgba(26,29,39,0.92);border-bottom:1px solid #2a2d3a;font-size:13px;flex-shrink:0;position:relative;z-index:99999;pointer-events:auto;';
                
                var v = document.createElement('span');
                v.id = 'hs-ver';
                v.style.cssText = 'color:#8b8fa3;font-weight:600;';
                v.textContent = 'Hindsight ...';
                bar.appendChild(v);
                
                var s = document.createElement('span');
                s.id = 'hs-status';
                s.style.cssText = 'color:#8b8fa3;font-size:12px;margin-left:4px;';
                s.textContent = '';
                bar.appendChild(s);
                
                var cb = document.createElement('button');
                cb.id = 'hs-check-btn';
                cb.textContent = '检查更新';
                cb.style.cssText = 'margin-left:auto;padding:4px 14px;border-radius:8px;border:1px solid #2a2d3a;background:#0f1117;color:#e1e4eb;font-size:12px;cursor:pointer;pointer-events:auto;';
                cb.onclick = function(e) { console.log('hs: check clicked'); try { window.webkit.messageHandlers.hsAction.postMessage('check'); } catch(err) { console.error('hs: msg err', err); } };
                cb.onmouseover = function() { this.style.borderColor = '#6c8cff'; };
                cb.onmouseout = function() { this.style.borderColor = '#2a2d3a'; };
                bar.appendChild(cb);
                
                var ub = document.createElement('button');
                ub.id = 'hs-upgrade-btn';
                ub.textContent = '一键升级';
                ub.style.cssText = 'padding:4px 14px;border-radius:8px;border:none;background:#6c8cff;color:#fff;font-size:12px;cursor:pointer;pointer-events:auto;';
                ub.onclick = function(e) { console.log('hs: upgrade clicked'); try { window.webkit.messageHandlers.hsAction.postMessage('upgrade'); } catch(err) { console.error('hs: msg err', err); } };
                ub.onmouseover = function() { this.style.opacity = '0.85'; };
                ub.onmouseout = function() { this.style.opacity = '1'; };
                bar.appendChild(ub);
                
                // 插入到 body 最顶部
                document.body.insertBefore(bar, document.body.firstChild);
                console.log('hs: inject done, bar in body:', !!document.getElementById('hs-bar'));
            } catch(e) {
                console.error('hs: inject failed', e);
            }
        })();
        """
        webView?.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("⚠️ 注入工具栏失败: \(error.localizedDescription)")
            } else {
                print("✅ 工具栏注入成功")
                // 读取 console 日志
                self.webView?.evaluateJavaScript("console.log('hs: post-inject verify ok')") { _, _ in }
            }
        }
    }
    
    private func fetchVersionAndInject() {
        guard let url = URL(string: "http://localhost:9077/version") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let ver = json["api_version"] as? String ?? "?.?.?"
            DispatchQueue.main.async {
                self?.currentVer = ver
                self?.webView?.evaluateJavaScript(
                    "var el = document.getElementById('hs-ver'); if (el) el.textContent = 'Hindsight v\(ver)';"
                ) { _, _ in }
            }
        }.resume()
    }
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "hsAction", let action = message.body as? String else { return }
        if action == "check" { checkForUpdates() }
        else if action == "upgrade" { runUpgrade() }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        stopProxy()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "hsAction")
        webView?.loadHTMLString("", baseURL: nil)
        webView = nil
    }
}
