---
title: ad-hoc 重签名让 keychain ACL 失联，SecItemCopyMatching 阻塞 securityd
date: 2026-08-19
category: deployment
module: 现代Swift菜单栏app
problem_type: integration_issue
severity: high
symptoms:
  - 填了 OpenRouter/DeepSeek 等 API Key，界面“暂无数据”/余额不更新
  - app 内所有服务（Tavily/OpenRouter/DeepSeek）同时卡死，连网络请求都没发出
root_cause: deploy.sh 每次 codesign --force --sign - 重签名（新签名不在 keychain 条目的受信任应用 ACL 里）→ macOS 交给 securityd 等授权 → 菜单栏 app 无可见窗口，授权弹窗滞留，SecItemCopyMatching 永久阻塞
resolution_type: code_fix_plus_manual_grant
tags: [keychain, secitemcopymatching, securityd, codesign, ad-hoc, macos, tcc, secret-storage]
---

# ad-hoc 重签名让 keychain ACL 失联，SecItemCopyMatching 阻塞 securityd

> 这是本项目 `OpenRouter` 余额监控「Management Key 填了没作用」的根治报告。排查耗时很长（被“URLSession 卡住”误导过），死路和根因都值得记下来。

## Problem

用户在 app 里填好 OpenRouter Management Key 后，余额/用量卡片一直不更新（“没有作用”）。现象是**所有**依赖 Keychain 的服务同时失效，不是单个 API 的问题。

## Symptoms

- 填了 key、重启 app，OpenRouter 卡片仍 `暂无数据` / 旧缓存
- 偶发错误：`KeychainHelper.get` 返回 `OSStatus -10814`（errSecConnectionLoad，keychain 访问被拒）
- 用 `sample` 抓线程栈：**每个**并发服务（Tavily/OpenRouter/DeepSeek）都卡在：
  ```
  KeychainHelper.get(key:)  →  SecItemCopyMatching
    →  SecurityServer::ClientSession::decrypt
      →  mach_msg   ← 永久阻塞在 securityd（钥匙串守护进程）
  ```
  没有任何 HTTP 请求发出（URLSession 从未被调用）。

## What Didn't Work

- **加 URLSession 超时** — 无济于事，因为根本没走到网络那一步（所有线程停在读 key）。
- **绕过系统代理 / 强制直连（`connectionProxyDictionary = [:]`）** — 无效；独立 Swift 脚本直连 `openrouter.ai` 0.7s 就通，但 app 内照旧卡死，证明不是网络问题。
- **怀疑 MainActor 被占住** — 用 `sample` 验证，主线程空闲（在等事件），罪魁是后台并发队列全卡在 `SecItemCopyMatching`。并发服务彼此独立的坑，用线程采样一眼看穿。

## Solution

1. **根因不是代码，是授权**：`deploy.sh` 每次都 `codesign --force --sign -`（ad-hoc）重新签名，每次生成的签名码不同。keychain 通用密码条目带着“受信任应用 ACL”，指向创建它的那次签名；新签名不在 ACL → macOS 交给 `securityd` 弹“允许访问钥匙串”授权 → 菜单栏 app（无 Dock 窗口）弹窗滞留，`SecItemCopyMatching` 永久阻塞。
2. **一次性授权即可恢复**：在系统弹出的钥匙串访问授权里确认一次（本案例用户输入密码后全部恢复）。之后 App 内 `/key`、`/credits` 都正常返回，Management Key 算出 `余额 = totalCredits - totalUsage`（例：$10.00 − $0.90 = $9.10）。
3. **代码侧优化（可选但推荐）**：KeychainHelper 保持 Keychain 存储，但 OpenRouter 的请求用 `.ephemeral` + `connectionProxyDictionary = [:]` 强制直连，直连实测 0.7s 优于走 10808 代理 3.7s，且不受多请求并发挤占代理影响。

## Why This Works

授权把“当前签名”加入 keychain 条目的受信任 ACL，`SecItemCopyMatching` 不再被 `securityd` 拦截，读 key 立即返回。直连 session 则从网络链路侧消除了对系统代理的依赖，双保险。

## Prevention

- **每次 `deploy.sh`（重签名）后，如遇“填 key 无作用”，优先怀疑 keychain ACL/授权，用 `sample <pid> 3` 看线程栈确认卡在 `SecItemCopyMatching`，不要先去查网络。**
- 菜单栏 app 无窗口，TCC/keychain 授权弹窗容易被漏掉；可在 `applicationDidFinishLaunching` 时记录一次 keychain 读取状态，便于诊断。
- 若反复被授权问题困扰，可评估把这道 API Key 改存 UserDefaults（明文、无 ACL，重签名永远生效）——安全性换便利，需用户拍板。
- 参考本仓库其它部署坑：[app-bundle-deploy.md](./app-bundle-deploy.md)（deploy.sh 重签名是该根因的源头）。

## Related

- [app-bundle-deploy.md](./app-bundle-deploy.md) — deploy.sh 的 `codesign --force --sign -` 滚动重签名是触发此坑的直接原因