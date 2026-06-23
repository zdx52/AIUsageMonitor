# AIUsageMonitor 菜单栏视觉升级

## 概述
对 MenuBarView 进行视觉美化，提升 macOS 原生感和信息可读性。

## 改动范围
仅修改 `MenuBarView.swift`，不动数据层和逻辑层。

## 改动内容

### 1. SF Symbols 替换 emoji
- DeepSeek: `waveform.path.ecg` (紫色)
- Tavily: `magnifyingglass` (青色)
- OpenCode GO: `arrow.triangle.2.circlepath` (橙色)
- 标题: `cpu` (灰色)
- 状态图标: `exclamationmark.triangle`(橙) / `xmark.circle.fill`(红) / `checkmark.circle.fill`(绿)

### 2. ProgressBar 进度条组件
- 高度 6pt，圆角 3pt
- 填充色随百分比变化：0-50% 绿 → 50-80% 橙 → 80%+ 红
- 适用于 OpenCode 三种用量和 Tavily 已用/总额度

### 3. DeepSeek 余额预警
- 余额 > ¥20: 紫色背景 (品牌色)
- ¥5 ~ ¥20: 橙色背景 + "余额偏低"
- < ¥5: 红色背景 + "余额不足"

### 4. 排版间距优化
- UsageCard padding: 8pt → 12pt
- UsageRow label: `.secondary` → `.tertiary`
- UsageRow value: 保持 `.medium`，更突出

## 设计时间
2026-06-23
