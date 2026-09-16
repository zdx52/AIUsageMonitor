# AIUsageMonitor UI 布局修复 + Tavily JSON 可选字段

## 症状

1. **Command Code 月度额度重置倒计时被挡住**：月度额度进度条下方的「重置于 X天X小时」倒计时文字被月度额度警告 label（使用过半/即将耗尽）遮挡
2. **Tavily 一直显示「请配置 API Key」**：设置里已填好 key，但每次刷新都提示配置 key（实际上 key 有效，API 返回了数据）

## 根因

### 问题1：布局顺序错误

原布局顺序（自上而下）：
```
5小时窗口
每周窗口
本期汇总（花费/请求数/Tokens）
月度额度使用警告（⚠️ label）  ← 插入在汇总和月度额度之间
月度额度 + 重置倒计时         ← 警告 label 把它"挤出"视图
```

### 问题2：JSON 可选字段缺失 + 状态分支不区分

1. Tavily 免费版（Researcher）API 返回 `plan_limit: null`，但 `TavilyUsageResponse.AccountUsage.planLimit` 是 `Int`（非可选），JSON 解码直接抛错，Swift 吞掉错误返回 `nil`
2. `UsageData` 中无区分「key 未配置」vs「key 配置了但获取失败」的状态标记，导致两种情况在 UI 上显示完全相同：「请在设置中配置 Tavily API Key」

## 修复

### 问题1修复（MenuBarView.swift）

- 移除月度额度警告 label（`>= 90%` 和 `>= 70%` 的两个 `Label`）
- 月度额度进度条 + 重置倒计时移至每周窗口下方
- 新顺序：5小时 → 每周 → 月度额度 → 本期汇总

### 问题2修复

**TavilyData.swift** — `planLimit` 改为可选：
```swift
struct AccountUsage: Codable {
    let planLimit: Int?   // 免费版 plan_limit 为 null
}
struct KeyUsage: Codable {
    let limit: Int?       // 免费版 limit 为 null
}
```

**TavilyService.swift** — 使用时解包：
```swift
let monthlyLimit = usageResponse.account.planLimit ?? 0
```

**UsageData.swift** — 新增 `tavilyKeyConfigured` 标记：
```swift
@Published var tavilyKeyConfigured = false

// refreshAll() 中调用 fetchTavilyUsage() 前先检查：
let hasTavilyKey = !(KeychainHelper.get(key: "tavily_api_key") ?? "").isEmpty
self.tavilyKeyConfigured = hasTavilyKey
```

**MenuBarView.swift** — UI 分支增加「key 配置了但获取失败」状态：
```swift
} else if dataStore.tavilyKeyConfigured {
    Label("获取失败，请检查网络或 Key", systemImage: "exclamationmark.triangle")
        .font(.caption)
        .foregroundStyle(.orange)
    Text("将在下次自动重试")
        .font(.caption2)
        .foregroundStyle(.tertiary)
} else {
    Text("暂无数据")
    Text("请在设置中配置 Tavily API Key")
}
```

## 预防

1. **JSON 模型防御**：第三方 API 的数字字段一律用可选类型（`Int?`）声明，避免 null 抛错
2. **状态区分原则**：从 Keychain/配置读取 key 后，应有独立的状态变量标记「key 是否存在」，UI 根据此变量区分「未配置」和「获取失败」
3. **UI 布局验证**：在修改卡片的 item 顺序时，用真实数据实测确认无遮挡，不要依赖代码审阅
