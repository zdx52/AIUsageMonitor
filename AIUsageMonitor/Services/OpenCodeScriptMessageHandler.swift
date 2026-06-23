import Foundation
import WebKit

// MARK: - JS 消息处理器（用于 WKWebView ↔ Native 通信）

class OpenCodeScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var service: OpenCodeService?
    
    init(service: OpenCodeService) {
        self.service = service
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "openCodeData",
              let body = message.body as? [String: Any] else { return }
        service?.handleScriptMessage(body)
    }
}
