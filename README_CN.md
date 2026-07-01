# AIUsageMonitor

<p align="center">
  <img src="docs/images/app-icon.png" alt="AIUsageMonitor 图标" width="120">
</p>

<p align="center">
  macOS 菜单栏系统监控工具
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/github/v/release/zdx52/AIUsageMonitor">
  <img alt="License" src="https://img.shields.io/github/license/zdx52/AIUsageMonitor">
  <img alt="Swift" src="https://img.shields.io/badge/swift-5.0-orange">
  <img alt="macOS" src="https://img.shields.io/badge/platform-macOS-lightgray">
  <img alt="Version" src="https://img.shields.io/badge/version-1.4.5-blue">
</p>

AIUsageMonitor 是一个 macOS 菜单栏轻量级系统监控工具，实时显示笔记本温度、CPU 使用率、AI 用量（DeepSeek / Tavily / OpenCode GO）和 Hindsight 记忆状态。支持自动刷新和手动刷新。

## 快速使用

从 [GitHub Releases](https://github.com/zdx52/AIUsageMonitor/releases) 下载最新版：

- `AIUsageMonitor.dmg` — macOS 通用安装包

安装后：

1. 双击挂载 DMG，将 `AIUsageMonitor.app` 拖入 Applications 文件夹
2. 双击 `AIUsageMonitor.app` 启动
3. 菜单栏出现图标，点击即可查看用量
4. 在设置面板中配置 API Key / 工作区 URL

> ⚠️ **macOS 26+ 用户**：由于系统 Gatekeeper 限制，首次启动请使用**右键 → 打开**方式，或先去系统设置 > 隐私与安全性中允许运行。

## 功能特性

- 🌡️ **温度监控** — 实时显示电池温度、CPU 使用率、系统热状态
- 🐋 **DeepSeek 余额监控** — 实时查询账户总余额、赠送余额、充值余额
- 🔍 **Tavily 用量监控** — 查看月度额度、已用和剩余额度
- 🔄 **OpenCode GO 用量监控** — RPC 查询用量百分比，支持 WKWebView 内嵌登录与浏览器备选
- 🧠 **Hindsight 记忆看板** — 实时显示记忆总数、经验、观察和世界知识统计
- 🌐 **菜单栏网速显示** — 实时显示 `↓下载 ↑上传`，3 秒刷新
- 🟢 **动态健康提示** — 文字颜色标示：健康默认色/预警橙色/严重红色
- 🔒 **Keychain 安全存储** — API Key 存储在 macOS 钥匙串
- ⏱️ **自定义自动刷新** — 可自定义刷新间隔（1-30 分钟）
- 👁️ **显示开关** — 可在设置中分别控制各模块的显示与隐藏
- ⚙️ **设置面板** — 可视化配置 API Key、工作区和刷新间隔

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

### v1.4.5

- 🌡️ **温度监控** — 新增笔记本温度显示卡片，实时显示电池温度、CPU 使用率、系统热状态。菜单栏新增竖直温度计图标（按温度变色）和实时数据
- 📊 **双栏布局** — 弹窗改为左右两栏：左栏系统信息（温度+Hindsight）、右栏 AI 用量（DeepSeek+Tavily+OpenCode）
- 📌 **菜单栏信息增强** — 菜单栏新增温度计图标、温度、CPU 使用率，3 秒刷新
- ⚙️ **显示设置** — 设置面板新增温度监控开关
- 🗂️ **系统监控** — 标题从「AI 用量监控」改为「系统监控」

### v1.4.4

- ⏱️ **Hindsight 启动等待延长至 2 分钟** — 重启后 app 最多等 2 分钟直到 Hindsight 就绪，不再因为 PostgreSQL/模型加载慢而错过

### v1.4.3

- 🐛 **OpenCode 登录 cookie 同步修复** — 登录成功时立即同步 cookie 到 HTTPCookieStorage，刷新不再报"登录已过期"

### v1.4.2

- 🧠 **Hindsight 版本显示** — 看板标题栏 + 右侧面板同时显示当前版本号
- 🔄 **自动更新检查** — 左侧看板每 2 小时自动查 PyPI，右侧面板每次刷新时带缓存检查
- ⬆ **新版本提醒** — 有新版本时橙色标签/文字提示升级
- 📐 **看板自适应布局** — 网格列数随窗口宽度自动适配（窄→1列 / 中→2列 / 宽→3列）
- 🧩 **心智模型始终显示** — 即使 0 条也灰显入口
- 🐛 **API 字段适配** — 修正 fact_type / date 字段映射，数据正确显示
- 🏷️ **版本号统一** — Info.plist / README / GitHub 统一为 v1.4.2
- 🐛 **Info.plist 构建变量修复** — 替换 $(EXECUTABLE_NAME) 等为字面值，修复 bundle 读取
- 🎨 **OpenCode 登录 UI 精简** — 提取公共组件消除 108 行重复代码
- 🧹 **代码清理** — 移除冷 msg handler、统一版本号扩展、proxyDir 硬编码修复、catch 日志化
- 🔧 **设置面板遮挡修复** — 点击设置/看板时弹窗自动关闭，不遮挡新面板
- 🏷️ **Dock 图标隐藏** — 添加 LSUIElement=true，纯菜单栏应用
