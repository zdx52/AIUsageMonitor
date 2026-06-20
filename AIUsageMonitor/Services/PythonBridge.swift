import Foundation

class PythonBridge {
    
    // MARK: - DeepSeek 今日消耗获取
    
    static func fetchDeepSeekUsage() async -> DeepSeekUsage? {
        if let todayCost = await DeepSeekUsageScraper.fetchTodayUsage() {
            return DeepSeekUsage(
                totalBalance: 0,
                grantedBalance: 0,
                toppedUpBalance: 0,
                todayCost: todayCost,
                currency: "CNY"
            )
        }
        return nil
    }
    
    // MARK: - Tavily 用量获取
    
    static func fetchTavilyUsage() async -> TavilyUsage? {
        return await TavilyService.fetchUsage()
    }
}
