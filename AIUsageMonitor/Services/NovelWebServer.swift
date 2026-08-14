import Foundation

/// 小说 Web UI（Flask，端口 8080）进程管理
/// web/ 目录随项目维护，用 web/.venv 的 Python 运行 web/app.py
enum NovelWebServer {

    /// 项目根目录（web/ 的父目录）。
    /// 默认源码目录，可用 UserDefaults 键 "novelWebProjectPath" 覆盖。
    static var projectPath: String {
        UserDefaults.standard.string(forKey: "novelWebProjectPath")
            ?? "/Users/zdx52/Documents/Hermes/AIUsageMonitor"
    }

    static var baseURL: URL { URL(string: "http://localhost:8080")! }

    private static var serverProcess: Process?
    private static var starting = false

    /// Flask 是否已在运行（探测 8080 首页）
    static func isRunning() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var ok = false
        var request = URLRequest(url: baseURL, timeoutInterval: 1.5)
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                ok = true
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        return ok
    }

    /// 确保服务运行；就绪后回调 true
    static func ensureRunning(completion: @escaping (Bool) -> Void) {
        if isRunning() {
            completion(true)
            return
        }
        guard !starting else {
            pollReady(timeout: 20) { completion($0) }
            return
        }
        starting = true
        guard launchProcess() else {
            starting = false
            completion(false)
            return
        }
        pollReady(timeout: 20) { ok in
            starting = false
            completion(ok)
        }
    }

    private static func launchProcess() -> Bool {
        let project = projectPath
        let python = project + "/web/.venv/bin/python"
        guard FileManager.default.fileExists(atPath: python) else {
            print("❌ 小说 Web 未找到 Python 环境: \(python)")
            return false
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = ["web/app.py"]
        proc.currentDirectoryURL = URL(fileURLWithPath: project)
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            serverProcess = proc
            print("🚀 小说 Web 启动中: \(python) web/app.py")
            return true
        } catch {
            print("❌ 小说 Web 启动失败: \(error.localizedDescription)")
            return false
        }
    }

    private static func pollReady(timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func check() {
            if isRunning() {
                completion(true)
                return
            }
            if Date() >= deadline {
                completion(false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { check() }
        }
        check()
    }

    /// 应用退出时清理由本应用拉起的进程（不碰外部已运行的实例）
    static func shutdown() {
        serverProcess?.terminate()
        serverProcess = nil
    }
}
