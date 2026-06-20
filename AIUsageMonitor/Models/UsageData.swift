import Foundation

struct DeepSeekBalance: Codable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]
    
    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

struct BalanceInfo: Codable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String
    
    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

struct DeepSeekUsage: Equatable {
    var totalBalance: Double
    var grantedBalance: Double
    var toppedUpBalance: Double
    var todayCost: Double
    let currency: String
}

class DataStore: ObservableObject {
    @Published var menuBarTitle: String = "⏳ 加载中..."
    @Published var deepSeekBalance: DeepSeekUsage?
    @Published var tavilyUsage: TavilyUsage?
    @Published var lastRefreshTime: Date?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    func refreshAll() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        // 并行获取所有数据
        async let dsBalance = DeepSeekService.fetchBalance()
        async let dsUsage = PythonBridge.fetchDeepSeekUsage()
        async let tvUsage = PythonBridge.fetchTavilyUsage()
        
        let ds = await dsBalance
        let dsUsageData = await dsUsage
        let tavilyData = await tvUsage
        
        await MainActor.run {
            // 合并 DeepSeek 余额和今日消耗
            if var balance = ds {
                balance.todayCost = dsUsageData?.todayCost ?? 0
                self.deepSeekBalance = balance
            } else if let usageData = dsUsageData {
                self.deepSeekBalance = usageData
            } else {
                self.deepSeekBalance = nil
            }
            
            self.tavilyUsage = tavilyData
            self.lastRefreshTime = Date()
            self.isLoading = false
            
            self.updateMenuBarTitle()
        }
    }
    
    private func updateMenuBarTitle() {
        var parts: [String] = []
        
        if let ds = deepSeekBalance {
            parts.append("DS ¥\(String(format: "%.1f", ds.totalBalance))")
        } else {
            parts.append("DS --")
        }
        
        if let tv = tavilyUsage {
            parts.append("TV \(tv.remaining)/\(tv.monthlyLimit)")
        } else {
            parts.append("TV --")
        }
        
        menuBarTitle = parts.joined(separator: " | ")
    }
}
