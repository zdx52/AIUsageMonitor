import Foundation

class DeepSeekService {
    
    static func fetchBalance() async -> DeepSeekUsage? {
        guard let apiKey = KeychainHelper.get(key: "deepseek_api_key"), !apiKey.isEmpty else {
            print("⚠️ DeepSeek: API Key 未设置")
            return nil
        }
        
        print("🔑 DeepSeek: key found, making API call...")
        guard let url = URL(string: "https://api.deepseek.com/user/balance") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ DeepSeek API 返回非 HTTP 响应")
                return nil
            }
            
            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                print("❌ DeepSeek API 返回错误: \(httpResponse.statusCode), body: \(body)")
                return nil
            }
            
            let decoder = JSONDecoder()
            let balance = try decoder.decode(DeepSeekBalance.self, from: data)
            
            guard let firstInfo = balance.balanceInfos.first else {
                print("❌ DeepSeek: balanceInfos 为空")
                return nil
            }
            
            return DeepSeekUsage(
                totalBalance: Double(firstInfo.totalBalance) ?? 0,
                grantedBalance: Double(firstInfo.grantedBalance) ?? 0,
                toppedUpBalance: Double(firstInfo.toppedUpBalance) ?? 0,
                todayCost: 0, // API 不提供当日消耗，后续由 Playwright 获取
                currency: firstInfo.currency
            )
        } catch {
            print("❌ DeepSeek API 请求失败: \(error.localizedDescription)")
            return nil
        }
    }
}
