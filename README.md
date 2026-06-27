# AIUsageMonitor

<p align="center">
  <img src="docs/images/app-icon.png" alt="AIUsageMonitor 图标" width="120">
</p>

<p align="center">
  macOS 菜单栏 AI 用量监控工具
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/github/v/release/zdx52/AIUsageMonitor">
  <img alt="License" src="https://img.shields.io/github/license/zdx52/AIUsageMonitor">
  <img alt="Swift" src="https://img.shields.io/badge/swift-5.0-orange">
  <img alt="macOS" src="https://img.shields.io/badge/platform-macOS-lightgray">
  <img alt="Version" src="https://img.shields.io/badge/version-1.3.2-blue">
</p>

AIUsageMonitor 是一个 macOS 菜单栏轻量级应用，实时监控 DeepSeek、Tavily 和 OpenCode GO 的 API 用量与余额。通过菜单栏常驻，随时掌握 AI 账户状态，支持自动刷新和手动刷新。

## 快速使用

从 [GitHub Releases](https://github.com/zdx52/AIUsageMonitor/releases) 下载最新版：

- `AIUsageMonitor.dmg` — macOS 通用安装包

安装后：

1. 双击挂载 DMG，将 `AIUsageMonitor.app` 拖入 Applications 文件夹
2. 双击 `AIUsageMonitor.app` 启动
3. 菜单栏出现图标，点击即可查看用量
4. 在设置面板中配置 DeepSeek、Tavily 和 OpenCode 的 API Key / 工作区 URL

> ⚠️ **macOS 26+ 用户**：由于系统 Gatekeeper 限制，首次启动请使用**右键 → 打开**方式，或先去系统设置 > 隐私与安全性中允许运行。

## 功能特性

- 🐋 **DeepSeek 余额监控** — 实时查询账户总余额、赠送余额、充值余额
- 🔍 **Tavily 用量监控** — 查看月度额度、已用和剩余额度
- 🔄 **OpenCode GO 用量监控** — RPC 查询用量百分比，支持 WKWebView 内嵌登录与浏览器备选
- 🟢 **动态菜单栏图标** — 根据服务健康度自动变色：🟢 全部正常 / 🟠 有预警 / 🔴 有严重问题
- 🔒 **Keychain 安全存储** — API Key 存储在 macOS 钥匙串，不明文保存
- ⏱️ **自定义自动刷新** — 可自定义刷新间隔（1-30 分钟），设置即生效
- 👁️ **显示开关** — 可在设置中分别控制 DeepSeek/Tavily/OpenCode 的显示与隐藏
- 🎛️ **菜单栏常驻** — 轻量运行，不占用桌面空间
- ⚙️ **设置面板** — 可视化配置 API Key、OpenCode 工作区和刷新间隔
- 🌐 **双模式登录** — WKWebView 内嵌登录 + 系统浏览器备选，支持手动检测登录完成

## 数据说明

### DeepSeek

- 余额通过 `https://api.deepseek.com/user/balance` 获取
- 今日消耗通过 WebView 爬虫从 `https://platform.deepseek.com/usage` 页面解析

### Tavily

- 用量通过 `https://api.tavily.com/usage` 获取
- 显示计划类型、月度额度、已用 credits 和剩余 credits

### OpenCode GO

- 用量通过 RPC 调用 + WKWebView 页面抓取获取
- 支持 WKWebView 内嵌登录（GitHub / Google OAuth）
- 支持系统浏览器登录备选方案
- 登录失败时提供手动确认按钮

### 菜单栏图标颜色

| 状态 | 图标 | 说明 |
|------|:----:|------|
| 全部服务正常 | 模板图标 | 系统自动适配浅色/深色菜单栏，始终清晰 |
| 有预警 | 🟠 橙色 | 余额偏低 / 用量将尽 / 登录过期 |
| 严重问题 | 🔴 红色 | 余额不足 / 数据获取失败 |

## 常见问题

### 首次打开提示"无法验证开发者"

本版本使用 ad-hoc 签名，macOS Gatekeeper 会拦截。在终端执行：

```bash
sudo xattr -rd com.apple.quarantine /Applications/AIUsageMonitor.app
```

执行后重新打开即可。

### 数据不显示

1. 打开设置面板，确认 DeepSeek 和 Tavily 的 API Key 已正确配置
2. 确认 OpenCode 工作区 URL 正确（格式：`https://opencode.ai/workspace/wrk_xxx/go`）
3. 点击菜单栏右上角「刷新」按钮手动刷新
4. 检查 Keychain 中是否成功保存了 API Key

### OpenCode 登录失败

1. 点击「在 App 内登录」使用 WKWebView 内嵌登录
2. 如果内嵌窗口空白，可关闭后使用系统浏览器登录
3. 登录完成后，点击「✅ 我已登录完成（手动检测）」按钮确认

### 如何修改自动刷新间隔？

在设置面板中拖动滑块调整，范围 1-30 分钟。

## 技术栈

- **SwiftUI** — 现代化 UI 框架
- **AppKit** — 菜单栏应用支持
- **Security Framework** — Keychain 密钥存储
- **URLSession** — HTTP API 请求
- **WebKit** — DeepSeek 页面解析 + OpenCode 内嵌登录
- **Combine** — 菜单栏图标颜色动态更新

## 开发

```bash
git clone git@github.com:zdx52/AIUsageMonitor.git
cd AIUsageMonitor
swift build -c release
open .build/release/AIUsageMonitor
```

或使用 Xcode 打开 `AIUsageMonitor.xcodeproj` 构建运行。

## 许可证

MIT License
