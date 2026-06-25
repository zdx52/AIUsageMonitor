import XCTest
@testable import AIUsageMonitor

final class ModelDecodingTests: XCTestCase {
    
    // MARK: - DeepSeek 解码
    
    func testDecodeDeepSeekBalance() throws {
        let json = """
        {
            "is_available": true,
            "balance_infos": [
                {
                    "currency": "CNY",
                    "total_balance": "42.50",
                    "granted_balance": "10.00",
                    "topped_up_balance": "32.50"
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(DeepSeekBalance.self, from: data)
        
        XCTAssertTrue(result.isAvailable)
        XCTAssertEqual(result.balanceInfos.count, 1)
        XCTAssertEqual(result.balanceInfos[0].currency, "CNY")
        XCTAssertEqual(result.balanceInfos[0].totalBalance, "42.50")
        XCTAssertEqual(result.balanceInfos[0].grantedBalance, "10.00")
        XCTAssertEqual(result.balanceInfos[0].toppedUpBalance, "32.50")
    }
    
    func testDecodeDeepSeekBalanceEmptyInfos() throws {
        let json = """
        {
            "is_available": false,
            "balance_infos": []
        }
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(DeepSeekBalance.self, from: data)
        
        XCTAssertFalse(result.isAvailable)
        XCTAssertTrue(result.balanceInfos.isEmpty)
    }
    
    // MARK: - Tavily 解码
    
    func testDecodeTavilyUsageResponse() throws {
        let json = """
        {
            "key": {
                "usage": 150,
                "limit": 1000,
                "search_usage": 80,
                "crawl_usage": 30,
                "extract_usage": 20,
                "map_usage": 10,
                "research_usage": 10
            },
            "account": {
                "current_plan": "free",
                "plan_usage": 150,
                "plan_limit": 1000,
                "search_usage": 80,
                "crawl_usage": 30,
                "extract_usage": 20,
                "map_usage": 10,
                "research_usage": 10,
                "paygo_usage": 0,
                "paygo_limit": null
            }
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(TavilyUsageResponse.self, from: data)
        
        XCTAssertEqual(result.account.currentPlan, "free")
        XCTAssertEqual(result.account.planUsage, 150)
        XCTAssertEqual(result.account.planLimit, 1000)
        
        let remaining = max(0, result.account.planLimit - result.account.planUsage)
        XCTAssertEqual(remaining, 850)
    }
    
    // MARK: - OpenCode RPC 解码
    
    func testDecodeOpenCodeRPCResponse() throws {
        let json = """
        {
            "usagePercent": 72.5,
            "resetInSec": 86400,
            "plan": "pro",
            "totalUsed": 725,
            "totalLimit": 1000,
            "remaining": 275,
            "useBalance": true
        }
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(OpenCodeRPCResponse.self, from: data)
        
        XCTAssertEqual(result.usagePercent, 72.5)
        XCTAssertEqual(result.resetInSec, 86400)
        XCTAssertEqual(result.plan, "pro")
        XCTAssertEqual(result.totalUsed, 725)
        XCTAssertEqual(result.totalLimit, 1000)
        XCTAssertEqual(result.remaining, 275)
        XCTAssertEqual(result.useBalance, true)
    }
    
    func testDecodeOpenCodeRPCResponsePartial() throws {
        let json = """
        {
            "usagePercent": 45.0,
            "plan": "free"
        }
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(OpenCodeRPCResponse.self, from: data)
        
        XCTAssertEqual(result.usagePercent, 45.0)
        XCTAssertNil(result.resetInSec)
        XCTAssertNil(result.totalUsed)
        XCTAssertEqual(result.plan, "free")
    }
    
    // MARK: - DeepSeekUsage 模型
    
    func testDeepSeekUsageInit() {
        let usage = DeepSeekUsage(
            totalBalance: 42.5,
            grantedBalance: 10.0,
            toppedUpBalance: 32.5,
            todayCost: 1.23,
            currency: "CNY"
        )
        
        XCTAssertEqual(usage.totalBalance, 42.5)
        XCTAssertEqual(usage.todayCost, 1.23)
        XCTAssertEqual(usage.currency, "CNY")
    }
    
    func testDeepSeekUsageEquality() {
        let a = DeepSeekUsage(totalBalance: 42.5, grantedBalance: 10, toppedUpBalance: 32.5, todayCost: 0, currency: "CNY")
        let b = DeepSeekUsage(totalBalance: 42.5, grantedBalance: 10, toppedUpBalance: 32.5, todayCost: 0, currency: "CNY")
        let c = DeepSeekUsage(totalBalance: 99.0, grantedBalance: 10, toppedUpBalance: 32.5, todayCost: 0, currency: "CNY")
        
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
    
    // MARK: - OpenCodeUsage 模型
    
    func testOpenCodeUsageDefaultInit() {
        let usage = OpenCodeUsage()
        
        XCTAssertFalse(usage.useBalance)
        XCTAssertFalse(usage.needsLogin)
        XCTAssertEqual(usage.status, .success)
        XCTAssertNil(usage.rpcUsagePercent)
        XCTAssertTrue(usage.usagePercentages.isEmpty)
    }
    
    func testOpenCodeUsageWithThreeDimensions() {
        let usage = OpenCodeUsage(
            rollingPercent: 65.0,
            rollingReset: "23h",
            weeklyPercent: 40.0,
            weeklyReset: "5d",
            monthlyPercent: 25.0,
            monthlyReset: "20d"
        )
        
        XCTAssertEqual(usage.rollingPercent, 65.0)
        XCTAssertEqual(usage.weeklyPercent, 40.0)
        XCTAssertEqual(usage.monthlyPercent, 25.0)
        XCTAssertEqual(usage.rollingReset, "23h")
    }
    
    // MARK: - OpenCodeStatus
    
    func testOpenCodeStatusEquality() {
        XCTAssertEqual(OpenCodeStatus.notConfigured, OpenCodeStatus.notConfigured)
        XCTAssertNotEqual(OpenCodeStatus.notConfigured, OpenCodeStatus.needsLogin)
        XCTAssertEqual(OpenCodeStatus.noCookies, OpenCodeStatus.noCookies)
    }
}
