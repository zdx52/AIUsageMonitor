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
  <img alt="Version" src="https://img.shields.io/badge/version-1.4.2-blue">
</p>

AIUsageMonitor 是一个 macOS 菜单栏轻量级应用，实时监控 DeepSeek、Tavily、OpenCode GO 和 Hindsight 的 API 用量与记忆状态。通过菜单栏常驻，随时掌握 AI 账户状态，支持自动刷新和手动刷新。

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
- 🔄 **OpenCode GO 用量监控** — RPC 查询用量百分比，支持 WKWebView 内嵌登录与浏览器备选，独立重置倒计时
- 🧠 **Hindsight 记忆看板** — 实时显示记忆总数、经验、观察和世界知识统计，支持 WKWebView 内嵌看板
- 🌐 **菜单栏网速显示** — 实时显示 `↓下载 ↑上传`，3 秒刷新，紧凑显示
- 🟢 **动态健康提示** — 文字颜色标示：健康默认色 / 预警橙色 / 严重红色
- 🔒 **Keychain 安全存储** — API Key 存储在 macOS 钥匙串，不明文保存
- ⏱️ **自定义自动刷新** — 可自定义刷新间隔（1-30 分钟），设置即生效
- 👁️ **显示开关** — 可在设置中分别控制 DeepSeek/Tavily/OpenCode/Hindsight 的显示与隐藏
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
- 支持 WKWebView 内嵌登录（GitHub / Google OAuth）
- 支持系统浏览器登录备选方案
- 登录失败时提供手动确认按钮

## 常见问题

### 首次打开提示"无法验证开发者"

本版本使用 ad-hoc 签名，macOS Gatekeeper 会拦截。在终端执行：

```bash
xattr -dr com.apple.quarantine /Applications/AIUsageMonitor.app
```

### 如何添加 API Key？

点击菜单栏图标 → 设置 → 在对应输入框中粘贴 API Key → 点击保存。

## 构建

需要 macOS 14+、Xcode 15+。

```bash
git clone git@github.com:zdx52/AIUsageMonitor.git
cd AIUsageMonitor
swift build -c release
cp -r .build/release/AIUsageMonitor AIUsageMonitor.app/Contents/MacOS/
```

## 更新内容

### v1.4.2

- 🧠 **Hindsight 版本显示** — 看板标题栏 + 右侧面板同时显示当前版本号
- 🔄 **自动更新检查** — 左侧看板每 2 小时自动查 PyPI，右侧面板每次刷新时带缓存检查
- ⬆ **新版本提醒** — 有新版本时橙色标签/文字提示升级
- 📐 **看板自适应布局** — 网格列数随窗口宽度自动适配（窄→1列 / 中→2列 / 宽→3列）
- 🧩 **心智模型始终显示** — 即使 0 条也灰显入口
- 🐛 **API 字段适配** — 修正 fact_type / date 字段映射，数据正确显示
- 🏷️ **版本号统一** — Info.plist / README / GitHub 统一为 v1.4.2

### v1.4.0

- 🧠 **Hindsight 集成** — 菜单栏弹窗显示记忆总数/经验/观察/世界知识，5 分钟自动刷新
- 📊 **看板面板** — WKWebView 内嵌 Hindsight 看板，支持搜索、分类和详情查看
- 🔄 **OpenCode 重置倒计时** — 每项用量独立显示剩余重置时间（滚动/每周/每月）
- ⏱️ **下次刷新倒计时** — 弹窗底部实时显示距离下次自动刷新的剩余时间
- 🔘 **Hindsight 显示开关** — 设置面板新增 Hindsight 记忆显示开关
- ♻️ **Hindsight 刷新跟随设置** — 刷新间隔遵循用户自定义配置
- 🔧 **弹窗交互优化** — 点击弹窗外部自动关闭
- 🎨 **看板时间本地化** — 记忆时间显示为本地时区（zh-CN）
