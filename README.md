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
  <img alt="Version" src="https://img.shields.io/badge/version-1.13.0-blue">
</p>

AIUsageMonitor is a lightweight macOS menu bar system monitor that displays real-time laptop temperature, CPU usage, AI service usage (DeepSeek / Tavily / MiniMax / OpenRouter / Command Code / OpenCode GO / Open Design AMR), and Hindsight memory stats. Supports auto-refresh and manual refresh.

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
- 🌐 **OpenRouter Usage** — Account balance (total/used/remaining) + today's spend via the Analytics API. Requires a Management Key
- ✨ **MiniMax Token Plan** — China subscription usage (5h + weekly windows per model family, with countdown reset)
- 🔄 **OpenCode GO** — RPC usage % with WKWebView login & browser fallback
- 🧩 **Open Design (AMR)** — Coding Plan 5h / weekly rolling windows (used %) with reset countdowns + wallet balance, read from the locally installed Open Design `vela` CLI (no API key)
- ⬇️ **Douyin Downloader** — Paste a Douyin video link (page URL, `modal_id` profile link, short link, or share text) and save the highest source — usually 4K, which the web player never hands out — straight into `~/Downloads`. A hidden WKWebView captures the page's own signed API response, so no signature reverse-engineering; endpoint/JSON drift is tolerated and it falls back to the player stream when the API gives nothing
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

### OpenRouter
- Balance via `https://openrouter.ai/api/v1/credits` (requires a Management Key)
- Today's spend via `POST https://openrouter.ai/api/v1/analytics/query` (beta Analytics API, grouped by day, UTC-aligned)

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

### v1.13.2

- ⌨️ **Edit menu** — The app had no 编辑 menu at all, and macOS routes ⌘V / ⌘C / ⌘A / ⌘Z through menu key equivalents, so pasting a link only worked via right-click → Paste (same for API key fields in Settings). Added the standard Edit menu; those shortcuts now work app-wide
- 🎯 **Auto-focus** — The Douyin window puts the caret in the link field on open, so ⌘V works immediately without clicking the field first

### v1.13.1

- ⬇️ **Douyin Downloader** — New menu bar entry (between 小说 and 退出). Paste a video link and the highest source lands in `~/Downloads` — usually 2160×3840, which the web player never exposes to logged-out visitors. Extraction hooks the page's own `/aweme/detail` response inside a hidden `WKWebView`, so the platform's signature is computed by the platform itself
- 🛡️ **Drift tolerance** — Matching is by response content (`"play_addr"`), not endpoint path; parsing walks the whole JSON tree instead of `video.bit_rate[]` and locks onto the requested `aweme_id`; a 25s timeout falls back to the player's current stream (lower quality, still downloads) instead of failing
- 🔧 **Fixed** — v1.13.0 was built from a commit that did not contain these files, so the button vanished from the shipped app; the feature is now committed and versioned together

### v1.13.0

- 🧩 **Open Design (AMR) usage card** — New menu bar card showing the Coding Plan tier, 5-hour and weekly rolling windows (used % with reset countdowns), and wallet balance. The AMR API key cannot read usage (`/v1/usage`, `/v1/me`, `/v1/credits` all return 404 — upstream issue #8674), so this reads the account-side `vela billing preflight --workspace-id … --format json` shipped inside the local Open Design app. `vela` path is discovered by scanning the versioned app directories, the workspace id is auto-detected from the app log, and both can be overridden in Settings
- 🎛️ **Settings** — Added an "Open Design (AMR) 用量" toggle and an optional workspace id field

### v1.12.0

- ⏱️ **OpenCode GO reset countdown** — The "重置于" line now shows a live countdown (`3天5小时20分钟` / `5小时20分钟` / `20分钟`) instead of an absolute date (`9月30日 19:16`), matching the official dashboard's wording. `resetsAt` is kept as a `Date` and formatted at render time, so it ticks while the popover is open; the cookie/scraped page text is still used as a fallback
- 🔁 **Command Code** — Day-scale countdowns now include minutes too (`1天2小时3分钟` instead of `1天2小时`)

### v1.11.1

- 🐛 **Blank settings window on launch** — the app's only SwiftUI scene was `Settings { EmptyView() }`, so macOS auto-presented it at launch as an empty "AIUsageMonitor 设置" window. The app now starts from a plain AppKit entry point (`main.swift`) with no SwiftUI App lifecycle; the real settings window is still the panel opened by the 设置 button

### v1.11.0

- 🔑 **OpenCode GO via API key** — Direct usage lookup: `GET /zen/go/v1/usage` with a Go API key (Bearer) returns rolling/weekly/monthly usage percentages plus reset times, no browser login required. Falls back to the existing cookie/RPC flow when no key is set
- 🎛️ **Settings** — Added a "Go API Key" field to the OpenCode GO section (stored in Keychain)
- 🐛 **Bug fixes**
  - **OpenCode login**: the login window no longer pops up blank when the workspace URL is empty/invalid — `showLoginWindow` now rejects bad URLs up front
  - **Tavily**: fixed a pre-existing test compile error left over from making `planLimit` optional

### v1.10.1

- 🐛 **Bug fixes**
  - **Command Code**: removed monthly allowance warning labels (over-70%/over-90% alerts); monthly meter and reset countdown moved below the weekly meter — new order: 5-hour → weekly → monthly → period summary
  - **Tavily**: fixed JSON decode failure for free-tier users (`plan_limit: null`) by making `planLimit` optional; added `tavilyKeyConfigured` flag to distinguish "key configured but fetch failed" from "key not configured"

### v1.10.0

- 📊 **Command Code card: percentage + reset countdowns** — Monthly allowance now shows as a percentage (used %), with reset countdowns in "Xh Ym" / "Xd Xh" format below the 5-hour, weekly, and monthly meters. Monthly reset is sourced from the billing period end (`currentPeriodEnd`, fixed fractional-seconds parsing)
- 🗓️ **Order** — Monthly meter moved below the weekly meter (5-hour → weekly → monthly)

### v1.9.0

- 🐐 **Command Code usage card** — New menu bar card showing GOAT (or Pro/Max) subscription usage: monthly credit remaining vs. $70 cap with progress bar, 5-hour and weekly rolling window meters with reset countdowns, and current billing period total cost / request count / tokens. Uses the same API key as the CLI (internal `/alpha/*` endpoints: whoami, billing/credits, billing/subscriptions, usage/summary)
- 🎛️ **Settings** — Added "Command Code 用量" toggle + API Key input

### v1.8.0

- 🌐 **OpenRouter Usage card (re-added)** — Menu bar card showing account balance (total credits / used / remaining) from the `/api/v1/credits` endpoint, plus **today's spend** from the beta Analytics API (`/api/v1/analytics/query`), grouped by day. Requires an OpenRouter **Management Key** in Settings
- 🎛️ **Settings** — Added "OpenRouter 用量" toggle + Management Key input

### v1.7.0

- ✨ **MiniMax Token Plan card** — New menu bar card showing China subscription usage per model family (general / video): 5h rolling window + weekly window with progress bars (used %) and "重置于 X 小时之后" reset countdowns. Requires subscription Key (eyJ...) in Settings, separate from the pay-as-you-go API Key
- 🎛️ **Settings** — Added "MiniMax Token Plan" + "show video model" toggles
- 🗑️ **Removed OpenRouter** — Card, service, settings panel and toggle all removed (unused dead code)

### v1.6.0

- 📖 **Novel Writing Web UI integrated** — New "小说" (Novel) button next to the dashboard launches the built-in Flask web UI (port 8080) in a native window; the web/ app is now maintained in this repo
- 🚀 **Auto service startup** — Clicking the button detects and starts the novel web service (web/.venv) automatically; cleaned up on app exit
- 🎨 **UI polish** — Gradient book covers (real cover images from 封面/ take priority), overview hero with SVG word-count chart (hover details) + quality summary, character avatar cards, world/outline/tracking card layouts, pill badges, macOS glassmorphism, evenly spaced menu bar buttons

### v1.5.3

- 🧹 **Cleaner status bar** — Removed CPU usage percentage from menu bar title, keeping temperature + network speed only
- 🧠 **Hindsight native dashboard** — Replaced embedded web proxy with native Hindsight Control Plane (port 9999)
- 🗑️ **Cleanup** — Removed old hindsight-server.py and hindsight-dashboard.html resources
- 📋 **Prerequisites documented** — Added setup guide for Hindsight API + Control Plane services

### v1.5.1

- 🧹 **Simplify mental model page** — Removed category filters, only show "全部" (All) view
- 🐛 **Minor fixes** — Streamlined mental model list UI
