import Foundation

// MARK: - vela `billing preflight --format json` 响应
//
// 数据来自本机 Open Design 自带的 vela CLI（不在 PATH 里，路径见 OpenDesignService）。
// amr-link.open-design.ai 的 API key 读不到任何用量端点（/v1/usage 等全 404），
// 只有账号侧 preflight 才带 Coding Plan 滚动窗口。

struct OpenDesignPreflight: Codable {
    struct Window: Codable {
        let durationSeconds: Int
        let usedCredits: String
        let limitCredits: String
        let resetsAt: String?
    }

    struct CodingPlan: Codable {
        let tier: String?
        let windows: [Window]
    }

    let balanceUsd: String?
    let codingPlan: CodingPlan?
}

// MARK: - 业务数据模型

/// Open Design AMR（Coding Plan）用量快照。
struct OpenDesignUsage: Equatable {
    struct Window: Equatable {
        let seconds: Int
        let usedCredits: Int
        let limitCredits: Int
        let resetsAt: Date?

        /// 已用百分比（0~100）
        var usedPercent: Double {
            guard limitCredits > 0 else { return 0 }
            return min(100, max(0, Double(usedCredits) / Double(limitCredits) * 100))
        }

        var label: String {
            let hours = seconds / 3600
            return hours >= 24 && hours % 24 == 0 ? "\(hours / 24)天" : "\(hours)小时"
        }
    }

    var tier: String?
    var balanceUsd: Double?
    var windows: [Window] = []

    /// 各窗口里最紧的那个已用百分比（用于健康度判断）
    var maxUsedPercent: Double {
        windows.map(\.usedPercent).max() ?? 0
    }
}

extension OpenDesignUsage {
    /// 解析 vela preflight 的 JSON；窗口为空视为失败（与 CLI 的校验口径一致）。
    static func from(preflight data: Data) -> OpenDesignUsage? {
        guard let raw = try? JSONDecoder().decode(OpenDesignPreflight.self, from: data),
              let plan = raw.codingPlan, !plan.windows.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return OpenDesignUsage(
            tier: plan.tier,
            balanceUsd: raw.balanceUsd.flatMap(Double.init),
            windows: plan.windows.map { w in
                Window(
                    seconds: w.durationSeconds,
                    usedCredits: Int(w.usedCredits) ?? 0,
                    limitCredits: Int(w.limitCredits) ?? 0,
                    resetsAt: w.resetsAt.flatMap { iso.date(from: $0) }
                )
            }
        )
    }
}
