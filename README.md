# AIUsageMonitor

<p align="center">
  <img src="docs/images/app-icon.png" alt="AIUsageMonitor 图标" width="120">
</p>

<p align="center">
  macOS 菜单栏网速监控工具
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/github/v/release/zdx52/AIUsageMonitor">
  <img alt="License" src="https://img.shields.io/github/license/zdx52/AIUsageMonitor">
  <img alt="macOS" src="https://img.shields.io/badge/platform-macOS-lightgray">
</p>

## 更新内容 (v1.3.4)

- 🚀 **菜单栏网速显示** — 用 `getifaddrs()` 每秒采样网速，菜单栏实时显示 `↓下载 ↑上传`
- 🎨 **文字颜色标示状态** — 健康默认色、预警橙色、严重红色，一目了然
- ♻️ **重构 NSStatusItem** — 告别 SwiftUI MenuBarExtra，标题更新更可靠
- 🔑 **Keychain 优化** — 添加访问控制，不再频繁弹窗

## 使用

从 [GitHub Releases](https://github.com/zdx52/AIUsageMonitor/releases) 下载最新 `AIUsageMonitor.dmg`，安装后点击菜单栏图标可查看详细数据。

## 构建

```bash
git clone git@github.com:zdx52/AIUsageMonitor.git
cd AIUsageMonitor
swift build -c release
```
