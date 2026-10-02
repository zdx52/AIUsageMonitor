import Foundation

// MARK: - OpenCode RPC 响应模型

struct OpenCodeRPCResponse: Codable {
    let usagePercent: Double?
    let resetInSec: Int?
    let plan: String?
    let totalUsed: Int?
    let totalLimit: Int?
    let remaining: Int?
    let useBalance: Bool?
    
    enum CodingKeys: String, CodingKey {
        case usagePercent
        case resetInSec
        case plan
        case totalUsed
        case totalLimit
        case remaining
        case useBalance
    }
}

// MARK: - 错误状态

enum OpenCodeStatus: Equatable {
    case notConfigured
    case noCookies
    case needsLogin
    case fetchFailed
    case success
}

// MARK: - Go API 用量响应（API key 直查，实测可用）
//
// 端点：GET https://opencode.ai/zen/go/v1/usage
// 鉴权：Authorization: Bearer <Go API key>（console 订阅页复制）
// 实测（2026-09-30）：无 key → 401 AuthError；有 key → 200，结构如下。
// 注意：官方 docs 未公开此端点；Zen 按量余额无对应端点（GitHub #10448 仍 open）。
struct OpenCodeGoUsageBucket: Codable {
    let status: String?
    let percent: Double?
    let resetsAt: String?
}

struct OpenCodeGoUsageResponse: Codable {
    let usage: OpenCodeGoUsageBuckets?

    struct OpenCodeGoUsageBuckets: Codable {
        let rolling: OpenCodeGoUsageBucket?
        let weekly: OpenCodeGoUsageBucket?
        let monthly: OpenCodeGoUsageBucket?
    }

    /// 映射到卡片业务模型（复用 rolling/weekly/monthly 三维度展示）。
    /// resetsAt 存成 Date，卡片渲染时算「天/小时/分钟」倒计时（每次重绘都刷新）。
    func toOpenCodeUsage() -> OpenCodeUsage? {
        guard let u = usage else { return nil }
        var out = OpenCodeUsage(
            rollingPercent: u.rolling?.percent,
            rollingResetAt: Self.parseISO(u.rolling?.resetsAt),
            weeklyPercent: u.weekly?.percent,
            weeklyResetAt: Self.parseISO(u.weekly?.resetsAt),
            monthlyPercent: u.monthly?.percent,
            monthlyResetAt: Self.parseISO(u.monthly?.resetsAt)
        )
        if let date = out.rollingResetAt {
            out.rpcResetInSec = max(0, Int(date.timeIntervalSinceNow))
        }
        out.status = .success
        guard out.rollingPercent != nil || out.weeklyPercent != nil || out.monthlyPercent != nil else {
            return nil
        }
        return out
    }

    /// "2026-09-30T19:16:15.131Z" → Date（带毫秒需 withFractionalSeconds）。
    private static func parseISO(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}

// MARK: - 业务数据模型

struct OpenCodeUsage: Equatable {
    var usagePercentages: [Int]
    var bodyText: String
    var useBalance: Bool
    var needsLogin: Bool
    var status: OpenCodeStatus
    
    // RPC 数据字段
    var rpcUsagePercent: Double?
    var rpcResetInSec: Int?
    var rpcPlan: String?
    var rpcTotalUsed: Int?
    var rpcTotalLimit: Int?
    var rpcRemaining: Int?
    
    // 三种用量
    var rollingPercent: Double?    // 滚动用量
    var rollingResetAt: Date?      // 滚动重置时刻（渲染时算倒计时）
    var rollingReset: String?      // 滚动重置文案（页面抓取回退）
    var weeklyPercent: Double?     // 每周用量
    var weeklyResetAt: Date?       // 每周重置时刻
    var weeklyReset: String?       // 每周重置文案（页面抓取回退）
    var monthlyPercent: Double?    // 每月用量
    var monthlyResetAt: Date?      // 每月重置时刻
    var monthlyReset: String?      // 每月重置文案（页面抓取回退）

    /// 卡片「重置于」文案：有时刻走实时倒计时（天/小时/分钟），否则用抓取原文。
    var rollingResetText: String? { Self.resetText(rollingResetAt, rollingReset) }
    var weeklyResetText: String? { Self.resetText(weeklyResetAt, weeklyReset) }
    var monthlyResetText: String? { Self.resetText(monthlyResetAt, monthlyReset) }

    private static func resetText(_ date: Date?, _ fallback: String?) -> String? {
        guard let date else { return fallback }
        return countdownText(from: date)
    }

    init(usagePercentages: [Int] = [], bodyText: String = "", useBalance: Bool = false, needsLogin: Bool = false,
         status: OpenCodeStatus = .success,
         rpcUsagePercent: Double? = nil, rpcResetInSec: Int? = nil, rpcPlan: String? = nil,
         rpcTotalUsed: Int? = nil, rpcTotalLimit: Int? = nil, rpcRemaining: Int? = nil,
         rollingPercent: Double? = nil, rollingReset: String? = nil, rollingResetAt: Date? = nil,
         weeklyPercent: Double? = nil, weeklyReset: String? = nil, weeklyResetAt: Date? = nil,
         monthlyPercent: Double? = nil, monthlyReset: String? = nil, monthlyResetAt: Date? = nil) {
        self.usagePercentages = usagePercentages
        self.bodyText = bodyText
        self.useBalance = useBalance
        self.needsLogin = needsLogin
        self.status = status
        self.rpcUsagePercent = rpcUsagePercent
        self.rpcResetInSec = rpcResetInSec
        self.rpcPlan = rpcPlan
        self.rpcTotalUsed = rpcTotalUsed
        self.rpcTotalLimit = rpcTotalLimit
        self.rpcRemaining = rpcRemaining
        self.rollingPercent = rollingPercent
        self.rollingReset = rollingReset
        self.rollingResetAt = rollingResetAt
        self.weeklyPercent = weeklyPercent
        self.weeklyReset = weeklyReset
        self.weeklyResetAt = weeklyResetAt
        self.monthlyPercent = monthlyPercent
        self.monthlyReset = monthlyReset
        self.monthlyResetAt = monthlyResetAt
    }
}
