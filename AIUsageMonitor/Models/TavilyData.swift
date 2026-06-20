import Foundation

// MARK: - API 响应模型

struct TavilyUsageResponse: Codable {
    let key: KeyUsage
    let account: AccountUsage
    
    struct KeyUsage: Codable {
        let usage: Int
        let limit: Int
        let searchUsage: Int
        let crawlUsage: Int
        let extractUsage: Int
        let mapUsage: Int
        let researchUsage: Int
    }
    
    struct AccountUsage: Codable {
        let currentPlan: String
        let planUsage: Int
        let planLimit: Int
        let searchUsage: Int
        let crawlUsage: Int
        let extractUsage: Int
        let mapUsage: Int
        let researchUsage: Int
        let paygoUsage: Int
        let paygoLimit: Int?
    }
}

// MARK: - 业务数据模型

struct TavilyUsage: Equatable {
    var plan: String
    var monthlyLimit: Int
    var creditsUsed: Int
    var remaining: Int
    let createdAt: String
}
