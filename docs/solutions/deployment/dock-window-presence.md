---
title: 菜单栏 app 窗口开→Dock 图标出现、全关→消失（activationPolicy 动态切换）
date: 2026-08-15
category: deployment
module: AppDelegate / 窗口控制器
problem_type: architecture_pattern
severity: medium
applies_when:
  - 菜单栏 app（.accessory）打开主窗口时需要在 Dock 显示图标，方便来回切换
  - 全部窗口关闭后图标要消失，但 app 本体不退出
tags: [activation-policy, dock, menu-bar-app, nswindow, swift]
---

# 菜单栏 app 窗口开→Dock 图标出现、全关→消失

## Context

AIUsageMonitor 是纯菜单栏 app（`activationPolicy = .accessory`，无 Dock 图标）。用户希望打开「看板」（Hindsight Control Plane :9999）或「小说」（Flask Web :8080）窗口时，Dock 出现图标方便切换（Cmd+Tab / 点 Dock / 窗口菜单）；全部窗口关闭后图标消失；但菜单栏监控必须常驻、**绝不因关窗口退出**。

## Guidance

macOS 的 `NSApplication.ActivationPolicy` 可以在运行时动态切换：

- `.accessory` — 无 Dock 图标、无菜单栏（菜单栏 app 常态）
- `.regular` — 有 Dock 图标、有菜单栏（普通 app）

模式：**任一窗口可见 → `.regular`；全部关闭 → `.accessory`**。AppDelegate 统一管理：

```swift
func updateDockPresence() {
    let dashboardVisible = DashboardWindowController.shared.window?.isVisible ?? false
    let novelVisible = NovelWebWindowController.shared.window?.isVisible ?? false
    let target: NSApplication.ActivationPolicy = (dashboardVisible || novelVisible) ? .regular : .accessory
    if NSApp.activationPolicy() != target {
        NSApp.setActivationPolicy(target)
    }
}
```

触发时机两条路：

1. **打开窗口**：窗口控制器 `show()`/`createWindow()` 里 post 自定义通知（如 `.windowVisibilityChanged`），AppDelegate 收到后刷新
2. **关闭窗口**：AppDelegate 直接观察系统通知 `NSWindow.willCloseNotification`（窗口真正关闭后发送，此时 `isVisible` 已为 false），不用在 `windowWillClose` 里判断（此时 isVisible 还是 true）

防退出（关键）：

```swift
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
```

`.regular` 状态下菜单栏必然出现，设置最小 `mainMenu`（App 菜单 + 窗口菜单），`NSApp.windowsMenu = windowMenu` 会让 AppKit 自动把所有打开的窗口列进窗口菜单——天然支持看板/小说间一键切换。

## Pitfalls

- **`NSWindow.didCloseNotification` 不存在** — 编译报 `type 'NSWindow' has no member 'didCloseNotification'`。正确通知名是 `NSWindow.willCloseNotification`。
- **不要实现 `windowDidClose(_:)` delegate 方法** — 会触发编译器警告 "instance method 'windowDidClose' nearly matches optional requirement 'windowDidExpose' of protocol 'NSWindowDelegate'"，且该 delegate 方法本就不存在；改用系统通知观察，零警告。
- **Swift 字符串插值转义坑** — 源码应为 `print("... \(cond ? "a" : "b")")`；经 patch/JSON 传递时多转义一层会变成 `\\"` 和 `\\(`，编译报 "unterminated string literal"。写完立即 `swift build` 验证，不要等 deploy 脚本。

## Why This Matters

纯菜单栏 app 的主窗口默认不进 Dock / Cmd+Tab，两个 Web 窗口之间来回切换很别扭。动态 policy 切换用几行代码让窗口打开期间拥有完整"普通 app 体验"（Dock 图标 + Cmd+Tab + 窗口菜单），关闭后回归隐身，且监控进程永不退出——精确匹配"图标随窗口生灭、app 常驻"的需求。

## When to Apply

- 任何 `.accessory` 菜单栏 app 需要临时展示主窗口的场景
- 用户要求"窗口开着有 Dock 图标、关了图标消失、app 不退出"时

## Examples

AIUsageMonitor v1.6.0（2026-08-15）：
1. 点菜单栏「看板」→ 窗口打开 → Dock 出现 AIUsageMonitor 图标
2. 再点「小说」→ 两窗口并存，一个 Dock 图标，Cmd+` / 窗口菜单切换
3. 关闭其中一个 → 图标保留（还有窗口）
4. 全部关闭 → 图标消失，菜单栏图标照常
5. 重启看板 → 图标再次出现

## Related

- [flask-web-in-swift-app.md](flask-web-in-swift-app.md) — Web 窗口（WKWebView + 本地服务）集成模式
- [app-bundle-deploy.md](app-bundle-deploy.md) — 改完代码必须 deploy.sh 部署，禁止只提交 git
