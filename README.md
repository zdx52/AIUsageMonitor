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
  <img alt="Version" src="https://img.shields.io/badge/version-1.5.2-blue">
</p>

AIUsageMonitor is a lightweight macOS menu bar system monitor that displays real-time laptop temperature, CPU usage, AI service usage (DeepSeek / Tavily / OpenCode GO), and Hindsight memory stats. Supports auto-refresh and manual refresh.

## Prerequisites

The Hindsight dashboard requires two backend services to be running:

### 1. Hindsight API (port 9077)

The core memory engine. Install and run via pip:

```bash
pip install hindsight-api -U
hindsight-api --port 9077
```

API keys and LLM provider are configured via environment variables. See the [Hindsight documentation](https://hindsight.vectorize.io/developer/installation) for details.

### 2. Hindsight Control Plane (port 9999)

The official web UI for browsing memory banks, searching memories, and managing configuration. Requires **Node.js 18+**.

```bash
# Install globally (one-time)
npm install -g @vectorize-io/hindsight-control-plane

# Run (pointing to your local API)
hindsight-control-plane --api-url http://localhost:9077
```

The Control Plane starts on port 9999 by default. AIUsageMonitor's native dashboard window loads this URL automatically.

> For auto-start on login, both services can be managed via launchd. See [`scripts/`](./scripts/) for example plist files.

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
- 🧠 **Hindsight Dashboard** — Opens native Hindsight Control Plane (port 9999) with official web UI for memory banks, recall, and entity exploration
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

### v1.5.2

- 🧠 **Hindsight native dashboard** — Replaced embedded web proxy with native Hindsight Control Plane (port 9999)
- 🗑️ **Cleanup** — Removed old hindsight-server.py and hindsight-dashboard.html resources
- 📋 **Prerequisites documented** — Added setup guide for Hindsight API + Control Plane services

### v1.5.1

- 🧹 **Simplify mental model page** — Removed category filters, only show "全部" (All) view
- 🐛 **Minor fixes** — Streamlined mental model list UI
