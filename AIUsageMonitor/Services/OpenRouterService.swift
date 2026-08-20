import Foundation

/// OpenRouter 账户用量查询。
///
/// 端点：
/// - GET  https://openrouter.ai/api/v1/credits           → 账户充值总额/使用额
/// - POST https://openrouter.ai/api/v1/analytics/query   → 按 day 分组的花费（当日使用）
///
/// 需 Management Key（openrouter.ai → Settings → Keys → 创建 Management Key）。
/// 普通 API Key 调用返回 403 "Only management keys can perform this operation"。
/// Management Key 不能做模型请求，只读、免费。
///
/// 账户级可用余额 = total_credits - total_usage。
/// 当日花费 = analytics 查询中 `total_usage` 按 `day` 分组、取今天的行。
///
/// 网络策略：直连 session（connectionProxyDictionary = [:]），
/// 实测直连 0.7s 优于走 10808 代理 3.7s，且不受多请求并发挤占代理影响。
/// 经验详见 docs/solutions/deployment/keychain-acl-resign.md。
class OpenRouterService {

    /// 直连 session：绕过系统代理，避免并发拖慢
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }()

    static func fetchUsage() async -> OpenRouterUsage? {
        guard let apiKey = KeychainHelper.get(key: "openrouter_management_key"), !apiKey.isEmpty else {
            NSLog("⚠️ OpenRouter: Management Key 未设置")
            return nil
        }
        let todaySpend: Double? = await fetchTodaySpend(apiKey: apiKey)

        guard let url = URL(string: "https://openrouter.ai/api/v1/credits") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            // 网络层失败诊断
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? "no body"
                print("❌ OpenRouter HTTP \(http.statusCode): \(body)")
                return nil
            }

            let parsed: OpenRouterCreditsResponse
            do {
                parsed = try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data)
            } catch {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? "no body"
                print("❌ OpenRouter 响应解析失败: \(error.localizedDescription), body: \(body)")
                return nil
            }

            guard let d = parsed.data else {
                print("❌ OpenRouter 响应缺少 data")
                return nil
            }

            return OpenRouterUsage(
                totalCredits: d.totalCredits ?? 0,
                totalUsage: d.totalUsage ?? 0,
                todaySpend: todaySpend
            )
        } catch {
            print("❌ OpenRouter 请求失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 查询当天（UTC 日）的花费（USD）。失败返回 nil（不影响余额卡片展示）。
    /// 请求 body：
    ///   {
    ///     "metrics": ["total_usage"],
    ///     "granularity": "day",
    ///     "time_range": { "start": "<今天00:00 Z>", "end": "<明天00:00 Z>" }
    ///   }
    /// 响应 data.data 里每行含 `created_at__day`（或 `date__day`）+ `total_usage`。
    private static func fetchTodaySpend(apiKey: String) async -> Double? {
        guard let url = URL(string: "https://openrouter.ai/api/v1/analytics/query") else { return nil }

        // UTC 日历下的今天 00:00 → 明天 00:00
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start)!

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let body: [String: Any] = [
            "metrics": ["total_usage"],
            "granularity": "day",
            "time_range": [
                "start": iso.string(from: start),
                "end": iso.string(from: end)
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? "no body"
                print("❌ OpenRouter Analytics HTTP \(http.statusCode): \(body)")
                return nil
            }

            let parsed: OpenRouterAnalyticsResponse
            do {
                parsed = try JSONDecoder().decode(OpenRouterAnalyticsResponse.self, from: data)
            } catch {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? "no body"
                print("❌ OpenRouter Analytics 解析失败: \(error.localizedDescription), body: \(body)")
                return nil
            }

            return parsed.data.rows.reduce(0) { $0 + ($1.totalUsage ?? 0) }
        } catch {
            print("❌ OpenRouter Analytics 请求失败: \(error.localizedDescription)")
            return nil
        }
    }
}