import Foundation
import WebKit
import AppKit

// MARK: - OpenCode WebView 页面抓取器

class OpenCodeWebViewScraper: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var fetchWebView: WKWebView?
    var fetchCompletion: ((OpenCodeUsage?) -> Void)?
    private var fetchTimeoutTimer: Timer?
    var defaultTimeout: TimeInterval = 30
    var capturedAPIData: [String: [String: Any]] = [:]
    var capturedPageText: String = ""
    private var extractionAttemptCount = 0
    private let maxExtractionAttempts = 3
    
    // MARK: - WKScriptMessageHandler
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "openCodeData",
              let body = message.body as? [String: Any] else { return }
        handleScriptMessage(body)
    }
    
    // MARK: - WKWebView 页面抓取（后备方案）
    
    func fetchUsageViaWebView(urlString: String) async -> OpenCodeUsage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                self.cleanupFetch()
                self.capturedAPIData = [:]
                self.capturedPageText = ""
                
                let config = WKWebViewConfiguration()
                config.websiteDataStore = WKWebsiteDataStore.default()
                
                config.userContentController.add(self, name: "openCodeData")
                
                // 注入 JS 拦截 fetch/XHR 并实时发送到 native
                let interceptScript = WKUserScript(
                    source: """
                        (function() {
                            if (window.__ocInit) return;
                            window.__ocInit = true;
                            window.__ocCaptured = [];
                            
                            function sendToNative(type, data, url) {
                                try {
                                    window.webkit.messageHandlers.openCodeData.postMessage({
                                        type: type,
                                        data: data,
                                        url: url || ''
                                    });
                                } catch(e) {}
                            }
                            
                            const origFetch = window.fetch;
                            window.fetch = async function(...args) {
                                const url = typeof args[0] === 'string' ? args[0] : (args[0]?.url || '');
                                const resp = await origFetch.apply(this, args);
                                if (url.includes('/_server') || url.includes('usage') || url.includes('subscription') || url.includes('balance') || url.includes('billing') || url.includes('plan') || url.includes('remaining') || url.includes('reset')) {
                                    const clone = resp.clone();
                                    try {
                                        const text = await clone.text();
                                        window.__ocCaptured.push({url, text});
                                        sendToNative('captured_api', text.substring(0, 10000), url);
                                    } catch(e) {}
                                }
                                return resp;
                            };
                            
                            const origOpen = XMLHttpRequest.prototype.open;
                            XMLHttpRequest.prototype.open = function(method, url) {
                                this._ocUrl = typeof url === 'string' ? url : (url?.toString() || '');
                                return origOpen.apply(this, arguments);
                            };
                            const origSend = XMLHttpRequest.prototype.send;
                            XMLHttpRequest.prototype.send = function(...args) {
                                this.addEventListener('load', function() {
                                    const url = this._ocUrl || '';
                                    if (url.includes('/_server') || url.includes('usage') || url.includes('subscription') || url.includes('balance') || url.includes('billing') || url.includes('plan') || url.includes('remaining') || url.includes('reset')) {
                                        const text = this.responseText || '';
                                        window.__ocCaptured.push({url, text});
                                        sendToNative('captured_api', text.substring(0, 10000), url);
                                    }
                                });
                                return origSend.apply(this, args);
                            };
                        })()
                    """,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
                config.userContentController.addUserScript(interceptScript)
                
                let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
                webView.navigationDelegate = self
                self.fetchWebView = webView
                
                self.fetchCompletion = { result in
                    continuation.resume(returning: result)
                }
                
                self.fetchTimeoutTimer = Timer.scheduledTimer(withTimeInterval: self.defaultTimeout, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    print("❌ OpenCode 页面抓取超时")
                    self.finishFetch(usage: nil)
                }
                
                if let url = URL(string: urlString) {
                    print("🌐 OpenCode WebView 加载: \(urlString)")
                    webView.load(URLRequest(url: url))
                } else {
                    self.finishFetch(usage: nil)
                }
            }
        }
    }
    
    func cleanupFetch() {
        fetchTimeoutTimer?.invalidate()
        fetchTimeoutTimer = nil
        fetchWebView?.navigationDelegate = nil
        fetchWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "openCodeData")
        fetchWebView = nil
        fetchCompletion = nil
        capturedAPIData = [:]
        capturedPageText = ""
    }
    
    func finishFetch(usage: OpenCodeUsage?) {
        fetchTimeoutTimer?.invalidate()
        fetchTimeoutTimer = nil
        
        if let completion = self.fetchCompletion {
            self.fetchCompletion = nil
            completion(usage)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.fetchWebView?.navigationDelegate = nil
            self?.fetchWebView = nil
            self?.capturedAPIData = [:]
            self?.capturedPageText = ""
        }
    }
    
    // MARK: - JS 消息处理
    
    func handleScriptMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        
        if type == "captured_api" {
            guard let dataStr = body["data"] as? String,
                  let url = body["url"] as? String,
                  let data = dataStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if let dataStr = body["data"] as? String,
                    let url = body["url"] as? String,
                    let data = dataStr.data(using: .utf8),
                    let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
                    jsonArray.count >= 2,
                    let resultObj = jsonArray[1] as? [String: Any] {
                    capturedAPIData[url] = resultObj
                    print("📡 OpenCode API 拦截（数组格式）: \(url)")
                }
                return
            }
            capturedAPIData[url] = json
            print("📡 OpenCode API 拦截: \(url)")
            
            if let usage = parseCapturedAPIData() {
                print("✅ OpenCode API 数据解析成功！")
                finishFetch(usage: usage)
            }
        }
        
        if type == "extract_result" {
            guard let dataStr = body["data"] as? String,
                  let data = dataStr.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            
            let rollingPercent = parsed["rollingPercent"] as? Double
            let rollingReset = parsed["rollingReset"] as? String
            let weeklyPercent = parsed["weeklyPercent"] as? Double
            let weeklyReset = parsed["weeklyReset"] as? String
            let monthlyPercent = parsed["monthlyPercent"] as? Double
            let monthlyReset = parsed["monthlyReset"] as? String
            
            let hasThreeUsage = rollingPercent != nil || weeklyPercent != nil || monthlyPercent != nil
            
            if hasThreeUsage {
                print("📊 extract_result: rolling=\(rollingPercent ?? -1)%, weekly=\(weeklyPercent ?? -1)%, monthly=\(monthlyPercent ?? -1)%")
                let usage = OpenCodeUsage(
                    rollingPercent: rollingPercent,
                    rollingReset: rollingReset,
                    weeklyPercent: weeklyPercent,
                    weeklyReset: weeklyReset,
                    monthlyPercent: monthlyPercent,
                    monthlyReset: monthlyReset
                )
                finishFetch(usage: usage)
            }
        }
        
        if type == "page_text" {
            capturedPageText = body["data"] as? String ?? ""
        }
    }
    
    // MARK: - 解析捕获的 API 数据
    
    func parseCapturedAPIData() -> OpenCodeUsage? {
        for (_, json) in capturedAPIData {
            if let data = try? JSONSerialization.data(withJSONObject: json) {
                if let rpcResponse = try? JSONDecoder().decode(OpenCodeRPCResponse.self, from: data) {
                    if rpcResponse.usagePercent != nil || rpcResponse.remaining != nil || rpcResponse.plan != nil {
                        print("📊 解析到 RPC 数据: usagePercent=\(rpcResponse.usagePercent ?? -1), remaining=\(rpcResponse.remaining ?? -1), plan=\(rpcResponse.plan ?? "?")")
                        return OpenCodeUsage(
                            useBalance: rpcResponse.useBalance ?? false,
                            rpcUsagePercent: rpcResponse.usagePercent,
                            rpcResetInSec: rpcResponse.resetInSec,
                            rpcPlan: rpcResponse.plan,
                            rpcTotalUsed: rpcResponse.totalUsed,
                            rpcTotalLimit: rpcResponse.totalLimit,
                            rpcRemaining: rpcResponse.remaining
                        )
                    }
                }
            }
        }
        return nil
    }
    
    // MARK: - 从页面文本中提取数据（纯文本方式）
    
    func parseTextForUsageData() -> OpenCodeUsage? {
        let text = capturedPageText
        guard !text.isEmpty else { return nil }
        
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        var rollingPercent: Double?
        var rollingReset: String?
        var weeklyPercent: Double?
        var weeklyReset: String?
        var monthlyPercent: Double?
        var monthlyReset: String?
        
        for i in 0..<lines.count {
            let line = lines[i]
            
            if (line.contains("滚动") || line.lowercased().contains("rolling")) && i + 1 < lines.count {
                let nextLine = lines[i + 1]
                if let range = nextLine.range(of: "(\\d+)%", options: .regularExpression) {
                    let numStr = String(nextLine[range]).replacingOccurrences(of: "%", with: "")
                    rollingPercent = Double(numStr)
                    for j in (i + 2)..<min(i + 4, lines.count) {
                        if lines[j].contains("重置") || lines[j].lowercased().contains("reset") {
                            rollingReset = lines[j].replacingOccurrences(of: "重置于 ", with: "").replacingOccurrences(of: "重置于", with: "").trimmingCharacters(in: .whitespaces)
                            break
                        }
                    }
                }
            }
            else if (line.contains("每周") || line.lowercased().contains("weekly")) && i + 1 < lines.count {
                let nextLine = lines[i + 1]
                if let range = nextLine.range(of: "(\\d+)%", options: .regularExpression) {
                    let numStr = String(nextLine[range]).replacingOccurrences(of: "%", with: "")
                    weeklyPercent = Double(numStr)
                    for j in (i + 2)..<min(i + 4, lines.count) {
                        if lines[j].contains("重置") || lines[j].lowercased().contains("reset") {
                            weeklyReset = lines[j].replacingOccurrences(of: "重置于 ", with: "").replacingOccurrences(of: "重置于", with: "").trimmingCharacters(in: .whitespaces)
                            break
                        }
                    }
                }
            }
            else if (line.contains("每月") || line.lowercased().contains("monthly")) && i + 1 < lines.count {
                let nextLine = lines[i + 1]
                if let range = nextLine.range(of: "(\\d+)%", options: .regularExpression) {
                    let numStr = String(nextLine[range]).replacingOccurrences(of: "%", with: "")
                    monthlyPercent = Double(numStr)
                    for j in (i + 2)..<min(i + 4, lines.count) {
                        if lines[j].contains("重置") || lines[j].lowercased().contains("reset") {
                            monthlyReset = lines[j].replacingOccurrences(of: "重置于 ", with: "").replacingOccurrences(of: "重置于", with: "").trimmingCharacters(in: .whitespaces)
                            break
                        }
                    }
                }
            }
        }
        
        if rollingPercent != nil || weeklyPercent != nil || monthlyPercent != nil {
            return OpenCodeUsage(
                rollingPercent: rollingPercent,
                rollingReset: rollingReset,
                weeklyPercent: weeklyPercent,
                weeklyReset: weeklyReset,
                monthlyPercent: monthlyPercent,
                monthlyReset: monthlyReset
            )
        }
        
        return nil
    }
    
    // MARK: - 多轮提取
    
    func startExtractionLoop(webView: WKWebView) {
        extractionAttemptCount = 0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, webView === self.fetchWebView else { return }
            self.performExtractionAttempt(webView: webView, delayIndex: 0)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self = self, webView === self.fetchWebView else { return }
            self.performExtractionAttempt(webView: webView, delayIndex: 1)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, webView === self.fetchWebView else { return }
            self.performExtractionAttempt(webView: webView, delayIndex: 2)
        }
    }
    
    func performExtractionAttempt(webView: WKWebView, delayIndex: Int) {
        extractionAttemptCount += 1
        
        if !capturedAPIData.isEmpty {
            print("📡 第\(extractionAttemptCount)次提取: 使用 API 数据")
            if let usage = parseCapturedAPIData() {
                finishFetch(usage: usage)
                return
            }
        }
        
        if !capturedPageText.isEmpty {
            print("📝 第\(extractionAttemptCount)次提取: 解析页面文本")
            if let usage = parseTextForUsageData() {
                finishFetch(usage: usage)
                return
            }
        }
        
        print("🔍 第\(extractionAttemptCount)次提取: 注入 JS 提取")
        extractData(webView: webView, isFinalAttempt: delayIndex >= 2)
    }
    
    // MARK: - WKNavigationDelegate（后台抓取）
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.fetchWebView else { return }
        
        webView.evaluateJavaScript("window.location.href") { [weak self] urlString, _ in
            guard let self = self else { return }
            
            let url = urlString as? String ?? ""
            
            let loginUrlKeywords = ["/auth/", "/login", "/signin", "/oauth", "/authorize", "openauth", "open-auth"]
            let isLoginPage = loginUrlKeywords.contains { url.contains($0.lowercased()) }
            
            if isLoginPage {
                print("⚠️ OpenCode 需要登录（检测到登录页 URL: \(url)）")
                self.finishFetch(usage: OpenCodeUsage(
                    usagePercentages: [],
                    bodyText: "",
                    useBalance: false,
                    needsLogin: true
                ))
                return
            }
            
            print("✅ OpenCode 页面加载完成: \(url)")
            self.startExtractionLoop(webView: webView)
        }
    }
    
    func extractData(webView: WKWebView, isFinalAttempt: Bool = false) {
        let extractJS = """
            (function() {
                try {
                    const result = {};
                    
                    const captured = window.__ocCaptured || [];
                    for (const item of captured) {
                        try {
                            const parsed = JSON.parse(item.text);
                            if (parsed && typeof parsed === 'object') {
                                if (parsed.usagePercent !== undefined || parsed.resetInSec !== undefined || parsed.plan !== undefined || parsed.remaining !== undefined || parsed.totalLimit !== undefined) {
                                    result.apiData = parsed;
                                    break;
                                }
                                if (Array.isArray(parsed) && parsed.length >= 2) {
                                    const obj = parsed[1];
                                    if (obj && typeof obj === 'object' && (obj.usagePercent !== undefined || obj.remaining !== undefined || obj.plan !== undefined)) {
                                        result.apiData = obj;
                                        break;
                                    }
                                }
                            }
                        } catch(e) {}
                    }
                    
                    const bodyText = document.body ? document.body.innerText : '';
                    result.bodyText = bodyText.substring(0, 8000);
                    
                    try {
                        window.webkit.messageHandlers.openCodeData.postMessage({
                            data: bodyText.substring(0, 2000)
                        });
                    } catch(e) {}
                    
                    const cleanLines = bodyText.split('\\n').map(l => l.trim()).filter(l => l.length > 0);
                    
                    for (let i = 0; i < cleanLines.length; i++) {
                        const line = cleanLines[i];
                        
                        if (/滚动|rolling/i.test(line) && i + 1 < cleanLines.length) {
                            const pctMatch = cleanLines[i + 1].match(/(\\d+)%/);
                            if (pctMatch) {
                                result.rollingPercent = parseFloat(pctMatch[1]);
                                for (let j = i + 2; j < Math.min(i + 4, cleanLines.length); j++) {
                                    if (/重置|reset/i.test(cleanLines[j])) {
                                        result.rollingReset = cleanLines[j].replace(/重置于\\s*/, '').trim();
                                        break;
                                    }
                                }
                            }
                        }
                        else if (/每周|weekly/i.test(line) && i + 1 < cleanLines.length) {
                            const pctMatch = cleanLines[i + 1].match(/(\\d+)%/);
                            if (pctMatch) {
                                result.weeklyPercent = parseFloat(pctMatch[1]);
                                for (let j = i + 2; j < Math.min(i + 4, cleanLines.length); j++) {
                                    if (/重置|reset/i.test(cleanLines[j])) {
                                        result.weeklyReset = cleanLines[j].replace(/重置于\\s*/, '').trim();
                                        break;
                                    }
                                }
                            }
                        }
                        else if (/每月|monthly/i.test(line) && i + 1 < cleanLines.length) {
                            const pctMatch = cleanLines[i + 1].match(/(\\d+)%/);
                            if (pctMatch) {
                                result.monthlyPercent = parseFloat(pctMatch[1]);
                                for (let j = i + 2; j < Math.min(i + 4, cleanLines.length); j++) {
                                    if (/重置|reset/i.test(cleanLines[j])) {
                                        result.monthlyReset = cleanLines[j].replace(/重置于\\s*/, '').trim();
                                        break;
                                    }
                                }
                            }
                        }
                    }
                    
                    result.needsLogin = false;
                    result.url = window.location.href;
                    result.hasUsageData = bodyText.includes('%') || (result.apiData && (result.apiData.remaining !== undefined || result.apiData.plan !== undefined));
                    
                    try {
                        window.webkit.messageHandlers.openCodeData.postMessage({
                            type: 'extract_result',
                            data: JSON.stringify(result)
                        });
                    } catch(e) {}
                    return JSON.stringify(result);
                } catch(e) {
                    return JSON.stringify({ error: e.message, needsLogin: false });
                }
            })()
        """
        
        webView.evaluateJavaScript(extractJS) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ OpenCode JS 执行失败: \(error.localizedDescription)")
                if isFinalAttempt {
                    self.finishFetch(usage: nil)
                }
                return
            }
            
            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                if isFinalAttempt {
                    self.finishFetch(usage: nil)
                }
                return
            }
            
            if parsed["error"] as? String != nil {
                print("❌ OpenCode JS 错误: \(parsed["error"] as? String ?? "")")
                if isFinalAttempt {
                    self.finishFetch(usage: nil)
                }
                return
            }
            
            if let apiData = parsed["apiData"] as? [String: Any] {
                print("📡 JS 在 API 数据中找到结构化信息")
                let usage = OpenCodeUsage(
                    useBalance: apiData["useBalance"] as? Bool ?? false,
                    rpcUsagePercent: apiData["usagePercent"] as? Double,
                    rpcResetInSec: apiData["resetInSec"] as? Int,
                    rpcPlan: apiData["plan"] as? String,
                    rpcTotalUsed: apiData["totalUsed"] as? Int,
                    rpcTotalLimit: apiData["totalLimit"] as? Int,
                    rpcRemaining: apiData["remaining"] as? Int
                )
                self.finishFetch(usage: usage)
                return
            }
            
            let rollingPercent = parsed["rollingPercent"] as? Double
            let rollingReset = parsed["rollingReset"] as? String
            let weeklyPercent = parsed["weeklyPercent"] as? Double
            let weeklyReset = parsed["weeklyReset"] as? String
            let monthlyPercent = parsed["monthlyPercent"] as? Double
            let monthlyReset = parsed["monthlyReset"] as? String
            
            let hasThreeUsage = rollingPercent != nil || weeklyPercent != nil || monthlyPercent != nil
            
            if hasThreeUsage {
                print("📊 JS 提取到三种用量: rolling=\(rollingPercent ?? -1)%, weekly=\(weeklyPercent ?? -1)%, monthly=\(monthlyPercent ?? -1)%")
                let usage = OpenCodeUsage(
                    rollingPercent: rollingPercent,
                    rollingReset: rollingReset,
                    weeklyPercent: weeklyPercent,
                    weeklyReset: weeklyReset,
                    monthlyPercent: monthlyPercent,
                    monthlyReset: monthlyReset
                )
                self.finishFetch(usage: usage)
                return
            }
            
            if isFinalAttempt {
                print("⚠️ OpenCode 多次提取均未找到数据")
                let usage = OpenCodeUsage(
                    usagePercentages: parsed["usagePercentages"] as? [Int] ?? [],
                    bodyText: parsed["bodyText"] as? String ?? "",
                    useBalance: parsed["useBalance"] as? Bool ?? false,
                    needsLogin: false
                )
                self.finishFetch(usage: usage)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.fetchWebView else { return }
        print("❌ OpenCode 导航失败: \(error.localizedDescription)")
        finishFetch(usage: nil)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.fetchWebView else { return }
        print("❌ OpenCode 初始导航失败: \(error.localizedDescription)")
        finishFetch(usage: nil)
    }
}
