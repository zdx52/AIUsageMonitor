---
title: .app bundle 部署与版本号五处同步
date: 2026-08-05
category: deployment
module: 部署
problem_type: tooling_decision
severity: high
applies_when:
  - 改了代码要部署到 /Applications/AIUsageMonitor.app
  - 改了版本号时
tags: [deploy, app-bundle, version, codesign]
---

# .app bundle 部署与版本号五处同步

## Context

本项目是 macOS 菜单栏应用（Swift），用户安装的是 `/Applications/AIUsageMonitor.app`。
之前踩过坑：只改了代码提交 git，没有同步部署到 .app，导致用户跑的还是旧版本；
改版本号时只改了一两处，导致 README/Info.plist 显示不一致。

## Guidance

**部署：** 运行 `./scripts/deploy.sh` 一键完成，脚本自动执行：
1. `swift build -c release` 构建
2. 复制二进制到 `/Applications/AIUsageMonitor.app/Contents/MacOS/`
3. 复制 Info.plist（版本号同步的关键步骤）
4. `codesign --force --sign -` 重签名（ad-hoc）
5. `killall AIUsageMonitor` + `open` 重启

**版本号五处同步（改版本号时全部要改）：**
1. `AIUsageMonitor/Info.plist` — `CFBundleShortVersionString`
2. `README.md` — badge 和更新日志
3. `README_CN.md` — badge 和更新日志
4. GitHub Release tag
5. GitHub About description（如含版本号）

## Why This Matters

- **禁止只提交 git 不部署**：用户会直接运行旧版并以为功能没做。改完代码必须 `deploy.sh` 部署。
- 版本号不同步：README badge 显示 1.5.3 但应用实际 1.5.2，用户混淆，排查困难。
- Info.plist 复制进 bundle 的顺序在 deploy.sh 里是硬编码的，不要手工往 bundle 里拷二进制（会漏 plist）。

## When to Apply

- 每次修改功能代码、准备让用户试新版本时
- 每次 bump 版本号时（五处一起改）

## Examples

```bash
# 改完代码后
./scripts/deploy.sh
# 验证版本
defaults read /Applications/AIUsageMonitor.app/Contents/Info CFBundleShortVersionString
```

## Related

- [git-push-release-workflow.md](../workflow/git-push-release-workflow.md) — 部署完记得走推送流程
