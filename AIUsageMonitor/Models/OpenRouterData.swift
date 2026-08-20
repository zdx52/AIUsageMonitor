import Foundation

// MARK: - API 响应模型（GET https://openrouter.ai/api/v1/credits）
//
// 需 Management Key（普通 API Key 调用会返回 403 "Only management keys can
// perform this operation"）。返回该账户「已充值总额」与「已使用额」：
//
//   { "data": { "total_credits": 100.5, "total_usage": 25.75 } }
//
// 余额（当前可用）= total_credits - total_usage。

struct OpenRouterCreditsResponse: Codable {
    let data: Data?

    struct Data: Codable {
        let totalCredits: Double?
        let totalUsage: Double?

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }
}

// MARK: - API 响应模型（POST https://openrouter.ai/api/v1/analytics/query）
//
// 官方 Analytics API（beta）。用 Management Key 按 day 分组返回当日花费。
// 请求 body：{ "metrics": ["total_usage"], "granularity": "day",
//              "time_range": {"start","end"} }
// 响应：{ "data": { "data": [ { "<created_at__day|date__day>": "...",
//                              "total_usage": <number 或 string> } ],
//                   "metadata": {...} } }
//
// 注意：字段名是 created_at__day 或 date__day（两种前缀都见过）；total_usage
// 在官方文档示例里是数字，但 count 类指标可能返回字符串，所以这里防御式地
// 接受 number/string 两种。

struct OpenRouterAnalyticsResponse: Codable {
    let data: Data

    struct Data: Codable {
        let rows: [AnalyticsRow]

        enum CodingKeys: String, CodingKey {
            case rows = "data"
        }
    }

    struct AnalyticsRow: Codable {
        /// 日期（取 created_at__day 或 date__day 之一）
        let day: String?
        /// 当日花费（USD，可能是数字或字符串）
        let totalUsage: Double?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: RawKey.self)
            struct RawKey: CodingKey {
                var stringValue: String; var intValue: Int?
                init?(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { self.intValue = intValue; stringValue = "\(intValue)" }
            }
            // day 键名可能是 created_at__day 或 date__day
            if let s = try? c.decode(String.self, forKey: RawKey(stringValue: "created_at__day")!) {
                day = s
            } else {
                day = try? c.decode(String.self, forKey: RawKey(stringValue: "date__day")!)
            }
            // total_usage 可能是数字或字符串
            if let dv = try? c.decode(Double.self, forKey: RawKey(stringValue: "total_usage")!) {
                totalUsage = dv
            } else if let sv = try? c.decode(String.self, forKey: RawKey(stringValue: "total_usage")!) {
                totalUsage = Double(sv)
            } else {
                totalUsage = nil
            }
        }
    }
}

// MARK: - 业务数据模型

/// OpenRouter 账户充值 / 用量快照。
/// 用 `total_credits - total_usage` 算当前可用余额。
struct OpenRouterUsage: Equatable {
    /// 已充值总额（USD）
    var totalCredits: Double
    /// 已使用额（USD）
    var totalUsage: Double
    /// 当日花费（USD，UTC 日对齐）。nil 表示当日查询失败/未配置
    var todaySpend: Double? = nil

    /// 是否有真实订阅数据（充值额 > 0）
    var hasUsageData: Bool {
        totalCredits > 0
    }

    /// 当前可用余额（USD），不会为负
    var remaining: Double {
        max(0, totalCredits - totalUsage)
    }

    /// 已用百分比（0~100）；totalCredits 为 0 时返回 0
    var usedPercent: Double {
        guard totalCredits > 0 else { return 0 }
        return min(100, max(0, totalUsage / totalCredits * 100))
    }
}