import Foundation

/// Command Code 账户用量查询（GOAT / Pro / Max 订阅）。
///
/// 端点（CLI `/usage` 同源，实测可用，非公开文档）：
/// - GET https://api.commandcode.ai/alpha/whoami               → 账号/orgId
/// - GET https://api.commandcode.ai/alpha/billing/credits      → credits + 窗口
/// - GET https://api.commandcode.ai/alpha/billing/subscriptions→ plan/周期
/// - GET https://api.commandcode.ai/alpha/usage/summary        → 本期花费/tokens
///
/// 鉴权：同一把 API key（Bearer），CLI / Provider API / alpha 端点通用。
class CommandCodeService {

    private static let baseURL = "https://api.commandcode.ai"

    static func fetchUsage() async -> CommandCodeUsage? {
        guard let apiKey = KeychainHelper.get(key: "commandcode_api_key"), !apiKey.isEmpty else {
            NSLog("⚠️ CommandCode: API Key 未设置")
            return nil
        }

        let whoami = await get("/alpha/whoami", apiKey: apiKey) as CommandCodeWhoamiResponse?
        let orgId = whoami?.org?.id

        async let creditsReq = get("/alpha/billing/credits" + orgQuery(orgId), apiKey: apiKey) as CommandCodeCreditsResponse?
        async let subReq = get("/alpha/billing/subscriptions" + orgQuery(orgId), apiKey: apiKey) as CommandCodeSubscriptionResponse?
        async let summaryReq = get("/alpha/usage/summary" + orgQuery(orgId), apiKey: apiKey) as CommandCodeSummaryResponse?

        let credits = await creditsReq
        let sub = await subReq
        let summary = await summaryReq

        var usage = CommandCodeUsage()
        usage.plan = sub?.data?.planId
        usage.status = sub?.data?.status

        if let c = credits?.credits {
            usage.monthlyCredits = c.monthlyCredits
        }
        if let wl = credits?.windowLimits {
            usage.fiveHourUsed = wl.fiveHour?.used
            usage.fiveHourCap = wl.fiveHour?.cap ?? usage.fiveHourCap
            usage.weeklyUsed = wl.weekly?.used
            usage.weeklyCap = wl.weekly?.cap ?? usage.weeklyCap
            if let reset = wl.fiveHour?.resetAt {
                usage.fiveHourResetAt = Date(timeIntervalSince1970: TimeInterval(reset) / 1000)
            }
            if let reset = wl.weekly?.resetAt {
                usage.resetAt = Date(timeIntervalSince1970: TimeInterval(reset) / 1000)
            }
        }
        if let s = summary {
            usage.periodTotalCost = s.totalCost
            usage.periodTotalCount = s.totalCount
            usage.periodTotalTokens = s.totalTokens ?? s.totalTokensIn
        }
        if let periodEnd = sub?.data?.currentPeriodEnd {
            // API 返回带毫秒（.000Z），默认 ISO8601 解析不了，需开 withFractionalSeconds
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            usage.monthlyResetAt = f.date(from: periodEnd) ?? ISO8601DateFormatter().date(from: periodEnd)
        }

        return usage.hasUsageData ? usage : nil
    }

    // MARK: - 请求

    private static func orgQuery(_ orgId: String?) -> String {
        orgId.map { "?orgId=\($0)" } ?? ""
    }

    private static func get<T: Decodable>(_ path: String, apiKey: String) async -> T? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? "no body"
                print("❌ CommandCode HTTP \(http.statusCode) \(path): \(body)")
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("❌ CommandCode 请求失败 \(path): \(error.localizedDescription)")
            return nil
        }
    }
}
