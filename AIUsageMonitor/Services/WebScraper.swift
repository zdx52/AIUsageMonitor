import Foundation
import WebKit

struct WebScrapeResult {
    let success: Bool
    let data: [String: Any]?
    let error: String?
}

class WebViewScraper: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView?
    private var completion: ((WebScrapeResult) -> Void)?
    private var timeoutTimer: Timer?
    private var isFinished = false
    
    func scrape(url: String, timeout: TimeInterval = 15) async -> WebScrapeResult {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: WebScrapeResult(success: false, data: nil, error: "实例已释放"))
                    return
                }
                
                let config = WKWebViewConfiguration()
                let userScript = WKUserScript(
                    source: """
                        window._apiData = {};
                        const originalFetch = window.fetch;
                        window.fetch = async function(...args) {
                            const response = await originalFetch.apply(this, args);
                            const url = args[0];
                            if (typeof url === 'string' && (url.includes('api') || url.includes('usage') || url.includes('balance'))) {
                                try {
                                    const clone = response.clone();
                                    const text = await clone.text();
                                    window._apiData[url] = text;
                                } catch(e) {}
                            }
                            return response;
                        };
                    """,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: false
                )
                config.userContentController.addUserScript(userScript)
                config.userContentController.add(self, name: "apiInterceptor")
                
                self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
                self.webView?.navigationDelegate = self
                self.completion = { result in
                    continuation.resume(returning: result)
                }
                
                self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.finishWith(result: WebScrapeResult(success: false, data: nil, error: "超时"))
                }
                
                if let urlObj = URL(string: url) {
                    let request = URLRequest(url: urlObj)
                    self.webView?.load(request)
                } else {
                    self.finishWith(result: WebScrapeResult(success: false, data: nil, error: "URL 无效"))
                }
            }
        }
    }
    
    private func finishWith(result: WebScrapeResult) {
        guard !isFinished else { return }
        isFinished = true
        timeoutTimer?.invalidate()
        completion?(result)
        completion = nil
        webView = nil
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self else { return }
            
            let js = """
                (function() {
                    try {
                        return JSON.stringify({
                            url: window.location.href,
                            apiData: window._apiData || {},
                            bodyText: document.body.innerText.substring(0, 5000)
                        });
                    } catch(e) {
                        return JSON.stringify({error: e.message});
                    }
                })()
            """
            
            self.webView?.evaluateJavaScript(js) { [weak self] result, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.finishWith(result: WebScrapeResult(success: false, data: nil, error: "JS 失败: \(error.localizedDescription)"))
                    return
                }
                
                if let jsonString = result as? String,
                   let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.finishWith(result: WebScrapeResult(success: true, data: json, error: nil))
                } else {
                    self.finishWith(result: WebScrapeResult(success: false, data: nil, error: "解析失败"))
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishWith(result: WebScrapeResult(success: false, data: nil, error: "导航失败: \(error.localizedDescription)"))
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // 处理消息
    }
}

class DeepSeekUsageScraper {
    static func fetchTodayUsage() async -> Double? {
        let scraper = WebViewScraper()
        let result = await scraper.scrape(url: "https://platform.deepseek.com/usage")
        
        guard result.success, let data = result.data else {
            return nil
        }
        
        if let bodyText = data["bodyText"] as? String {
            let patterns = [
                "今日消耗[：:]?\\s*[¥￥]([\\d.]+)",
                "Today[：:]?\\s*[¥￥]([\\d.]+)"
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: bodyText, range: NSRange(bodyText.startIndex..., in: bodyText)) {
                    let numStr = String(bodyText[Range(match.range(at: 1), in: bodyText)!])
                    return Double(numStr)
                }
            }
        }
        return nil
    }
}
