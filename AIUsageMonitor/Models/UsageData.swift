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

// MARK: - 服务健康度

enum ServiceHealth: Comparable {
    case healthy
    case warning
    case critical
}

@MainActor
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
    @Published var healthLevel: ServiceHealth = .healthy
    @Published var isOpenCodeLoggingIn = false
    @Published var tavilyRateLimited = false
    private var lastSuccessfulTavily: TavilyUsage?  // 限流时保留最后成功数据
    
    func refreshAll() async {
        isLoading = true
        errorMessage = nil
        
        // 并行获取所有数据
        async let dsBalance = DeepSeekService.fetchBalance()
        async let dsUsage = fetchDeepSeekUsage()
        async let tvUsage = fetchTavilyUsage()
        async let ocUsage = fetchOpenCodeUsage()
        
        let ds = await dsBalance
        let dsUsageData = await dsUsage
        let tavilyData = await tvUsage
        let openCodeData = await ocUsage
        
        // 合并 DeepSeek 余额和今日消耗
        if var balance = ds {
            balance.todayCost = dsUsageData?.todayCost ?? 0
            self.deepSeekBalance = balance
        } else if let usageData = dsUsageData {
            self.deepSeekBalance = usageData
        } else {
            self.deepSeekBalance = nil
        }
        
        if let tvData = tavilyData {
            if tvData.isRateLimited {
                // 限流时保留上次成功数据（如有），标记限流状态
                self.tavilyRateLimited = true
                if let cached = lastSuccessfulTavily {
                    self.tavilyUsage = cached
                } else {
                    self.tavilyUsage = nil
                }
            } else {
                self.tavilyUsage = tvData
                self.lastSuccessfulTavily = tvData
                self.tavilyRateLimited = false
            }
        } else if lastSuccessfulTavily != nil {
            self.tavilyRateLimited = true
        } else {
            self.tavilyUsage = nil
            self.tavilyRateLimited = false
        }
        
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
        
        self.updateHealthLevel()
        self.updateMenuBarTitle()
    }
    

    // MARK: - 数据获取（原 PythonBridge）

    private func fetchDeepSeekUsage() async -> DeepSeekUsage? {
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

    private func fetchTavilyUsage() async -> TavilyUsage? {
        return await TavilyService.fetchUsage()
    }

    private func fetchOpenCodeUsage() async -> OpenCodeUsage? {
        return await withTaskGroup(of: OpenCodeUsage?.self) { group in
            group.addTask {
                guard let url = UserDefaults.standard.string(forKey: "openCodeWorkspaceURL"),
                      !url.isEmpty else {
                    return nil
                }
                return await OpenCodeService.shared.fetchUsage(urlString: url)
            }
            // 15 秒超时兜底，避免 WKWebView 卡死整个刷新
            group.addTask {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                return nil
            }
            
            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            return nil
        }
    }
    
    private func updateHealthLevel() {
        // Critical 优先检查
        if let ds = deepSeekBalance, ds.totalBalance < 5 {
            healthLevel = .critical
            return
        }
        if openCodeStatus == .fetchFailed {
            healthLevel = .critical
            return
        }
        
        // Warning 检查
        if let ds = deepSeekBalance, ds.totalBalance < 20 {
            healthLevel = .warning
            return
        }
        if let tv = tavilyUsage, tv.monthlyLimit > 0,
           Double(tv.remaining) / Double(tv.monthlyLimit) < 0.25 {
            healthLevel = .warning
            return
        }
        if let oc = openCodeUsage, let pct = oc.rpcUsagePercent, pct > 80 {
            healthLevel = .warning
            return
        }
        if openCodeStatus == .noCookies || openCodeStatus == .needsLogin {
            healthLevel = .warning
            return
        }
        
        // 默认健康
        healthLevel = .healthy
    }
    
    private func updateMenuBarTitle() {
        let ud = UserDefaults.standard
        var parts: [String] = []

        if ud.bool(forKey: "showDeepSeek") {
            if let ds = deepSeekBalance {
                parts.append("DS ¥\(String(format: "%.1f", ds.totalBalance))")
            } else {
                parts.append("DS --")
            }
        }

        if ud.bool(forKey: "showTavily") {
            if let tv = tavilyUsage {
                parts.append("TV \(tv.remaining)/\(tv.monthlyLimit)")
            } else {
                parts.append("TV --")
            }
        }

        if ud.bool(forKey: "showOpenCode") {
            switch openCodeStatus {
            case .notConfigured:
                parts.append("OC --")
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
        }

        menuBarTitle = parts.isEmpty ? "--" : parts.joined(separator: " | ")
    }
}
