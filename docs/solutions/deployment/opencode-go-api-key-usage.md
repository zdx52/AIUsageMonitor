---
title: OpenCode GO 用量直查（Go API key /zen/go/v1/usage）
date: 2026-09-30
category: deployment
module: AIUsageMonitor 菜单栏卡片
problem_type: architecture_pattern
severity: medium
applies_when:
  - 在 AIUsageMonitor 或任意应用里用 Go API key 查 OpenCode GO 订阅用量
  - OpenCode cookie/RPC/WebView 抓取链路不稳定，想换官方直连
tags: [opencode, go, usage, api-key, swift, usage-monitor]
---

# OpenCode GO 用量直查（Go API key）

## Context

AIUsageMonitor 的 OpenCode 卡原先走 cookie + `_server?id=<hash>` RPC + WebView 回退三级抓取（`OpenCodeService`），重且脆。用户问能否用 Go API key 直接查余额。

## Guidance

**关键发现：`GET https://opencode.ai/zen/go/v1/usage` 拿 Go key（Bearer）能直接返回三维度用量**（官方 docs 未公开，是逐个 fuzz 候选端点实测出来的，不要只信文档）：

| 端点 | 鉴权 | 结果 |
|---|---|---|
| `GET /zen/go/v1/usage` | `Bearer <Go key>` | 200，rolling/weekly/monthly |
| 同上无 key | — | 401 `AuthError: Missing API key` |
| `GET /zen/v1/usage\|billing\|credits`、`/zen/go/v1/billing`、`api/billing` | 同上 | 全 404（不存在） |

实测 payload（2026-09-30）：

```json
{"usage":{
  "rolling":{"status":"ok","percent":0,"resetsAt":"2026-09-30T19:16:15.131Z"},
  "weekly":{"status":"ok","percent":0,"resetsAt":"2026-10-05T00:00:00.000Z"},
  "monthly":{"status":"ok","percent":0,"resetsAt":"2026-10-30T14:12:15.000Z"}}}
```

### 关键点

- `resetsAt` 是 ISO8601（带毫秒），解析需 `ISO8601DateFormatter` + `.withFractionalSeconds`（Command Code 同款坑）。
- Zen 按量余额**无**对应端点（GitHub `anomalyco/opencode#10448` 仍 open）；`#18648` 评论原话确认 Go plan 之前只能看网页 dashboard。
- 集成策略：有 key 走直查（`URLSessionConfiguration.ephemeral` + `connectionProxyDictionary = [:]` 直连），无 key/失败回退原 cookie/RPC 链路。key 存 Keychain（`opencode_go_api_key`），与其它供应商同 pattern（见 `KeychainHelper`）。
- 卡片映射：`percent` → rolling/weekly/monthlyPercent；`resetsAt` → `*ResetAt: Date`，卡片渲染时经 `countdownText(from:)` 输出「X天X小时X分钟」（向上取整，避免 0分钟），比预烘字符串实时；rolling 的 `resetsAt-now` 秒数 → `rpcResetInSec`（倒计时复用）。
- 反例教训：本轮曾因"文档无记载 + issue 喊没接口"误判为不支持；**未公开 ≠ 不存在，候选端点逐个 curl 实测才算数**。

## AIUsageMonitor 接线位置

- `Models/OpenCodeData.swift`：`OpenCodeGoUsageResponse` + `toOpenCodeUsage()`
- `Services/OpenCodeService.swift`：`fetchUsageViaAPIKey()`，`fetchUsage` 入口优先调用
- `Models/UsageData.swift`：无 URL 时仅 key 可查；状态分支有 key 不算 `.notConfigured`
- `Views/SettingsView.swift`：Go key SecureField + eye toggle + load/save
- `Tests/.../ModelDecodingTests.swift`：`testDecodeOpenCodeGoUsage` / `testOpenCodeGoUsageEmpty`
