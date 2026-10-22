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
  <img alt="Version" src="https://img.shields.io/badge/version-1.13.3-blue">
</p>

AIUsageMonitor 是一个 macOS 菜单栏轻量级系统监控工具，实时显示笔记本温度、CPU 使用率、AI 用量（DeepSeek / Tavily / MiniMax / OpenRouter / Command Code / OpenCode GO / Open Design AMR）和 Hindsight 记忆状态。支持自动刷新和手动刷新。

## 前置依赖

Hindsight 看板需要两个后端服务配合运行：

### 1. Hindsight API（端口 9077）

核心记忆引擎。通过 pip 安装并运行：

```bash
pip install hindsight-api -U
hindsight-api --port 9077
```

API Key 和 LLM 提供者通过环境变量配置。详见 [Hindsight 官方文档](https://hindsight.vectorize.io/developer/installation)。

### 2. Hindsight Control Plane（端口 9999）

官方 Web 看板，用于浏览记忆银行、搜索记忆和管理配置。需要 **Node.js 18+**。

```bash
# 全局安装（一次）
npm install -g @vectorize-io/hindsight-control-plane

# 启动（指向本地 API）
hindsight-control-plane --api-url http://localhost:9077
```

Control Plane 默认运行在 9999 端口，AIUsageMonitor 的原生看板窗口会自动加载此地址。

> 要实现开机自启，两个服务都可通过 launchd 管理。参考 [`scripts/`](./scripts/) 目录下的 plist 配置。

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
- 🌐 **OpenRouter 用量监控** — 账户充值/已用/剩余余额（`/api/v1/credits`）+ 当日花费（beta Analytics API，按天分组）。需在设置中配置 Management Key
- ✨ **MiniMax Token Plan** — 中国区订阅用量卡片，每个模型族（general / video）显示 5h 滚动窗口 + 周窗口进度条（已用量百分比），底部倒计时「重置于 X 小时之后」
- 🔄 **OpenCode GO 用量监控** — RPC 查询用量百分比，支持 WKWebView 内嵌登录与浏览器备选
- 🧩 **Open Design (AMR) 用量监控** — Coding Plan 的 5h / 周滚动窗口已用百分比 + 重置倒计时 + 钱包余额，读本机 Open Design 自带的 `vela` CLI，不需要 API Key
- ⬇️ **抖音视频下载** — 菜单栏「抖音」按钮，粘作品链接（作品页 / 带 `modal_id` 的主页链接 / 短链 / 分享文案都行）即可把最高清晰度源存进「下载」文件夹；通常能拿到 4K，而网页播放器只给你 540p/720p。用隐藏 WKWebView 截页面自己发出的签名请求，不逆向签名算法；接口路径或字段变动能自愈，拿不到时降级用播放器当前流
- 🧠 **Hindsight 原生看板** — 点击「看板」打开官方 Hindsight Control Plane（端口 9999），完整浏览记忆银行、搜索和实体关系
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

### OpenRouter
- 余额通过 `https://openrouter.ai/api/v1/credits` 获取（需 Management Key）
- 当日花费通过 `POST https://openrouter.ai/api/v1/analytics/query`（beta Analytics API，按 day 分组，UTC 日对齐）

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

### v1.13.3

- 🔁 **Open Design (AMR) 卡片不再空白** — 上游 `amr-api.open-design.ai` 的账单接口偶发断连（`EOF`，实测约 7% 请求失败），原来一次失败就把卡片刷成「暂无数据」，要等下一轮刷新才恢复。现在读取会重试最多 3 次（间隔 0.5 秒），并且 `DataStore` 保留上次成功快照：真失败时显示旧数字 + 「⚠️ 本次读取失败，显示上次数据」，不再空白

### v1.13.2

- ⌨️ **补「编辑」菜单** — App 原来根本没有编辑菜单，而 macOS 的 ⌘V／⌘C／⌘A／⌘Z 是走菜单项快捷键的，所以之前粘链接只能右键 → 粘贴（设置里粘 API Key 也一样）。现在标准编辑菜单就位，这些快捷键全 App 可用
- 🎯 **自动聚焦** — 抖音窗口打开即把光标放进链接输入框，按 ⌘V 直接生效，不用先点一下输入框

### v1.13.1

- ⬇️ **抖音视频下载** — 菜单栏新增「抖音」入口（在「小说」和「退出」之间）。粘链接即把最高清晰度源存进「下载」文件夹，通常是 2160×3840 —— 网页播放器对未登录访客只给 540p/720p。解析靠隐藏 `WKWebView` 钩住页面自己发出的 `/aweme/detail` 响应，签名由平台自己的 JS 现算，不逆向
- 🛡️ **抗改版** — 判定看响应内容（含 `"play_addr"`）而不是接口路径；解析递归全树找 `play_addr*`，不绑死 `video.bit_rate[]`，并按 `aweme_id` 锁定目标作品；25 秒拿不到数据则降级用播放器当前流（画质降一档但仍能下载），不再直接失败
- 🔧 **修复** — v1.13.0 是从不含这些文件的提交构建的，导致发出去的包里按钮消失；现已随版本号一起提交

### v1.13.0

- 🧩 **Open Design (AMR) 用量卡片** — 显示 Coding Plan 档位、5 小时与每周滚动窗口已用百分比（带重置倒计时）、钱包余额。AMR 的 API Key 读不到用量（`/v1/usage`、`/v1/me`、`/v1/credits` 实测全 404，上游 issue #8674 待实现），因此改走账号侧：调本机 Open Design 自带的 `vela billing preflight --workspace-id … --format json`。`vela` 路径按版本目录扫描自动定位，workspace id 从 App 日志自动探测，两者都能在设置里手填覆盖
- 🎛️ **设置** — 新增「Open Design (AMR) 用量」开关与可选的工作区 ID 输入框

### v1.12.0

- ⏱️ **OpenCode GO 重置时间改为实时倒计时** — 「重置于」不再显示绝对日期（9月30日 19:16），改为官网同款的「X天X小时X分钟」，`resetsAt` 存为 `Date` 在渲染时计算，弹窗打开期间持续走秒；无 API Key 的抓取链路仍回退页面原文
- 🔁 **Command Code** — 天级倒计时补上分钟（`1天2小时3分钟`，原为 `1天2小时`）

### v1.11.1

- 🐛 **启动时弹出空白"设置"窗口** — 空窗口来自 SwiftUI 的 `Settings { EmptyView() }` 场景：它是 app 里唯一的场景，macOS 启动时会自动弹出。现在入口改为纯 AppKit（`main.swift`），不再有 SwiftUI App 生命周期；真正的设置窗口仍是菜单栏「设置」按钮打开的 NSPanel

### v1.11.0

- 🔑 **OpenCode GO 支持 API Key 直查** — `GET /zen/go/v1/usage`（Bearer 鉴权）直接返回滚动/每周/每月用量百分比与重置时间，无需浏览器登录；未配置 Key 时回退原有 cookie/RPC 链路
- 🎛️ **设置** — OpenCode GO 区新增 Go API Key 输入框（存 Keychain）
- 🐛 **Bug 修复**
  - **OpenCode 登录**：工作区 URL 为空/无效时不再弹出空白登录窗口，`showLoginWindow` 入口直接拒绝
  - **Tavily**：修复 `planLimit` 改可选后遗留的单测编译错误

### v1.10.1

- 🐛 **Bug 修复**
  - **Command Code**：移除月度额度警告 label（使用过半/即将耗尽提示），月度额度和重置倒计时移至每周窗口下方，顺序：5小时 → 每周 → 月度额度 → 本期汇总
  - **Tavily**：修复免费版用户（`plan_limit: null`）JSON 解码失败问题，`planLimit` 改为可选字段；新增 `tavilyKeyConfigured` 标记，区分「Key 已配置但获取失败」与「Key 未配置」两种状态

### v1.10.0

- 📊 **Command Code 卡片：百分比 + 重置倒计时** — 月度额度改为百分比显示（已用 %），5 小时 / 每周 / 月度三个进度条下新增「重置于 X小时X分钟 / X天X小时」倒计时。月度重置取账单周期结束（`currentPeriodEnd`，修复毫秒时间戳解析）
- 🗓️ **顺序调整** — 月度额度移到每周窗口下方（5小时 → 每周 → 月度）

### v1.9.0

- 🐐 **Command Code 用量卡片** — 菜单栏新增订阅用量卡片（GOAT / Pro / Max 通用）：月度剩余额度 vs $70 上限进度条、5 小时和每周滚动窗口用量条（含重置倒计时）、本期总花费/请求数/Tokens。与 CLI 共用同一把 API Key（内部 `/alpha/*` 端点：whoami、billing/credits、billing/subscriptions、usage/summary）
- 🎛️ **设置** — 新增「Command Code 用量」开关和 API Key 输入框

### v1.8.0

- 🌐 **OpenRouter 用量卡片（重新加入）** — 菜单栏新增账户用量卡片，通过 `/api/v1/credits` 显示充值总额/已用/剩余余额，并额外通过 beta Analytics API（`/api/v1/analytics/query`）按天分组展示**当日花费**。需在设置中配置 OpenRouter **Management Key**
- 🎛️ **设置** — 新增「OpenRouter 用量」开关和 Management Key 输入框

### v1.7.0

- ✨ **MiniMax Token Plan 卡片** — 菜单栏新增中国区订阅用量卡片，每个模型族（general / video）显示 5h 滚动窗口 + 周窗口进度条（已用量百分比）和「重置于 X 小时之后」倒计时。需在设置中粘贴订阅 Key（eyJ... JWT 格式，与按量计费 API Key 不互通）
- 🎛️ **设置** — 新增「MiniMax Token Plan」和「显示 video 模型」开关
- 🗑️ **移除 OpenRouter** — 菜单栏卡片、服务、设置面板和开关全部删除（已是无用代码）

### v1.6.0

- 📖 **小说创作 Web 集成** — 新增「小说」按钮（看板旁），一键启动内置 Flask Web UI（端口 8080）并在原生窗口打开；web/ 目录随本项目维护
- 🚀 **自动拉起服务** — 点击按钮自动检测并启动小说 Web 服务（web/.venv），退出应用时自动清理
- 🎨 **Web UI 精美升级** — 小说列表渐变封面卡片、总览页 hero + 统计卡 + SVG 字数面积图（悬停详情）+ 质量总览、章节页 pill 徽章表格、人物页渐变头像卡片、世界观章节卡片、故事架构卷时间线、连载追踪状态徽章、药丸按钮与毛玻璃质感统一

### v1.5.3

- 🧹 **状态栏精简** — 去掉菜单栏标题中的 CPU 使用率百分数，仅保留温度 + 网速
- 🧠 **Hindsight 原生看板** — 替换内嵌网页代理为 Hindsight 官方 Control Plane 看板（端口 9999）
- 🗑️ **清理** — 移除旧的 hindsight-server.py 和 hindsight-dashboard.html 资源文件
- 📋 **前置依赖说明** — 新增 Hindsight API + Control Plane 服务的安装与配置指南

### v1.5.1

- 🧹 **简化心智模型页面** — 移除分类筛选标签，只保留「全部」视图
- 🐛 **小修复** — 精简心智模型列表 UI
