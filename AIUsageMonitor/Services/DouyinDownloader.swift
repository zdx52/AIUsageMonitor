import AppKit
import WebKit

/// 抖音单条作品下载。
///
/// 为什么不用 yt-dlp：抖音接口现在要求 a_bogus 签名，yt-dlp 稳定版直连必 403（issue #17826 未修）。
/// 这里改成让 WebKit 自己去打开作品页 —— 签名由抖音自己的 JS 现算，页面自己发出的
/// `/aweme/v1/web/aweme/detail/` 响应里带着全部清晰度的真实地址，勾住它就行。
/// 拿到地址后带 Referer 下载，存到 ~/Downloads。
///
/// 范围：单条视频。图文（images）和整号批量不在这条路里。
final class DouyinDownloader: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

    static let shared = DouyinDownloader()

    enum DownloadError: LocalizedError {
        case busy
        case badLink
        case noResponse
        case noVideo
        case http(Int)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .busy: return "上一条还在下，等它结束"
            case .badLink: return "链接里找不到抖音作品 ID，请把作品页或分享链接整条粘进来"
            case .noResponse: return "25 秒内没拿到抖音接口响应（可能被风控或网络问题），再试一次"
            case .noVideo: return "这条作品里没有视频源（可能是图文作品）"
            case .http(let code): return "下载失败，HTTP \(code)"
            case .saveFailed(let msg): return "保存到下载目录失败：\(msg)"
            }
        }
    }

    private struct Quality {
        let width: Int
        let height: Int
        let size: Int
        let url: String
    }

    private var webView: WKWebView?
    private var hiddenWindow: NSWindow?
    private var onProgress: ((String) -> Void)?
    private var onFinish: ((Result<URL, Error>) -> Void)?
    private var timeoutWork: DispatchWorkItem?
    private var settled = false
    private var captured = false
    private var targetId: String?

    var isBusy: Bool { webView != nil }

    // MARK: - 对外入口

    func download(link: String,
                  progress: @escaping (String) -> Void,
                  completion: @escaping (Result<URL, Error>) -> Void) {
        guard !isBusy else { completion(.failure(DownloadError.busy)); return }
        guard let target = Self.normalize(link) else { completion(.failure(DownloadError.badLink)); return }

        onProgress = progress
        onFinish = completion
        settled = false
        captured = false
        targetId = Self.firstMatch(in: target.absoluteString, pattern: #"/video/(\d{15,25})"#)
        progress("正在打开作品页…")

        let config = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(self, name: "cap")
        ucc.addUserScript(WKUserScript(source: Self.hook,
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: false))
        config.userContentController = ucc

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700), configuration: config)
        web.navigationDelegate = self
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        webView = web

        // 需要有个窗口，页面才会真正渲染并发请求；透明 + 置底 + 不吃鼠标，用户看不到也点不到
        let win = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = web
        win.alphaValue = 0
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.transient, .ignoresCycle]
        win.orderBack(nil)
        hiddenWindow = win

        web.load(URLRequest(url: target))

        let work = DispatchWorkItem { [weak self] in
            // 接口没给源时的兜底：直接问播放器要当前地址（画质可能不是最高，但能下）
            self?.fallbackToVideoElement()
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: work)
    }

    // MARK: - 链接归一化

    /// 认三种输入：作品页 /video/<id>、主页带 modal_id=<id>、v.douyin.com 短链（原样返回让页面自己跳）
    static func normalize(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }

        if let id = firstMatch(in: text, pattern: #"modal_id=(\d{15,25})"#) {
            return URL(string: "https://www.douyin.com/video/\(id)")
        }
        if let id = firstMatch(in: text, pattern: #"/video/(\d{15,25})"#) {
            return URL(string: "https://www.douyin.com/video/\(id)")
        }
        if let id = firstMatch(in: text, pattern: #"/share/video/(\d{15,25})"#) {
            return URL(string: "https://www.douyin.com/video/\(id)")
        }
        if let short = firstMatch(in: text, pattern: #"https?://v\.douyin\.com/[A-Za-z0-9_\-]+"#) {
            return URL(string: short)
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range) else { return nil }
        if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) {
            return String(text[r])
        }
        if let r = Range(m.range, in: text) { return String(text[r]) }
        return nil
    }

    // MARK: - 页面钩子

    private static let hook = """
    (function(){
      // 隐藏窗口里不能出声：页面一有 video 就静音
      setInterval(function(){
        var vs = document.querySelectorAll('video');
        for (var i = 0; i < vs.length; i++) { vs[i].muted = true; }
      }, 300);
      function send(u, t) {
        try { window.webkit.messageHandlers.cap.postMessage({u: String(u), t: String(t)}); } catch(e) {}
      }
      // 只要响应里带 "play_addr" 就送过来 —— 不绑死具体接口名，
      // 抖音改路径/改参数/加 v2 前缀都能命中，少一类“改接口就坏”。
      function worth(u, t) {
        if (String(t).indexOf('"play_addr"') < 0) return false;
        return String(u).indexOf('/aweme') >= 0 || String(u).indexOf('/douyin') >= 0;
      }
      var of = window.fetch;
      window.fetch = async function(){
        var r = await of.apply(this, arguments);
        try {
          var a = arguments[0];
          var u = (a && a.url) || a;
          if (String(u).indexOf('/aweme') >= 0) {
            r.clone().text().then(function(t){ if (worth(u, t)) send(u, t); });
          }
        } catch(e) {}
        return r;
      };
      var oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(m,u){ this.__u = u; return oo.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function(){
        this.addEventListener('load', function(){
          try {
            var u = String(this.__u), t = this.responseText;
            if (u.indexOf('/aweme') >= 0 && worth(u, t)) send(u, t);
          } catch(e){}
        });
        return os.apply(this, arguments);
      };
    })();
    """

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard !settled, !captured,
              let body = message.body as? [String: Any],
              let text = body["t"] as? String,
              let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return }

        // 先按作品 ID 定位这一条（不想把“相关推荐”里的视频当成目标）；
        // 找不到再全树搜 —— 抖音改了字段层级也能捞到。
        var aweme: [String: Any] = [:]
        if let id = targetId, let hit = Self.findAweme(root, id: id) {
            aweme = hit
        } else if let rootDict = root as? [String: Any] {
            aweme = (rootDict["aweme_detail"] as? [String: Any])
                ?? ((rootDict["aweme_list"] as? [[String: Any]])?.first ?? [:])
        }

        var candidates: [Quality] = []
        Self.collectPlayAddrs(aweme.isEmpty ? root : aweme, into: &candidates)
        // 只认视频流，别把封面图（也有 url_list + 宽高）当视频
        let videoOnly = candidates.filter { $0.url.contains("video_mp4") || $0.url.contains(".mp4") }
        let pool = videoOnly.isEmpty ? candidates : videoOnly
        guard let best = pool.max(by: { ($0.width * $0.height, $0.size) < ($1.width * $1.height, $1.size) }) else {
            fail(.noVideo)
            return
        }

        let author = ((aweme["author"] as? [String: Any])?["nickname"] as? String) ?? "douyin"
        let desc = (aweme["desc"] as? String) ?? ""
        let awemeId = (aweme["aweme_id"] as? String) ?? targetId ?? "video"
        captured = true
        onProgress?("拿到 \(best.width)×\(best.height) 源，开始下载…")
        startDownload(best, author: author, desc: desc, awemeId: awemeId)
    }

    // MARK: - 容错解析（不绑死 JSON 结构）

    private static func findAweme(_ node: Any, id: String, depth: Int = 0) -> [String: Any]? {
        guard depth < 14 else { return nil }
        if let dict = node as? [String: Any] {
            if let s = dict["aweme_id"] as? String, s == id { return dict }
            if let n = dict["aweme_id"] as? NSNumber, String(n.int64Value) == id { return dict }
            for value in dict.values {
                if let hit = findAweme(value, id: id, depth: depth + 1) { return hit }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let hit = findAweme(value, id: id, depth: depth + 1) { return hit }
            }
        }
        return nil
    }

    /// 全树搜所有 play_addr* 节点，不假设它挂在 video.bit_rate 下面
    private static func collectPlayAddrs(_ node: Any, into out: inout [Quality], depth: Int = 0) {
        guard depth < 14 else { return }
        if let dict = node as? [String: Any] {
            for (key, value) in dict {
                if key.hasPrefix("play_addr"),
                   let pa = value as? [String: Any],
                   let urls = pa["url_list"] as? [String], let first = urls.first {
                    let w = (pa["width"] as? NSNumber)?.intValue ?? 0
                    let h = (pa["height"] as? NSNumber)?.intValue ?? 0
                    if w > 0, h > 0 {
                        out.append(Quality(width: w, height: h,
                                           size: (pa["data_size"] as? NSNumber)?.intValue ?? 0,
                                           url: first))
                    }
                }
                collectPlayAddrs(value, into: &out, depth: depth + 1)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectPlayAddrs(value, into: &out, depth: depth + 1)
            }
        }
    }

    // MARK: - 兜底：问播放器要地址

    private func fallbackToVideoElement() {
        guard !settled, !captured, let web = webView else { return }
        let js = "(function(){var v=document.querySelector('video');return v?(v.currentSrc||v.src||''):''})()"
        web.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self, !self.settled, !self.captured else { return }
            guard let urlString = result as? String, urlString.hasPrefix("http") else {
                self.fail(.noResponse)
                return
            }
            self.captured = true
            self.onProgress?("接口没给源，降级用播放器地址下载（画质可能不是最高）")
            self.startDownload(Quality(width: 0, height: 0, size: 0, url: urlString),
                               author: "douyin", desc: "", awemeId: self.targetId ?? "video")
        }
    }

    // MARK: - 下载

    private func startDownload(_ quality: Quality, author: String, desc: String, awemeId: String) {
        var request = URLRequest(url: URL(string: quality.url)!)
        request.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")

        URLSession.shared.downloadTask(with: request) { [weak self] tmp, response, error in
            guard let self = self else { return }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                self.fail(.http(http.statusCode))
                return
            }
            if let error = error {
                self.fail(.saveFailed(error.localizedDescription))
                return
            }
            guard let tmp = tmp else {
                self.fail(.saveFailed("下载结果为空"))
                return
            }
            let name = Self.fileName(author: author, desc: desc, awemeId: awemeId, quality: quality)
            guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                self.fail(.saveFailed("找不到下载目录"))
                return
            }
            let dest = Self.uniqueURL(in: dir, name: name)
            do {
                try FileManager.default.moveItem(at: tmp, to: dest)
                // URLSession 的临时文件是 600，改成普通可读，方便拖给别的程序用
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest.path)
            } catch {
                self.fail(.saveFailed(error.localizedDescription))
                return
            }
            DispatchQueue.main.async {
                self.settle()
                self.onFinish?(.success(dest))
            }
        }.resume()
    }

    /// 文件名：作者_描述前20字_<awemeId>_<宽>x<高>.mp4
    private static func fileName(author: String, desc: String, awemeId: String, quality: Quality) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        func clean(_ s: String, _ limit: Int) -> String {
            let parts = s.components(separatedBy: illegal)
            let joined = parts.joined(separator: "_").trimmingCharacters(in: .whitespaces)
            return joined.count > limit ? String(joined.prefix(limit)) : joined
        }
        let a = clean(author, 24)
        let d = clean(desc, 20)
        let head = d.isEmpty ? a : "\(a)_\(d)"
        let dims = quality.width > 0 ? "\(quality.width)x\(quality.height)" : "fallback"
        return "\(head)_\(awemeId)_\(dims).mp4"
    }

    private static func uniqueURL(in dir: URL, name: String) -> URL {
        var url = dir.appendingPathComponent(name)
        var i = 2
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) (\(i)).\(ext)")
            i += 1
        }
        return url
    }

    // MARK: - 收尾

    private func fail(_ error: DownloadError) {
        DispatchQueue.main.async {
            guard !self.settled else { return }
            self.settle()
            self.onFinish?(.failure(error))
        }
    }

    private func settle() {
        settled = true
        timeoutWork?.cancel()
        timeoutWork = nil
        hiddenWindow?.orderOut(nil)
        hiddenWindow = nil
        webView?.stopLoading()
        webView = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("⚠️ 抖音页面加载失败: \(error.localizedDescription)")
    }

    // MARK: - 自检（命令行跑一遍完整流程，用来验证解析+下载没坏）
    // swift run AIUsageMonitor --douyin-selfcheck <作品链接>

    static func runSelfCheck(link: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var done = false
        shared.download(link: link) { message in
            print("·", message)
        } completion: { result in
            switch result {
            case .success(let url):
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? Int) ?? 0
                print("✅ 保存成功: \(url.path) (\(size) 字节)")
                done = true
            case .failure(let error):
                print("❌ 失败: \(error.localizedDescription)")
            }
            done = true
        }
        let deadline = Date().addingTimeInterval(60)
        while !done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
        exit(done ? 0 : 1)
    }
}
