# AIUsageMonitor

<p align="center">
  <img src="docs/images/app-icon.png" alt="AIUsageMonitor Icon" width="120">
</p>

<p align="center">
  macOS Menu Bar System Monitor
</p>

<p align="center">
  <a href="README_CN.md">📖 中文版</a>
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/github/v/release/zdx52/AIUsageMonitor">
  <img alt="License" src="https://img.shields.io/github/license/zdx52/AIUsageMonitor">
  <img alt="Swift" src="https://img.shields.io/badge/swift-5.0-orange">
  <img alt="macOS" src="https://img.shields.io/badge/platform-macOS-lightgray">
  <img alt="Version" src="https://img.shields.io/badge/version-1.4.7-blue">
</p>

AIUsageMonitor is a lightweight macOS menu bar system monitor that displays real-time laptop temperature, CPU usage, AI service usage (DeepSeek / Tavily / OpenCode GO), and Hindsight memory stats. Supports auto-refresh and manual refresh.

## Quick Start

Download the latest release from [GitHub Releases](https://github.com/zdx52/AIUsageMonitor/releases):

- `AIUsageMonitor.dmg` — Universal macOS installer

After installation:

1. Mount the DMG and drag `AIUsageMonitor.app` to Applications
2. Launch AIUsageMonitor
3. Click the menu bar icon to view data
4. Configure API keys & workspace URL in Settings

> ⚠️ If Gatekeeper blocks the app, **right-click → Open** or allow it in System Settings > Privacy & Security.

## Features

- 🌡️ **Temperature Monitor** — Real-time battery temp, CPU usage & thermal state
- 🐋 **DeepSeek Balance** — Check total, granted & topped-up balance
- 🔍 **Tavily Usage** — Monthly quota, used & remaining credits
- 🔄 **OpenCode GO** — RPC usage % with WKWebView login & browser fallback
- 🧠 **Hindsight Dashboard** — Total memories, experiences, observations & world facts
- 🌐 **Network Speed** — Real-time ↓↑ network speed, 3s refresh
- 🟢 **Health Indicator** — Color-coded: default/orange/red for health status
- 🔒 **Secure Storage** — API keys stored in macOS Keychain
- ⏱️ **Auto Refresh** — Configurable refresh interval (1-30 min)
- 👁️ **Show/Hide Cards** — Toggle each module's visibility in settings
- ⚙️ **Settings Panel** — Visual config for API keys, workspace & refresh

## Data Sources

### DeepSeek
- Balance via `https://api.deepseek.com/user/balance`
- Daily usage via WebView scraper from `https://platform.deepseek.com/usage`

### Tavily
- Usage via `https://api.tavily.com/usage`
- Shows plan type, monthly limit, used & remaining credits

### OpenCode GO
- Usage via RPC + WKWebView scraping
- Supports WKWebView embedded login (GitHub / Google OAuth)
- System browser login as fallback
- Manual confirmation button on login failure

## FAQ

### "Cannot verify developer" on first launch

This build uses ad-hoc signing. Gatekeeper blocks it. Run in terminal:

```bash
xattr -dr com.apple.quarantine /Applications/AIUsageMonitor.app
```

### How to add API Key?

Click the menu bar icon → Settings → Paste API Key → Save.

## Build

Requires macOS 14+, Xcode 15+.

```bash
git clone git@github.com:zdx52/AIUsageMonitor.git
cd AIUsageMonitor
swift build -c release
cp -r .build/release/AIUsageMonitor AIUsageMonitor.app/Contents/MacOS/
```

## Changelog

### v1.4.7

- 💥 **Fix arithmetic overflow crash** — `NetworkSpeedMonitor` UInt64 subtraction overflow when network interfaces change during high-speed downloads, causing `SIGTRAP`. Added safe subtraction with overflow check
- ⏱️ **Upgrade timeout protection** — Add 60s timeout + anti-double-click guard to `runUpgrade()`. Process is killed gracefully on timeout
- 📋 **Live upgrade console** — Real-time log panel at bottom of dashboard showing each step's output. Pipe-based stdout capture with `[STEP:N]` markers
- 🐍 **uv tool upgrade** — Fix upgrade script to upgrade `uv tool` (actual runtime path) not just `pip` (venv). Add Aliyun mirror + official PyPI dual-index strategy
- ⏳ **Health check extended** — Increase wait loop from 20s to 60s for model loading. Add per-5-iteration progress message
- 🏗️ **v1.4.6 changes** (restored):

### v1.4.6

- 🐛 **Fix debug string interpolation** — Fix 12 debug print statements in OpenCodeWebViewScraper where double backslashes prevented variable interpolation
- 🧹 **Compiler warning cleanup** — Eliminate 8 warnings (unused variables, unhandled resource files)
- 📦 **Package.swift improvement** — Add exclude declarations for Info.plist / entitlements / icns

### v1.4.5

- 🌡️ **Temperature Monitor** — New temperature card with battery temp, CPU usage & thermal state. Vertical thermometer icon (color-coded) and live data in menu bar
- 📊 **Dual-Column Layout** — Popover split into system (left) and AI usage (right) columns
- 📌 **Enhanced Menu Bar** — Thermometer icon, temp & CPU in menu bar, 3s refresh
- ⚙️ **Settings** — New temperature toggle in settings panel
- 🗂️ **System Monitor** — Title changed from "AI Usage Monitor" to "System Monitor"

### v1.4.4

- ⏱️ Hindsight startup wait extended to 2 minutes — app retries up to 2 min for Hindsight readiness after restart

### v1.4.3

- 🐛 OpenCode login cookie sync fix — sync cookies to HTTPCookieStorage immediately on login

### v1.4.2

- 🧠 Hindsight version display in dashboard title + sidebar
- 🔄 Auto update check from PyPI every 2 hours
- ⬆ New version alert with orange label
- 📐 Responsive dashboard grid layout (1/2/3 columns)
- 🧩 Mental model always visible (grayed out when empty)
- 🐛 API field mapping fixes
- 🏷️ Unified version across Info.plist / README / GitHub
- 🎨 Refactored OpenCode login UI, removed 108 lines of duplicate code
- 🔧 Settings panel z-order fix — popover closes before opening settings
- 🏷️ LSUIElement=true, pure menu bar app (no Dock icon)
