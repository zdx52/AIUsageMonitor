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
</p>

AIUsageMonitor 是一个 macOS 菜单栏轻量级应用，实时监控 DeepSeek、Tavily 和 OpenCode GO 的 API 用量与余额。通过菜单栏常驻，随时掌握 AI 账户状态，支持自动刷新和手动刷新。

## 快速使用

从 [GitHub Releases](https://github.com/zdx52/AIUsageMonitor/releases) 下载最新版：

- `AIUsageMonitor.dmg` — macOS 通用安装包

安装后：

1. 双击挂载 DMG，将 `AIUsageMonitor.app` 拖入 Applications 文件夹
2. 双击 `AIUsageMonitor.app` 启动
3. 菜单栏出现图标，点击即可查看用量
4. 在设置面板中配置 DeepSeek 和 Tavily 的 API Key

> ⚠️ **macOS 26+ 用户**：由于系统 Gatekeeper 限制，首次启动请使用**右键 → 打开**方式，或先去系统设置 > 隐私与安全性中允许运行。


## 功能特性

- 🐋 **DeepSeek 余额监控** — 实时查询账户总余额、赠送余额、充值余额
- 🔍 **Tavily 用量监控** — 查看月度额度、已用和剩余额度
- 🔄 **OpenCode GO 用量监控** — 滚动/每周/每月三维度用量查询，登录态检测与管理

- 🔒 **Keychain 安全存储** — API Key 存储在 macOS 钥匙串，不明文保存
- ⏱️ **自定义自动刷新** — 可自定义刷新间隔（1-30分钟），设置即生效
- 👁️ **显示开关** — 可在设置中分别控制 DeepSeek/Tavily/OpenCode 的显示与隐藏
- 🎛️ **菜单栏常驻** — 轻量运行，不占用桌面空间
- ⚙️ **设置面板** — 可视化配置 API Key、OpenCode 工作区和刷新间隔

## 数据说明

### DeepSeek

- 余额通过 `https://api.deepseek.com/user/balance` 获取
- 今日消耗通过 WebView 爬虫从 `https://platform.deepseek.com/usage` 页面解析

### Tavily

- 用量通过 `https://api.tavily.com/usage` 获取
- 显示计划类型、月度额度、已用 credits 和剩余 credits

### OpenCode GO

- 用量通过 RPC 调用 + WKWebView 页面抓取获取
- 显示滚动、每周、每月三维度用量百分比及重置时间
- 支持登录态检测与内置浏览器重新登录


## 常见问题

### 首次打开提示"无法验证开发者"

本版本使用 ad-hoc 签名，macOS Gatekeeper 会拦截。在终端执行：

```bash
sudo xattr -rd com.apple.quarantine /Applications/AIUsageMonitor.app
```

执行后重新打开即可。

### 数据不显示

1. 打开设置面板，确认 DeepSeek 和 Tavily 的 API Key 已正确配置
2. 点击右上角"刷新"按钮手动刷新
3. 检查 Keychain 中是否成功保存了 API Key

### 如何修改自动刷新间隔？

在设置面板中拖动滑块调整，范围 1-30 分钟。

## 技术栈

- **SwiftUI** — 现代化 UI 框架
- **AppKit** — 菜单栏应用支持
- **Security Framework** — Keychain 密钥存储
- **URLSession** — HTTP API 请求
- **WebKit** — DeepSeek 今日消耗页面解析

## 开发

```bash
cd AIUsageMonitor
xcodebuild -project AIUsageMonitor.xcodeproj -scheme AIUsageMonitor -configuration Release build
```

## 许可证

MIT License

## 更新日志

### v1.3.1 (2026-06-27)

🐛 **Bug 修复**
- 修复 macOS 26 下 .app bundle 被 Gatekeeper 拦截无法启动的问题（改用 AppleScript 启动器）
- 修复 Keychain 访问导致 App 崩溃的问题（添加 Entitlements + 使用 Bundle ID 作为 Service Name）
- 修复设置窗口关闭后复用导致按钮状态卡死的问题（SettingsPanel 释放 window 引用）
- 修复 WKWebView 导航失败导致中断 OAuth 登录流程的问题（不再自动终止登录）
- 修复 DeepSeek 菜单栏标题 Unicode 编码显示异常

🎨 **改进**
- 全新 App 图标
- OpenCode 登录改为在 App 内 WKWebView 完成（支持 GitHub/Google OAuth）
- 登录检测增加轮询 + Cookie 检测 + URL 检测三种方式
- ASWebAuthenticationSession 登录支持（与 Safari 共享 cookie）
- 移除 LSUIElement + setActivationPolicy 冲突导致的菜单栏不显示问题

### v1.3.0 (2026-06-25)

🏗️ **重构**
- 拆分 OpenCodeService（862 行）为三个职责清晰的模块：OpenCodeService（99 行，编排）、OpenCodeRPC（137 行，RPC 客户端）、OpenCodeWebViewScraper（573 行，WebView 抓取）
- 删除冗余的 OpenCodeScriptMessageHandler，WebViewScraper 直接实现 WKScriptMessageHandler

⚡ **优化**
- DataStore 和 AppDelegate 改用 @MainActor，消除手动 MainActor.run 包裹
- KeychainHelper 增加 OSStatus 错误检查和安全解包，不再静默失败
- 移除冗余的 UserDefaults.synchronize() 调用

✅ **测试**
- 新增单元测试框架，10 个测试覆盖 DeepSeek/Tavily/OpenCode 的 Codable 解码和模型初始化

### v1.2.1 (2026-06-24)

🐛 **Bug 修复**
- 修复 WKWebView JS 消息处理器未释放导致的内存泄漏（WebScraper、OpenCodeService）
- 修复登录导航代理闭包强持有 self 的问题

🔧 **优化**
- 增强 DeepSeek 今日消耗页面解析容错性（7 种正则模式兜底，不再依赖单一文案）
- 设置面板高度改为自适应（400-800px 动态调整）
