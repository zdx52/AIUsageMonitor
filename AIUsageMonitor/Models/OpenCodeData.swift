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
