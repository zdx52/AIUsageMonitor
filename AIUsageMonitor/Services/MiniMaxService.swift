import Foundation

/// MiniMax 中国区（platform.minimaxi.com）Token Plan 订阅用量查询。
/// 单一端点：GET https://api.minimaxi.com/v1/token_plan/remains
///
/// 重要：实际响应（实测 2026-08-19）是 model_remains 数组，每个元素
/// 对应一个模型族（general / video / ...）。文档字段名（remains_time_window_hours
/// 等）与真实 payload 不符，已废弃。
///
/// 状态码语义（待官方确认，参考 minimax 整体文档）：
/// - base_resp.status_code == 0  → 成功
/// - 1004 / login fail            → Key 鉴权失败
/// - 2056                        → 窗口超额
/// - model_remains[i].current_interval_status / current_weekly_status:
///     1 = 正常, 3 = 限流中(待确认)
class MiniMaxService {

    /// 直连 session：中国区域名直连 0.7s 量级，绕过系统代理避免并发拖慢
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }()

    static func fetchTokenPlan() async -> MiniMaxUsage? {
        guard let apiKey = KeychainHelper.get(key: "minimax_subscription_key"), !apiKey.isEmpty else {
            NSLog("⚠️ MiniMax: 订阅 Key 未设置")
            return nil
        }

        guard let url = URL(string: "https://api.minimaxi.com/v1/token_plan/remains") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await session.data(for: request)

            // 网络层失败诊断
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? "no body"
                print("❌ MiniMax HTTP \(http.statusCode): \(body)")
                return nil
            }

            let decoder = JSONDecoder()
            let parsed: MiniMaxTokenPlanResponse
            do {
                parsed = try decoder.decode(MiniMaxTokenPlanResponse.self, from: data)
            } catch {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? "no body"
                print("❌ MiniMax 响应解析失败: \(error.localizedDescription), body: \(body)")
                return nil
            }

            guard let baseResp = parsed.baseResp else {
                print("❌ MiniMax 响应缺少 base_resp")
                return nil
            }

            // 业务错误：只返回 status 给 UI 显示
            guard baseResp.statusCode == 0 else {
                print("❌ MiniMax 业务错误: status=\(baseResp.statusCode) msg=\(baseResp.statusMsg ?? "")")
                return MiniMaxUsage(
                    models: [],
                    statusCode: baseResp.statusCode,
                    statusMsg: baseResp.statusMsg
                )
            }

            // 成功：聚合 model_remains
            let models: [MiniMaxModelUsage] = (parsed.modelRemains ?? []).map { mr in
                MiniMaxModelUsage(
                    modelName: mr.modelName ?? "—",
                    intervalRemainingPercent: mr.currentIntervalRemainingPercent,
                    intervalTotal: mr.currentIntervalTotalCount,
                    intervalUsed: mr.currentIntervalUsageCount,
                    intervalStatus: mr.currentIntervalStatus,
                    intervalRemainsMs: mr.remainsTime,
                    intervalEndAt: mr.endTime,
                    weeklyRemainingPercent: mr.currentWeeklyRemainingPercent,
                    weeklyTotal: mr.currentWeeklyTotalCount,
                    weeklyUsed: mr.currentWeeklyUsageCount,
                    weeklyStatus: mr.currentWeeklyStatus,
                    weeklyRemainsMs: mr.weeklyRemainsTime,
                    weeklyEndAt: mr.weeklyEndTime
                )
            }

            return MiniMaxUsage(
                models: models,
                statusCode: 0,
                statusMsg: baseResp.statusMsg
            )
        } catch {
            print("❌ MiniMax 请求失败: \(error.localizedDescription)")
            return nil
        }
    }
}