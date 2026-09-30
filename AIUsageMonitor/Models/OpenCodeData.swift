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
    func toOpenCodeUsage() -> OpenCodeUsage? {
        guard let u = usage else { return nil }
        var out = OpenCodeUsage(
            rollingPercent: u.rolling?.percent,
            rollingReset: Self.displayReset(u.rolling?.resetsAt),
            weeklyPercent: u.weekly?.percent,
            weeklyReset: Self.displayReset(u.weekly?.resetsAt),
            monthlyPercent: u.monthly?.percent,
            monthlyReset: Self.displayReset(u.monthly?.resetsAt)
        )
        if let iso = u.rolling?.resetsAt, let date = Self.parseISO(iso) {
            out.rpcResetInSec = max(0, Int(date.timeIntervalSinceNow))
        }
        out.status = .success
        guard out.rollingPercent != nil || out.weeklyPercent != nil || out.monthlyPercent != nil else {
            return nil
        }
        return out
    }

    /// "2026-09-30T19:16:15.131Z" → "9月30日 19:16"（卡片"重置于"后接）。
    private static func displayReset(_ iso: String?) -> String? {
        guard let iso, let date = parseISO(iso) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: date)
    }

    private static func parseISO(_ iso: String) -> Date? {
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
    var rollingReset: String?      // 滚动重置时间
    var weeklyPercent: Double?     // 每周用量
    var weeklyReset: String?       // 每周重置时间
    var monthlyPercent: Double?    // 每月用量
    var monthlyReset: String?      // 每月重置时间
    
    init(usagePercentages: [Int] = [], bodyText: String = "", useBalance: Bool = false, needsLogin: Bool = false,
         status: OpenCodeStatus = .success,
         rpcUsagePercent: Double? = nil, rpcResetInSec: Int? = nil, rpcPlan: String? = nil,
         rpcTotalUsed: Int? = nil, rpcTotalLimit: Int? = nil, rpcRemaining: Int? = nil,
         rollingPercent: Double? = nil, rollingReset: String? = nil,
         weeklyPercent: Double? = nil, weeklyReset: String? = nil,
         monthlyPercent: Double? = nil, monthlyReset: String? = nil) {
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
        self.weeklyPercent = weeklyPercent
        self.weeklyReset = weeklyReset
        self.monthlyPercent = monthlyPercent
        self.monthlyReset = monthlyReset
    }
}
