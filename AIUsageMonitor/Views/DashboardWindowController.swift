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
    private let upgradeTimeout: TimeInterval = 60  // 升级超时（uv 很快，10s 内完成）
    private var isUpgrading = false  // 防重复点击
    private var upgradePipeBuffer = ""  // 升级输出行缓存
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
        // 防重复点击
        guard !isUpgrading else { return }
        isUpgrading = true
        
        // 清空并显示控制台
        showUpgradeConsole()
        appendUpgradeLog("🔄 Hindsight 升级开始\n")
        updateUpgradeStep(1, "清理缓存")
        
        webView?.evaluateJavaScript(
            "document.getElementById('hs-upgrade-btn').textContent = '升级中...'; document.getElementById('hs-upgrade-btn').disabled = true; " +
            "document.getElementById('hs-status').textContent = '进行中，看底部日志'; document.getElementById('hs-status').style.color = '#8b8fa3'"
        ) { _, _ in }
        
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [self.upgradeScript]
            
            // 管道捕获输出
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = outPipe  // stderr 也合并到 stdout
            
            defer {
                DispatchQueue.main.async { self.isUpgrading = false }
            }
            
            // 逐行读取输出缓冲
            var lineBuf = ""
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                guard let chunk = String(data: data, encoding: .utf8) else { return }
                
                lineBuf += chunk
                // 按换行符拆成完整行
                let lines = lineBuf.components(separatedBy: "\n")
                if lines.count > 1 {
                    lineBuf = lines.last ?? ""
                    let complete = lines.dropLast()
                    for line in complete {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        
                        if trimmed.hasPrefix("[STEP:") {
                            // 解析进度标记: [STEP:N] 或 [STEP:DONE] 或 [STEP:FAIL]
                            // 格式: [STEP:1] 标签文字...  或  [STEP:DONE] 结果文字
                            let rest = String(trimmed.dropFirst(6)) // 去掉 "[STEP:"
                            if let endIdx = rest.firstIndex(of: "]") {
                                let stepStr = String(rest[..<endIdx])
                                let label = rest[rest.index(after: endIdx)...].trimmingCharacters(in: .whitespacesAndNewlines)
                                DispatchQueue.main.async {
                                    if stepStr == "DONE" {
                                        self.appendUpgradeLog("\n✅ 升级完成！\(label)\n")
                                    } else if stepStr == "FAIL" {
                                        self.appendUpgradeLog("\n❌ 升级失败\n")
                                    } else if let stepNum = Int(stepStr) {
                                        self.updateUpgradeStep(stepNum, label)
                                    }
                                }
                            }
                        } else {
                            // 普通输出行
                            DispatchQueue.main.async {
                                self.appendUpgradeLog(trimmed + "\n")
                            }
                        }
                    }
                }
            }
            
            do {
                // 终止处理器必须在 run() 之前设置
                let group = DispatchGroup()
                group.enter()
                process.terminationHandler = { _ in
                    // 关闭管道，触发 readabilityHandler 最后剩余数据
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    group.leave()
                }
                
                try process.run()
                
                // 超时等待
                let deadline = DispatchTime.now() + self.upgradeTimeout
                let result = group.wait(timeout: deadline)
                
                // 读取管道剩余数据
                let remaining = outPipe.fileHandleForReading.availableData
                if !remaining.isEmpty, let tail = String(data: remaining, encoding: .utf8) {
                    for line in tail.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            DispatchQueue.main.async {
                                self.appendUpgradeLog(trimmed + "\n")
                            }
                        }
                    }
                }
                
                if result == .timedOut {
                    process.terminate()
                    process.waitUntilExit()
                    DispatchQueue.main.async {
                        self.webView?.evaluateJavaScript(
                            "document.getElementById('hs-upgrade-btn').textContent = '一键升级'; " +
                            "document.getElementById('hs-upgrade-btn').disabled = false; " +
                            "document.getElementById('hs-status').textContent = '⏱️ 升级超时（>60s）'; " +
                            "document.getElementById('hs-status').style.color = '#ef4444'; " +
                            "hsSetStep('超时')"
                        ) { _, _ in }
                        self.appendUpgradeLog("\n⏱️ 升级超时（>60秒）\n")
                    }
                    return
                }
                
                let success = process.terminationStatus == 0
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript(
                        "document.getElementById('hs-upgrade-btn').textContent = '一键升级'; " +
                        "document.getElementById('hs-upgrade-btn').disabled = false; " +
                        "document.getElementById('hs-status').textContent = '\(success ? "升级成功 ✅" : "升级失败 ❌")'; " +
                        "document.getElementById('hs-status').style.color = '\(success ? "#4ade80" : "#ef4444")'"
                    ) { _, _ in }
                    if !success {
                        self.appendUpgradeLog("\n❌ 升级失败（退出码: \(process.terminationStatus)）\n")
                    }
                    if success { self.fetchVersionAndInject(); self.checkForUpdates() }
                }
            } catch {
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript(
                        "document.getElementById('hs-upgrade-btn').textContent = '一键升级'; " +
                        "document.getElementById('hs-upgrade-btn').disabled = false; " +
                        "document.getElementById('hs-status').textContent = '升级失败'; " +
                        "document.getElementById('hs-status').style.color = '#ef4444'; " +
                        "hsSetStep('出错')"
                    ) { _, _ in }
                    self.appendUpgradeLog("\n❌ 升级异常: \(error.localizedDescription)\n")
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
                
                // ——— 升级控制台（初始隐藏，升级时显示） ———
                if (!document.getElementById('hs-console-wrap')) {
                    var cw = document.createElement('div');
                    cw.id = 'hs-console-wrap';
                    cw.style.cssText = 'display:none;flex-direction:column;border-top:1px solid #2a2d3a;background:rgba(15,17,23,0.97);flex-shrink:0;max-height:45%;min-height:80px;position:relative;z-index:99999;';
                    
                    var ch = document.createElement('div');
                    ch.id = 'hs-console-header';
                    ch.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:6px 14px;font-size:11px;color:#6c8cff;background:rgba(26,29,39,0.95);border-bottom:1px solid #2a2d3a;';
                    ch.innerHTML = '<span>📋 升级日志</span><span id="hs-console-step" style="color:#8b8fa3;">准备中...</span>';
                    cw.appendChild(ch);
                    
                    var co = document.createElement('div');
                    co.id = 'hs-console';
                    co.style.cssText = 'flex:1;overflow-y:auto;padding:8px 14px;font-family:Menlo,monospace;font-size:11px;line-height:1.6;color:#c9d1d9;white-space:pre-wrap;word-break:break-all;';
                    cw.appendChild(co);
                    
                    document.body.appendChild(cw);
                }
                
                // ——— JS 接口 ———
                window.hsAppendLog = function(txt) {
                    var el = document.getElementById('hs-console');
                    var wrap = document.getElementById('hs-console-wrap');
                    if (!el || !wrap) return;
                    wrap.style.display = 'flex';
                    el.textContent += txt;
                    el.scrollTop = el.scrollHeight;
                };
                window.hsSetStep = function(label) {
                    var el = document.getElementById('hs-console-step');
                    if (el) el.textContent = label;
                };
                window.hsClearConsole = function() {
                    var el = document.getElementById('hs-console');
                    if (el) el.textContent = '';
                };
                
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
    
    // MARK: - 升级控制台
    
    private func showUpgradeConsole() {
        webView?.evaluateJavaScript("hsClearConsole(); hsSetStep('准备中...'); void(0);") { _, _ in }
    }
    
    private func appendUpgradeLog(_ text: String) {
        // 用 JSON 序列化确保 JS 字符串正确转义
        guard let data = try? JSONSerialization.data(withJSONObject: [text], options: []),
              let json = String(data: data, encoding: .utf8) else { return }
        let safe = String(json.dropFirst().dropLast()) // 去掉 JSON 数组的 [ ]
        webView?.evaluateJavaScript("hsAppendLog(\(safe))") { _, _ in }
    }
    
    private func updateUpgradeStep(_ step: Int, _ label: String) {
        let escaped = label.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("hsSetStep('\(escaped)')") { _, _ in }
        // 不在这里写日志行，由脚本的 [STEP:N] 标记统一输出
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
