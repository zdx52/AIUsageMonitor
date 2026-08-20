---
title: OpenRouter 用量监控集成（余额 + 当日花费）
date: 2026-08-20
category: deployment
module: AIUsageMonitor 菜单栏卡片
problem_type: architecture_pattern
severity: medium
applies_when:
  - 在 AIUsageMonitor 或任意 Swift/macOS 应用里接入 OpenRouter 账户用量展示
  - 需要显示 OpenRouter 余额（充值制账户）和当日花费
  - 复用 `/credits` 与 Analytics API 的数据源接入模式
tags: [openrouter, analytics, credits, management-key, swift, usage-monitor, utc]
---

# OpenRouter 用量监控集成（余额 + 当日花费）

## Context

AIUsageMonitor 需新增 OpenRouter 用量标签页。用户最开始只想要余额，后补充要"当日使用"。初始只想到 `/api/v1/credits`（余额），当日使用需额外数据源。调研后发现 OpenRouter 有**官方 Analytics API（beta）**可按天分组返回花费。

另外项目历史：OpenRouter 卡片曾在 v1.7.0 被当"未引用死代码"删除，用户又要加回来——不要轻易删看似无用的监控卡片。

## Guidance

OpenRouter 账户用量有**两个互补端点**，都用 **Management Key**（普通 API Key 一律 403 `Only management keys can perform this operation`）：

| 需求 | 端点 | 说明 |
|---|---|---|
| 余额 | `GET https://openrouter.ai/api/v1/credits` | 返回 `{data:{total_credits,total_usage}}`。余额 = total_credits − total_usage |
| 当日花费 | `POST https://openrouter.ai/api/v1/analytics/query`（beta） | 按 day 分组，取当天的 `total_usage` |

### 当日花费请求 body

```json
{
  "metrics": ["total_usage"],
  "granularity": "day",
  "time_range": { "start": "2026-08-20T00:00:00Z", "end": "2026-08-21T00:00:00Z" }
}
```

- **Management Key**：openrouter.ai → Settings → Keys → 创建 Management Key
- **时区坑（关键）**：Analytics API 按 **UTC 日**分组，非中国时区。UTC+8 用户看到的"当日"边界会与本地日历错开几小时，无法改，需在 UI/文档注明
- 请求用 `.ephemeral` + `connectionProxyDictionary = [:]` 强制直连（实测 0.7s 优于走代理 3.7s）

### 响应字段防御性解析（beta API 两个坑）

1. **日期键名不固定**：时序列主键可能是 `created_at__day` 或 `date__day`（两种前缀都见过），要两者都尝试
2. **total_usage 类型不稳定**：官方文档示例是数字，但 count 类指标可能返回字符串。Swift 里用自定义 `init(from:)` 分别尝试 `Double` 和 `String` 解码

```swift
// Swift 防御解码：total_usage 数字或字符串都能处理
if let dv = try? c.decode(Double.self, forKey: key) {
    totalUsage = dv
} else if let sv = try? c.decode(String.self, forKey: key) {
    totalUsage = Double(sv)
} else {
    totalUsage = nil
}
```

### 数据结构（本仓库实现）

- `Models/OpenRouterData.swift` — `OpenRouterUsage{totalCredits,totalUsage,todaySpend?}`，`todaySpend` 为 nil 时卡片不显示"当日使用"行（余额不受影响，降级友好）
- `Services/OpenRouterService.swift` — `fetchUsage()` 并行拉 `/credits` + 当日 analytics；当日失败只置 nil，不拖垮余额
- 阈值：额度使用 ≥50% 橙色、≥80% 红色预警；健康指示 ≥75% 告警

## Why This Matters

- `/credits` 只有累计值，**没有"当日"维度**；没有 Analytics API 就无法满足"当日使用"需求
- Analytics API 是 beta，字段变化（日期键名前缀、类型字符串化）会直接导致解码失败——防御解析是必须不是可选项
- 忽略 UTC 日分组会让用户困惑"怎么当日数据不对"；提前注明避免误判 bug

## When to Apply

- 每次新增/维护 AIUsageMonitor 的 OpenRouter 卡片
- 任何需要 OpenRouter 余额 + 时间维度花费展示的场景
- 遇到 OpenRouter analytics 字段解析异常时

## Examples

真实余额计算（keychain-acl-resign 记录）：`GET /credits` → total_credits $10.00、total_usage $0.90 → 余额 $9.10。当日花费：analytics 按 UTC 日取今天的行求和。

## What Didn't Work / 弯路

- 起初以为当日数据在 `/api/v1/key` 或 `/generation` 端点——前者只有 key 的速率/信用上限，后者是单次请求维度，都非当日汇总。正确是 Analytics API
- Analytics API 是 beta，使用 `gh`/search 时靠官方 cookbook `analytics-cost-control` 拿到精确 body，别凭猜测；`/api/v1/analytics/meta` 可动态发现指标/维度
- 在 Swift 里用标准 `Codable` + `CodingKeys` 一次定义两个日期键名不行（键名不固定），需自定义 `init(from:)` 手解

## Prevention

- 卡片数据源保持"当日失败不影响余额"的降级（`todaySpend` 可空）
- 当 API 字段变化导致解码失败，先看 body（print 前 200 字符诊断），再定位是键名前缀还是类型问题
- 不要因"当前未引用"删除监控卡片——用户可能后续要求加回（本仓库 v1.7.0 删、v1.8.0 重做的教训）

## Related

- [keychain-acl-resign.md](./keychain-acl-resign.md) — 同 repo 的 OpenRouter Key 存储坑（ad-hoc 重签名使 keychain ACL 失联）；本文声称的直连策略也源于此
- [app-bundle-deploy.md](./app-bundle-deploy.md) — deploy.sh 重签名是上述 keychain 坑的源头