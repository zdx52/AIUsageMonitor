import Foundation

/// Open Design AMR（Agentic Model Router）用量查询。
///
/// 没有可用的 HTTP 用量端点：API key（sk-amr-…）只能调 /v1/chat/completions 和 /v1/models，
/// /v1/usage、/v1/me、/v1/credits 全部 404（官方 issue #8674 待实现）。
/// 唯一能读到 5h / 7d 滚动窗口的是账号侧：本机 Open Design 自带 vela CLI 的
/// `billing preflight --workspace-id <id> --format json`，用已登录的会话鉴权。
enum OpenDesignService {

    // MARK: - 定位 vela / workspace

    /// Open Design 自带 CLI，不在 PATH 里；版本号在路径中，升级后会变，所以扫目录挑最新。
    static func velaPath() -> String? {
        if let custom = UserDefaults.standard.string(forKey: "openDesignVelaPath"),
           !custom.isEmpty, FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        let base = NSHomeDirectory()
            + "/Library/Application Support/Open Design/launcher/channels/stable/namespaces/release-stable/versions"
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
        for v in versions.sorted(by: versionAscending).reversed() {
            let path = base + "/" + v + "/payload/Open Design.app/Contents/Resources/open-design/bin/vela"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// workspace id 是固定的，但只出现在 App 日志里（`[od] hub events workspace verified workspaceId=…`）。
    /// ponytail: 日志里抓串，翻页/清理后可能失效；失效时在设置里手填一次即可。
    static func workspaceId() -> String? {
        if let custom = UserDefaults.standard.string(forKey: "openDesignWorkspaceId"),
           custom.count >= 20 {
            return custom
        }
        let base = NSHomeDirectory()
            + "/Library/Application Support/Open Design/namespaces/release-stable/logs"
        for rel in ["daemon/latest.log", "daemon/previous.log", "desktop/latest.log"] {
            guard let text = try? String(contentsOfFile: base + "/" + rel, encoding: .utf8) else { continue }
            if let id = firstMatch(#"workspaceId=([a-z0-9]{20,})"#, in: text) { return id }
        }
        return nil
    }

    // MARK: - 获取

    static func fetchUsage() async -> OpenDesignUsage? {
        guard let vela = velaPath() else {
            NSLog("⚠️ Open Design: 未找到 vela（App 未安装？）")
            return nil
        }
        guard let workspace = workspaceId() else {
            NSLog("⚠️ Open Design: 未找到 workspace id，请在设置里填写")
            return nil
        }
        guard let data = await runVela(vela, workspace: workspace) else { return nil }
        let usage = OpenDesignUsage.from(preflight: data)
        if usage == nil {
            NSLog("❌ Open Design: preflight 输出无法解析（vela 未登录？）")
        }
        return usage
    }

    private static func runVela(_ path: String, workspace: String) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["billing", "preflight", "--workspace-id", workspace, "--format", "json"]
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    NSLog("❌ Open Design: vela 启动失败 \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                // 读空管道必须早于 waitUntilExit，否则 64KB 缓冲打满会死锁
                let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: watchdog)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                watchdog.cancel()

                if process.terminationStatus != 0 {
                    let message = String(data: errData, encoding: .utf8) ?? ""
                    NSLog("❌ Open Design: vela preflight 退出码 \(process.terminationStatus) \(message.prefix(300))")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    // MARK: - 工具

    private static func versionAscending(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l < r }
        }
        return a < b
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
