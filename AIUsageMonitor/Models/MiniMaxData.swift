import Foundation

// MARK: - API 响应模型（GET https://api.minimaxi.com/v1/token_plan/remains）
//
// 中国区 Token Plan 订阅用量查询。返回 base_resp + model_remains 数组，
// 每个元素对应一个模型族（general / video / ...）的窗口用量与限流状态。
//
// 重要：官方文档字段名（remains_time_window_hours 等）与实际响应不符。
// 真实 payload 结构（实测 2026-08-19）见 MiniMaxModelRemainsResponse。

struct MiniMaxTokenPlanResponse: Codable {
    let baseResp: BaseResp?
    let modelRemains: [ModelRemains]?

    enum CodingKeys: String, CodingKey {
        case baseResp = "base_resp"
        case modelRemains = "model_remains"
    }

    struct BaseResp: Codable {
        let statusCode: Int
        let statusMsg: String?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case statusMsg = "status_msg"
        }
    }

    /// 单个模型的窗口用量。limit/usage 都是相对计数（如调用次数），
    /// percent 才是用户最直观的展示数据。
    struct ModelRemains: Codable {
        let modelName: String?
        let startTime: Int64?
        let endTime: Int64?
        let remainsTime: Int64?
        let currentIntervalTotalCount: Int?
        let currentIntervalUsageCount: Int?
        let currentIntervalRemainingPercent: Int?
        let currentIntervalStatus: Int?
        let weeklyStartTime: Int64?
        let weeklyEndTime: Int64?
        let weeklyRemainsTime: Int64?
        let currentWeeklyTotalCount: Int?
        let currentWeeklyUsageCount: Int?
        let currentWeeklyRemainingPercent: Int?
        let currentWeeklyStatus: Int?

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case startTime = "start_time"
            case endTime = "end_time"
            case remainsTime = "remains_time"
            case currentIntervalTotalCount = "current_interval_total_count"
            case currentIntervalUsageCount = "current_interval_usage_count"
            case currentIntervalRemainingPercent = "current_interval_remaining_percent"
            case currentIntervalStatus = "current_interval_status"
            case weeklyStartTime = "weekly_start_time"
            case weeklyEndTime = "weekly_end_time"
            case weeklyRemainsTime = "weekly_remains_time"
            case currentWeeklyTotalCount = "current_weekly_total_count"
            case currentWeeklyUsageCount = "current_weekly_usage_count"
            case currentWeeklyRemainingPercent = "current_weekly_remaining_percent"
            case currentWeeklyStatus = "current_weekly_status"
        }
    }
}

// MARK: - 业务数据模型（按 model 聚合）

/// 单个模型族（general / video / ...）的窗口用量快照。
struct MiniMaxModelUsage: Equatable {
    let modelName: String

    /// 5h 窗口剩余百分比（0~100）；nil 表示字段未返回
    var intervalRemainingPercent: Int?
    /// 5h 窗口总/已用配额（次数）
    var intervalTotal: Int?
    var intervalUsed: Int?
    /// 5h 窗口状态：1=normal, 3=limited（具体状态码待官方文档确认）
    var intervalStatus: Int?
    /// 5h 窗口剩余毫秒（用来算窗口何时重置）
    var intervalRemainsMs: Int64?
    var intervalEndAt: Int64?

    /// 周窗口剩余百分比（0~100）
    var weeklyRemainingPercent: Int?
    var weeklyTotal: Int?
    var weeklyUsed: Int?
    var weeklyStatus: Int?
    var weeklyRemainsMs: Int64?
    var weeklyEndAt: Int64?
}

/// Token Plan 用量聚合（所有模型族 + 整体状态）。
struct MiniMaxUsage: Equatable {
    /// 各模型族快照
    var models: [MiniMaxModelUsage] = []
    /// 整体诊断：base_resp.status_code，0=成功，其它见 MiniMaxStatusTranslator
    var statusCode: Int?
    var statusMsg: String?
    /// 是否有真实订阅响应（false 表示 status != 0 或 model_remains 缺失）
    var hasSubscriptionData: Bool {
        !models.isEmpty
    }
}