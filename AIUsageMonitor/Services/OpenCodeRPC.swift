import Foundation
import WebKit

class OpenCodeRPCClient {
    private let rpcHashes: [String: String] = [
        "lite.subscription.get": "c7389bd0e731f80f49593e5ee53835475f4e28594dd6bd83eb229bab753498cd",
        "go.referral.get": "2a0b2fef5fd2ec9eff0cb5d4955e4ada4eece21fac85591ed4c09630168d4844",
        "go.referral.usagePreview": "46625df0aecf05f270f7ae4612cde374d11350c8abaf8649027572228b8af150"
    ]

    // MARK: - Cookie 获取

    func getCookies(for domain: String) async -> [HTTPCookie] {
        return await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let filtered = cookies.filter { $0.domain.contains(domain) }
                continuation.resume(returning: filtered)
            }
        }
    }

    // MARK: - RPC 调用

    func callRPC(hash: String, body: Any) async -> Data? {
        guard let url = URL(string: "https://opencode.ai/_server?id=\(hash)") else {
            print("❌ OpenCode RPC URL 无效")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let cookieStorage = HTTPCookieStorage.shared
        let cookies = cookieStorage.cookies(for: URL(string: "https://opencode.ai")!) ?? []
        if cookies.isEmpty {
            print("⚠️ OpenCode RPC: HTTPCookieStorage 没有 cookie")
            let wkCookies = await getCookies(for: "opencode.ai")
            if wkCookies.isEmpty {
                print("⚠️ OpenCode RPC: 两个 cookie store 都没有 cookie，需要登录")
                return nil
            }
            let cookieHeader = wkCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        } else {
            let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        print("📡 OpenCode RPC 请求: \(url.lastPathComponent)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse {
                let logMsg = "📡 RPC status:\(httpResp.statusCode) body:\(String(data: data, encoding: .utf8)?.prefix(500) ?? "nil")"
                print(logMsg)
                if httpResp.statusCode != 200 {
                    return nil
                }
            }
            return data
        } catch {
            print("❌ OpenCode RPC 请求失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - RPC 响应解析

    func parseRPCResponse(_ data: Data) -> OpenCodeRPCResponse? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count >= 2 {
            if let resultObj = json[1] as? [String: Any] {
                let knownKeys: Set<String> = ["usagePercent", "resetInSec", "plan", "totalUsed", "totalLimit", "remaining", "useBalance"]
                let hasKnownKey = resultObj.keys.contains { knownKeys.contains($0) }

                if hasKnownKey,
                    let resultData = try? JSONSerialization.data(withJSONObject: resultObj) {
                    if let parsed = try? JSONDecoder().decode(OpenCodeRPCResponse.self, from: resultData) {
                        return parsed
                    }
                }
            }
        }

        if let parsed = try? JSONDecoder().decode(OpenCodeRPCResponse.self, from: data) {
            return parsed
        }

        return nil
    }

    // MARK: - 业务 RPC

    func callUsagePreviewRPC(workspaceID: String) async -> OpenCodeRPCResponse? {
        guard let previewHash = rpcHashes["go.referral.usagePreview"] else {
            print("❌ OpenCode 找不到 usagePreview 的 RPC 哈希")
            return nil
        }

        if let data = await callRPC(hash: previewHash, body: [workspaceID]) {
            if let result = parseRPCResponse(data) {
                return result
            }
        }

        guard let getHash = rpcHashes["go.referral.get"] else {
            print("❌ OpenCode 找不到 referral.get 的 RPC 哈希")
            return nil
        }

        if let data = await callRPC(hash: getHash, body: [workspaceID]) {
            if let result = parseRPCResponse(data) {
                return result
            }
        }

        return nil
    }

    // MARK: - Workspace ID 提取

    func extractWorkspaceID(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let components = url.pathComponents
        if let wrkIndex = components.firstIndex(of: "workspace"),
            wrkIndex + 1 < components.count {
            let candidate = components[wrkIndex + 1]
            if candidate.hasPrefix("wrk_") {
                return candidate
            }
        }
        return nil
    }
}
