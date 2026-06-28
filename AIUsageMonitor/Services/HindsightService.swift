import Foundation

// MARK: - 数据模型

struct HindsightStats {
    let totalMemories: Int
    let experiences: Int
    let observations: Int
    let worldFacts: Int
    let totalDocuments: Int
    let serviceAvailable: Bool
}

// MARK: - Hindsight API 服务

class HindsightService {
    static let shared = HindsightService()
    private let baseURL = "http://localhost:9077"
    
    /// 检查 Hindsight 服务是否在线
    func checkHealth() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// 获取记忆统计
    func fetchStats() async -> HindsightStats? {
        // 1. 获取 banks 列表（含 fact_count）
        guard let bankURL = URL(string: "\(baseURL)/v1/default/banks") else { return nil }
        var factCount = 0
        do {
            let (data, _) = try await URLSession.shared.data(from: bankURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let banks = json["banks"] as? [[String: Any]],
               let first = banks.first {
                factCount = first["fact_count"] as? Int ?? 0
            }
        } catch {
            return nil
        }
        
        // 2. 获取详细统计
        guard let statsURL = URL(string: "\(baseURL)/v1/default/banks/hermes/stats") else {
            return HindsightStats(totalMemories: factCount, experiences: 0, observations: 0, worldFacts: 0, totalDocuments: 0, serviceAvailable: true)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: statsURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let totalNodes = json["total_nodes"] as? Int ?? factCount
                let totalDocs = json["total_documents"] as? Int ?? 0
                let byType = json["nodes_by_fact_type"] as? [String: Int] ?? [:]
                return HindsightStats(
                    totalMemories: totalNodes,
                    experiences: byType["experience"] ?? 0,
                    observations: byType["observation"] ?? 0,
                    worldFacts: byType["world"] ?? 0,
                    totalDocuments: totalDocs,
                    serviceAvailable: true
                )
            }
        } catch {
            return HindsightStats(totalMemories: factCount, experiences: 0, observations: 0, worldFacts: 0, totalDocuments: 0, serviceAvailable: true)
        }
        
        return nil
    }
}
