---
title: Command Code 用量监控集成（GOAT 订阅 /alpha 端点）
date: 2026-08-31
category: deployment
module: AIUsageMonitor 菜单栏卡片
problem_type: architecture_pattern
severity: medium
applies_when:
  - 在 AIUsageMonitor 或任意应用里接入 Command Code 订阅（GOAT/Pro/Max）用量展示
  - 需要显示 Command Code 月度额度 / 5小时 / 每周窗口
  - 复用 CLI `/usage` 的内部数据源
tags: [commandcode, goat, alpha, usage, swift, usage-monitor]
---

# Command Code 用量监控集成（GOAT 订阅）

## Context

用户要在 AIUsageMonitor 菜单栏监控 Command Code GOAT 订阅（$10/月 = $70 用量池）的使用率。

先查了官方文档：Provider API（`api.commandcode.ai/provider/v1`）只有 chat/completions、messages、models 三个端点，**没有任何用量/余额端点**；Studio 用量页在网页端，CLI `/usage` 命令能看窗口用量。官方文档未公开用量 REST API。

## Guidance

**关键发现：Command Code 存在内部 alpha 用量端点，CLI `/usage` 同源**（从社区实现 [patlux/pi-commandcode-provider](https://github.com/patlux/pi-commandcode-provider) 的 `src/quota.ts` 源码确认）。用**同一把 API key**（Bearer，与 CLI / Provider API 通用）：

| 端点 | 返回 | 关键字段 |
|---|---|---|
| `GET https://api.commandcode.ai/alpha/whoami` | 账号 | `user.userName`、`org.id`（组织用户才有） |
| `GET https://api.commandcode.ai/alpha/billing/credits?orgId=` | 额度 | `credits.monthlyCredits/purchasedCredits/freeCredits`、`windowLimits.fiveHour/weekly{used,cap,resetAt}` |
| `GET https://api.commandcode.ai/alpha/billing/subscriptions?orgId=` | 订阅 | `data.planId`（如 individual-goat）、`status`、`currentPeriodStart/End` |
| `GET https://api.commandcode.ai/alpha/usage/summary?orgId=&since=` | 本期汇总 | `totalCost/totalCount/totalTokens` |

实测（2026-08-31，用户 zdx52 GOAT 订阅）：
- credits: `{"credits":{"monthlyCredits":69.88,...},"windowLimits":{"fiveHour":{"used":0.12,"cap":14,"resetAt":1788127154493},"weekly":{"used":0.12,"cap":35,"resetAt":1788713954493}}}`
- 订阅: `planId=individual-goat, status=active`
- summary: `totalCost=0.088, totalCount=62, totalTokens=4383076`

### 关键点

1. **`resetAt` 是 epoch 毫秒**（13 位），转 Date 要 `/1000`
2. **`credits.monthlyCredits` 是「剩余」不是「已用」**：已用 = cap − monthlyCredits（GOAT cap = $70）
3. **orgId 参数**：个人用户 `org=null`，直接不传 `orgId` 参数即可；组织用户必须带
4. **鉴权**：`Authorization: Bearer <api key>`，与 CLI/Provider 同一把 key，无额外权限
5. 失败降级：任一端点失败只影响对应字段，卡片其余照常显示

## Why This Matters

- 官方文档只公开 Provider API，文档里查不到用量端点——不看 CLI 实现/社区代码就无从发现 `/alpha/*`
- 如果误以为「没有 API」会走网页抓取（像 OpenCode GO），实现复杂 10 倍且易碎；实际 4 个 GET 就搞定
- `monthlyCredits` 是剩余值，拿它当已用会算出「已用 $0」的假象

## When to Apply

- 新增/维护 Command Code 用量卡片时
- 任何需要 Command Code 订阅剩余额度的场景
- 遇到 alpha 端点字段变化（`success` 包裹、字段重命名）时先 curl 看 body 再改解码

## Examples

Swift 解码（月度剩余 → 已用百分比）：
```swift
let usedPercent = (cap - monthlyCredits) / cap * 100   // cap=70
let resetDate = Date(timeIntervalSince1970: TimeInterval(resetAtMs) / 1000)
```

## What Didn't Work / 弯路

- 先查官方 Provider API 文档 → 没有用量端点（白找）
- 匿名 curl usage 页 → 302 跳转 /signin，必须登录态（网页抓取路径确认可行但没必要）
- 找本机 CLI auth.json / env → 没装 CLI、key 不在 .env（最终用户直接提供 key 实测）

## Prevention

- 新增外部服务监控前：先查 CLI 源码 / 社区实现找内部端点，再决定「API 直连」还是「网页抓取」
- alpha 端点可能变，解码做防御（optional 字段全可空，缺啥不崩）
- 卡片数据源保持独立降级：credits 挂了不影响 plan 显示

## Related

- [openrouter-usage-integration.md](./openrouter-usage-integration.md) — 同 repo 的 OpenRouter 用量集成（官方公开端点模式）
- [keychain-acl-resign.md](./keychain-acl-resign.md) — key 存储坑
