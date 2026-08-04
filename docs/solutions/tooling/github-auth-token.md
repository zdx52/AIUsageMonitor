---
title: GITHUB_TOKEN 与 gh CLI 的认证方式
date: 2026-08-05
category: tooling
module: CI/发布
problem_type: tooling_decision
severity: medium
applies_when:
  - 需要执行 GitHub API 操作（改 About、建 Release、传 DMG）
  - gh CLI 提示未登录时
tags: [github, token, gh-cli, auth]
---

# GITHUB_TOKEN 与 gh CLI 的认证方式

## Context

本项目机器的 gh CLI **未登录**（`gh auth status` 会提示未认证）。
Release/API 操作全靠 GITHUB_TOKEN 环境变量。

## Guidance

- **Token 存放位置**：`~/.zshrc`，格式 `export GITHUB_TOKEN=ghp_...`
- **使用前必须 source**：`source ~/.zshrc`（新 shell 或非交互环境不会自动加载）
- **gh CLI 绕过登录**：`export GITHUB_TOKEN=...` 后 gh 命令直接用 token 认证，不需要 `gh auth login`
- **API 直调**：`curl -H "Authorization: token $GITHUB_TOKEN"` 同样可用

## Why This Matters

- 不 source 就 echo $GITHUB_TOKEN 是空的 → API 401 → 发布流程卡住
- 不要试图 `gh auth login` 交互登录（用户环境没配 browser flow，会卡住）

## When to Apply

- 创建 Release、上传 DMG、更新仓库 description/topics 之前

## Examples

```bash
source ~/.zshrc
gh release create v1.5.3 --title "v1.5.3" --notes-file BODY.md
# 或
curl -X PATCH https://api.github.com/repos/zdx52/AIUsageMonitor \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -d '{"description":"..."}'
```

## Related

- [git-push-release-workflow.md](../workflow/git-push-release-workflow.md)
