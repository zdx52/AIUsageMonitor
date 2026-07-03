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
  <img alt="Version" src="https://img.shields.io/badge/version-1.4.10-blue">
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

### v1.4.10

- 🐛 **Fix status bar contamination** — Remove leftover debug code that periodically appended DeepSeek balance to the menu bar title
- 🌡️ **Fix GPU temperature on app autolaunch** — Use absolute path for `smctemp` instead of relying on PATH, fixing GPU temp display when launched via Finder/dock (vs terminal)
- 🔧 **Code cleanup** — Consolidate `getCPUTemperature()` / `getGPUTemperature()` into shared `runSmctemp(arg:)`
