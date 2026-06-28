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
    var pageURL: String = ""
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "openCodeData",
              let body = message.body as? [String: Any] else { return }
        handleScriptMessage(body)
    }
    
    func fetchUsageViaWebView(urlString: String) async -> OpenCodeUsage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                self.cleanup()
                self.capturedAPIData = [:]
                self.capturedPageText = ""
                self.pageURL = ""
                
                let config = WKWebViewConfiguration()
                config.websiteDataStore = WKWebsiteDataStore.default()
                config.userContentController.add(self, name: "openCodeData")
                
                let script = WKUserScript(source: """
                    (function() {
                        if (window.__ocInit) return;
                        window.__ocInit = true;
                        window.__ocCaptured = [];
                        const origFetch = window.fetch;
                        window.fetch = async function(...args) {
                            const url = typeof args[0] === 'string' ? args[0] : (args[0]?.url || '');
                            const resp = await origFetch.apply(this, args);
                            if (url.includes('/_server') || url.includes('usage') || url.includes('subscription') || url.includes('plan') || url.includes('remaining') || url.includes('reset') || url.includes('balance') || url.includes('billing')) {
                                const clone = resp.clone();
                                try {
                                    const text = await clone.text();
                                    window.__ocCaptured.push({url, text});
                                    window.webkit.messageHandlers.openCodeData.postMessage({type:'captured_api', data:text.substring(0,10000), url});
                                } catch(e) {}
                            }
                            return resp;
                        };
                    })()
                """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                config.userContentController.addUserScript(script)
                
                let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
                webView.navigationDelegate = self
                self.fetchWebView = webView
                
                self.fetchCompletion = { result in
                    continuation.resume(returning: result)
                }
                
                self.fetchTimeoutTimer = Timer.scheduledTimer(withTimeInterval: self.defaultTimeout, repeats: false) { [weak self] _ in
                    print("⏰ OpenCode 抓取超时")
                    self?.doFinish(usage: nil)
                }
                
                if let url = URL(string: urlString) {
                    webView.load(URLRequest(url: url))
                } else {
                    self.doFinish(usage: nil)
                }
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.fetchWebView else { return }
        
        webView.evaluateJavaScript("window.location.href") { [weak self] urlString, _ in
            guard let self = self else { return }
            let url = urlString as? String ?? ""
            self.pageURL = url
            
            // 判断是否登录页
            let loginKeywords = ["/auth/", "/login", "/signin", "/oauth", "/authorize", "openauth"]
            if loginKeywords.contains(where: { url.contains($0.lowercased()) }) {
                print("⚠️ OpenCode 需要登录: \\(url)")
                self.doFinish(usage: OpenCodeUsage(needsLogin: true))
                return
            }
            
            // 获取页面文本 + 提取数据
            self.captureAndExtract(webView: webView)
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.fetchWebView else { return }
        print("⚠️ OpenCode 页面加载错误: \\(error.localizedDescription)")
    }
    
    // MARK: - 调试 + 提取
    
    func captureAndExtract(webView: WKWebView) {
        // 先获取页面基本信息用于调试
        let debugJS = "JSON.stringify({url:location.href,title:document.title,text:document.body.innerText.substring(0,5000)})"
        
        webView.evaluateJavaScript(debugJS) { [weak self] result, error in
            guard let self = self else { return }
            
            if let jsonStr = result as? String,
               let data = jsonStr.data(using: .utf8),
               let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let url = info["url"] as? String ?? ""
                let title = info["title"] as? String ?? ""
                let text = info["text"] as? String ?? ""
                print("📄 URL: \\(url)")
                print("📄 标题: \\(title)")
                if !text.isEmpty {
                    print("📄 文本(前300): \\(text.prefix(300))")
                }
                self.capturedPageText = text
            }
            
            // 尝试所有方式提取
            self.tryExtract(webView: webView)
        }
    }
    
    func tryExtract(webView: WKWebView) {
        let js = """
            (function() {
                try {
                    const result = {};
                    
                    // 1. 尝试拦截的 API 数据
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
                    
                    // 2. 页面文本中找数据
                    const bodyText = document.body ? document.body.innerText : '';
                    result.bodyText = bodyText.substring(0, 5000);
                    
                    const lines = bodyText.split('\\\\n').map(l => l.trim()).filter(l => l.length > 0);
                    for (let i = 0; i < lines.length; i++) {
                        const line = lines[i];
                        if (/滚动|rolling/i.test(line) && i + 1 < lines.length) {
                            const m = lines[i + 1].match(/(\\\\d+)%/);
                            if (m) { result.rollingPercent = parseFloat(m[1]); }
                        }
                        if (/每周|weekly/i.test(line) && i + 1 < lines.length) {
                            const m = lines[i + 1].match(/(\\\\d+)%/);
                            if (m) { result.weeklyPercent = parseFloat(m[1]); }
                        }
                        if (/每月|monthly/i.test(line) && i + 1 < lines.length) {
                            const m = lines[i + 1].match(/(\\\\d+)%/);
                            if (m) { result.monthlyPercent = parseFloat(m[1]); }
                        }
                    }
                    
                    result.hasUsage = !!(result.apiData || result.rollingPercent || result.weeklyPercent || result.monthlyPercent);
                    return JSON.stringify(result);
                } catch(e) {
                    return JSON.stringify({error: e.message, bodyText: document.body?.innerText?.substring(0,2000) || ''});
                }
            })()
        """
        
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ JS 错误: \\(error.localizedDescription)")
                // 超时后再试一次
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard let wv = self.fetchWebView else { return }
                    self.tryExtract(webView: wv)
                }
                return
            }
            
            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            
            // 检查 API 数据
            if let api = parsed["apiData"] as? [String: Any] {
                if api["usagePercent"] != nil || api["remaining"] != nil || api["plan"] != nil {
                    print("📊 API 数据: \\(api)")
                    let usage = OpenCodeUsage(
                        useBalance: api["useBalance"] as? Bool ?? false,
                        rpcUsagePercent: api["usagePercent"] as? Double,
                        rpcResetInSec: api["resetInSec"] as? Int,
                        rpcPlan: api["plan"] as? String,
                        rpcTotalUsed: api["totalUsed"] as? Int,
                        rpcTotalLimit: api["totalLimit"] as? Int,
                        rpcRemaining: api["remaining"] as? Int
                    )
                    self.doFinish(usage: usage)
                    return
                }
            }
            
            // 检查页面文本提取
            let rp = parsed["rollingPercent"] as? Double
            let wp = parsed["weeklyPercent"] as? Double
            let mp = parsed["monthlyPercent"] as? Double
            
            if rp != nil || wp != nil || mp != nil {
                print("📊 页面提取: rolling=\\(rp ?? -1) weekly=\\(wp ?? -1) monthly=\\(mp ?? -1)")
                let usage = OpenCodeUsage(
                    rollingPercent: rp,
                    weeklyPercent: wp,
                    monthlyPercent: mp
                )
                self.doFinish(usage: usage)
                return
            }
            
            // 没有数据 - 打印收到的内容帮助调试
            let bodyText = parsed["bodyText"] as? String ?? ""
            print("⚠️ 未提取到数据, 页面文本(500): \\(bodyText.prefix(500))")
            
            // 3秒后重试（可能数据还没加载完）
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self, let wv = self.fetchWebView else { return }
                self.tryExtract(webView: wv)
            }
        }
    }
    
    // MARK: - JS 消息处理
    
    func handleScriptMessage(_ body: [String: Any]) {
        guard let type = body["type"] as? String else { return }
        
        if type == "captured_api" {
            guard let dataStr = body["data"] as? String,
                  let url = body["url"] as? String,
                  let data = dataStr.data(using: .utf8) else { return }
            
            // 尝试解析为标准 JSON 对象
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                capturedAPIData[url] = json
                print("📡 API 拦截: \\(url)")
                if let usage = parseCapturedData(json) {
                    doFinish(usage: usage)
                }
                return
            }
            
            // 尝试解析为数组格式 (OpenCode RPC 常用格式)
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
               jsonArray.count >= 2,
               let resultObj = jsonArray[1] as? [String: Any] {
                capturedAPIData[url] = resultObj
                print("📡 API 拦截(数组): \\(url)")
                if let usage = parseCapturedData(resultObj) {
                    doFinish(usage: usage)
                }
            }
        }
    }
    
    // MARK: - 解析
    
    func parseCapturedData(_ json: [String: Any]) -> OpenCodeUsage? {
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            if let rpc = try? JSONDecoder().decode(OpenCodeRPCResponse.self, from: data) {
                if rpc.usagePercent != nil || rpc.remaining != nil || rpc.plan != nil || rpc.resetInSec != nil {
                    print("📊 解析成功: \\(rpc)")
                    return OpenCodeUsage(
                        useBalance: rpc.useBalance ?? false,
                        rpcUsagePercent: rpc.usagePercent,
                        rpcResetInSec: rpc.resetInSec,
                        rpcPlan: rpc.plan,
                        rpcTotalUsed: rpc.totalUsed,
                        rpcTotalLimit: rpc.totalLimit,
                        rpcRemaining: rpc.remaining
                    )
                }
            }
        }
        return nil
    }
    
    // MARK: - 清理
    
    func doFinish(usage: OpenCodeUsage?) {
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
    
    func cleanup() {
        fetchTimeoutTimer?.invalidate()
        fetchTimeoutTimer = nil
        fetchWebView?.navigationDelegate = nil
        fetchWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "openCodeData")
        fetchWebView = nil
        fetchCompletion = nil
        capturedAPIData = [:]
        capturedPageText = ""
    }
}
