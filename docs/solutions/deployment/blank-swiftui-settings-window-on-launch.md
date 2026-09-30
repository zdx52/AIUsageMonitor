---
title: SwiftUI Settings 场景导致启动时弹出空白"设置"窗口
date: 2026-10-01
category: deployment
module: app 入口 / 窗口
problem_type: ui_bug
severity: medium
symptoms:
  - 每次启动 app（LSUIElement 菜单栏 app）都会自动冒出一个标题为「AIUsageMonitor 设置」的空白窗口
  - 全仓搜不到任何创建该标题窗口的代码，窗口内容永远空白
  - 关掉后下次启动还会再来
root_cause: logic_error
resolution_type: code_fix
tags: [swiftui, appkit, settings-scene, macos, window, entry-point]
---

# SwiftUI Settings 场景导致启动时弹出空白"设置"窗口

## Problem

AIUsageMonitor 是菜单栏 app（`LSUIElement = true`），真正的设置界面是 `SettingsWindowController` 里的 NSPanel（菜单栏弹窗「设置」按钮打开）。但每次启动都会额外弹出一个标题为「AIUsageMonitor 设置」的空白窗口，用户以为设置面板坏了。

## Symptoms

- 启动后最多几十秒内出现空白窗口，标题「AIUsageMonitor 设置」，尺寸 900×450（与 SwiftUI 默认设置窗口一致）
- 代码里只有 `panel.title = "设置"`，没有任何地方用过这个标题 → 说明窗口不是本项目代码创建的

## What Didn't Work

- 先怀疑 `SettingsWindowController` 的 NSPanel 渲染失败（`fittingSize` 为 0 → 高度兜底 640），但那个 panel 宽 480、标题是「设置」，与截图对不上，排除
- 怀疑窗口状态恢复：`~/Library/Saved Application State/com.aiusagemonitor.savedState` 不存在，排除

## Solution

根因在 `AIUsageMonitorApp.swift`：app 唯一的 SwiftUI 场景是个空占位 `Settings { EmptyView() }`，而 macOS 在启动时会自动呈现 app 的唯一场景 → 空的 Settings 窗口。

改成纯 AppKit 入口，彻底去掉 SwiftUI App 生命周期：

```swift
// 删掉整个 AIUsageMonitorApp.swift 里的 @main struct AIUsageMonitorApp { ... Settings { EmptyView() } }
// 新增 AIUsageMonitor/main.swift
import AppKit

// NSApplication.delegate 是 weak，必须用全局变量持有 delegate
private var appDelegate: AppDelegate?

MainActor.assumeIsolated {
    let app = NSApplication.shared
    appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.run()
}
```

`Package.swift` 是按目录收源文件（`path: "AIUsageMonitor"`），新增 `main.swift` 不需要改工程文件；注意本仓 `AIUsageMonitor.xcodeproj` 已过期（缺 `CommandCodeService.swift`），构建实际走 `swift build`。

## Why This Works

SwiftUI 的 `App` 至少需要一个 `Scene`，本 app 又完全不用 SwiftUI 的场景体系（菜单栏是手搓的 `NSStatusItem`，设置窗口是手搓的 `NSPanel`），于是那个 `Settings` 场景成了唯一场景。macOS 启动 agent app 时会去呈现它，内容只有 `EmptyView()` → 空白窗口。去掉 SwiftUI App 生命周期后不再有场景，也就没有任何窗口可被自动呈现。

## Prevention

- 纯 AppKit/菜单栏 app 不要为了"留个 App body"塞 `Settings { EmptyView() }` 这类占位场景，直接走 AppKit 入口
- 排查"莫名的窗口"先做两步：① 全仓搜窗口标题字符串（找不到 = 不是本项目代码建的）② `defaults read <bundle-id>` 看有没有 `NSWindow Frame ...` 键——SwiftUI 呈现窗口时会写回窗口尺寸（本项目实测键名：`NSWindow Frame com_apple_SwiftUI_Settings_window`，写入时间 = 启动时刻，可直接坐实"启动即弹"）
- 验证修复：`defaults delete <bundle-id> "NSWindow Frame com_apple_SwiftUI_Settings_window"` → 重新部署启动 → 该键不再出现 = 窗口没被呈现
