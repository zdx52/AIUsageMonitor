import Foundation

// MARK: - API 响应模型（Command Code alpha 用量端点）
//
// CLI `/usage` 命令使用的内部端点（非官方文档公开，实测可用）：
//   GET https://api.commandcode.ai/alpha/whoami            → 账号（orgId）
//   GET https://api.commandcode.ai/alpha/billing/credits   → credits + 5小时/每周窗口
//   GET https://api.commandcode.ai/alpha/billing/subscriptions → 当前订阅 plan
//   GET https://api.commandcode.ai/alpha/usage/summary     → 本期总花费/tokens
//
// 鉴权：Authorization: Bearer <API key>（与 CLI / Provider API 同一把 key）

struct CommandCodeCreditsResponse: Codable {
    struct Credits: Codable {
        let monthlyCredits: Double?
        let purchasedCredits: Double?
        let freeCredits: Double?
    }
    struct WindowLimit: Codable {
        let used: Double?
        let cap: Double?
        let resetAt: Int64?   // epoch 毫秒
    }
    struct WindowLimits: Codable {
        let fiveHour: WindowLimit?
        let weekly: WindowLimit?
    }
    let credits: Credits?
    let windowLimits: WindowLimits?
}

struct CommandCodeSubscriptionResponse: Codable {
    struct Data: Codable {
        let planId: String?
        let status: String?
        let currentPeriodStart: String?
        let currentPeriodEnd: String?
    }
    let data: Data?
}

struct CommandCodeSummaryResponse: Codable {
    let totalCost: Double?
    let totalCount: Int?
    let totalTokens: Double?
    let totalTokensIn: Double?
    let totalTokensOut: Double?
}

struct CommandCodeWhoamiResponse: Codable {
    struct User: Codable {
        let userName: String?
        let name: String?
    }
    struct Org: Codable {
        let login: String?
        let id: String?
    }
    let user: User?
    let org: Org?
}

// MARK: - 业务数据模型

/// Command Code GOAT 订阅用量快照。
struct CommandCodeUsage: Equatable {
    var plan: String?            // 例如 individual-goat
    var monthlyCredits: Double?  // 月度剩余 credits（GOAT = $70 的用量池）
    var monthlyCap: Double = 70  // 计划月度上限
    var fiveHourUsed: Double?    // 5 小时窗口已用
    var fiveHourCap: Double?     // 5 小时窗口上限（GOAT = $14）
    var weeklyUsed: Double?      // 每周窗口已用
    var weeklyCap: Double?       // 每周窗口上限（GOAT = $35）
    var resetAt: Date?           // 每周窗口重置时间
    var fiveHourResetAt: Date?   // 5小时窗口重置时间
    var monthlyResetAt: Date?    // 月度额度重置时间（billing period 结束）
    var periodTotalCost: Double? // 本期（billing period）总花费
    var periodTotalCount: Int?   // 本期请求数
    var periodTotalTokens: Double? // 本期总 tokens
    var status: String?          // 订阅状态（active 等）

    var hasUsageData: Bool {
        monthlyCredits != nil || fiveHourUsed != nil || weeklyUsed != nil
    }

    /// 月度使用百分比（0~100）
    var monthlyUsedPercent: Double {
        guard monthlyCap > 0, let mc = monthlyCredits else { return 0 }
        return min(100, max(0, (monthlyCap - mc) / monthlyCap * 100))
    }
}
