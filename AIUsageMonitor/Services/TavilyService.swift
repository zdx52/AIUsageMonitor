import Foundation

class TavilyService {
    
    static func fetchUsage() async -> TavilyUsage? {
        // 从 Keychain 读取 API Key
        guard let apiKey = KeychainHelper.get(key: "tavily_api_key"), !apiKey.isEmpty else {
            return nil
        }
        
        guard let url = URL(string: "https://api.tavily.com/usage") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            let usageResponse = try decoder.decode(TavilyUsageResponse.self, from: data)
            
            let plan = usageResponse.account.currentPlan
            let creditsUsed = usageResponse.account.planUsage
            let monthlyLimit = usageResponse.account.planLimit
            let remaining = max(0, monthlyLimit - creditsUsed)
            
            return TavilyUsage(
                plan: plan,
                monthlyLimit: monthlyLimit,
                creditsUsed: creditsUsed,
                remaining: remaining,
                createdAt: ""
            )
        } catch {
            print("❌ Tavily API 请求失败: \(error.localizedDescription)")
            return nil
        }
    }
}
