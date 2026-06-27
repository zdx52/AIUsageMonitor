# AIUsageMonitor 动态菜单栏图标

## 概述
根据各 AI 服务的健康度，动态变化菜单栏图标颜色，用户扫一眼就能知道整体状态。

## 改动范围
- `AIUsageMonitorApp.swift` — AppDelegate 图标更新逻辑
- `DataStore`（`UsageData.swift`）— 新增健康度计算属性
- 不动 `MenuBarView.swift`、`SettingsView.swift` 和其他 Service 文件

## 设计

### 1. ServiceHealth 枚举（DataStore 新增）

```swift
enum ServiceHealth: Comparable {
    case healthy  // 全部正常
    case warning  // 有预警
    case critical // 有严重问题
}
```

### 2. 健康度评分逻辑

在 DataStore 中添加计算属性 `healthLevel`，按以下规则判定：

**Critical（🔴 红）— 任意一项触发即整体红：**
- DeepSeek 余额 < ¥5
- OpenCode 状态为 `fetchFailed`

**Warning（🟠 橙）— 任意一项触发即整体橙：**
- DeepSeek 余额 < ¥20（但 ≥ ¥5）
- Tavily 剩余额度 < 月限额的 25%
- OpenCode 用量 > 80%
- OpenCode 状态为 `noCookies` / `needsLogin`
- 刷新失败且之前没有数据

**Healthy（🔵 蓝，系统强调色）— 默认态：**
- 全部正常
- 启动中、数据未到
- 未配置的服务不影响评分
- 刷新失败但之前有有效数据（保持上次颜色）

### 3. 颜色更新机制（AppDelegate）

- 移除 `statusBarIcon` 的 `lazy` 计算属性，改为 `var`
- 新增 `updateStatusBarIcon(color: NSColor)` 方法
  - 用 `NSImage(systemSymbolName: "chart.bar.fill")` 创建图标
  - 用 `.withSymbolConfiguration(.init(paletteColors: [color]))` 着色
- 在 `DataStore.refreshAll()` 完成后，自动触发图标更新
- 使用 Combine 的 `.sink` 监听 `dataStore.$healthLevel` 变化，自动驱动图标更新

### 4. 边界情况

| 场景 | 颜色 | 说明 |
|------|------|------|
| 启动中、全部正常 | 🔵 蓝 | 默认健康态 |
| 初始数据未到 | 🔵 蓝 | 不给用户假警报 |
| DeepSeek 余额 < ¥20 | 🟠 橙 | 偏低但未到红线 |
| DeepSeek 余额 < ¥5 | 🔴 红 | 严重不足 |
| Tavily 余量 < 25% | 🟠 橙 | 额度将尽 |
| OpenCode cookie 过期 | 🟠 橙 | 需要重新登录 |
| OpenCode 获取失败 | 🔴 红 | 服务可能不可用 |
| 刷新失败（有数据） | 保持上次颜色 | 避免网络波动误报 |
| 刷新失败（无数据） | 🟠 橙 | 无法获取任何数据 |

## 不变的部分
- 弹窗内容（MenuBarView）不作任何修改
- 菜单栏标题文字（`menuBarTitle`）不作修改
- 所有 Service 层代码不作修改
- 设置面板（SettingsView）不作修改

## 设计时间
2026-06-27
