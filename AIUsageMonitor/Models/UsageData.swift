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
    @Published var openCodeUsage: OpenCodeUsage?
    @Published var openCodeNeedsLogin: Bool = false
    @Published var openCodeStatus: OpenCodeStatus = .notConfigured
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
        async let ocUsage = PythonBridge.fetchOpenCodeUsage()
        
        let ds = await dsBalance
        let dsUsageData = await dsUsage
        let tavilyData = await tvUsage
        let openCodeData = await ocUsage
        
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
            
            // OpenCode
            if let oc = openCodeData {
                self.openCodeUsage = oc
                self.openCodeNeedsLogin = oc.needsLogin
                self.openCodeStatus = oc.status
            } else {
                let url = UserDefaults.standard.string(forKey: "openCodeWorkspaceURL") ?? ""
                if url.isEmpty {
                    self.openCodeStatus = .notConfigured
                    self.openCodeNeedsLogin = false
                } else {
                    // 有 URL 但获取失败 → 可能是 cookie 过期
                    self.openCodeStatus = .fetchFailed
                    self.openCodeNeedsLogin = true
                    self.openCodeUsage = OpenCodeUsage(status: .fetchFailed)
                }
            }
            
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
        
        // OpenCode: 根据状态显示不同图标
        switch openCodeStatus {
        case .notConfigured:
            break // 不显示
        case .noCookies, .needsLogin:
            parts.append("OC ⚠️")
        case .fetchFailed:
            parts.append("OC ❌")
        case .success:
            if let oc = openCodeUsage {
                if let pct = oc.rpcUsagePercent {
                    parts.append("OC \(Int(pct))%")
                } else if let firstPct = oc.usagePercentages.first {
                    parts.append("OC \(firstPct)%")
                } else {
                    parts.append("OC ✅")
                }
            }
        }
        
        menuBarTitle = parts.joined(separator: " | ")
    }
}
