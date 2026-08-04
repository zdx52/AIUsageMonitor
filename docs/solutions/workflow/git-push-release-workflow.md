---
title: Git 推送三件套与 Release 三件套的顺序
date: 2026-08-05
category: workflow
module: 发布流程
problem_type: workflow_issue
severity: high
applies_when:
  - 向 GitHub 推送新版本代码时
  - 需要发布新 Release 版本时
tags: [git, release, github, workflow]
---

# Git 推送三件套与 Release 三件套的顺序

## Context

本项目（AIUsageMonitor）的发布流程踩过"只 push 代码没发 Release"的坑（2026-07-27 教训），
也踩过"推送时漏更新 README/About"的坑。后来总结出两条固定流程，顺序不能乱。

## Guidance

**推送代码（每次必须按序完成）：**

1. **更新 README.md / README_CN.md** — 保留完整项目说明，只把更新日志缩减为最新版本（README 纯英文 + README_CN 纯中文）
2. **更新 GitHub About** — 通过 GitHub API 设置仓库 description 和 topics
3. **git commit + push**（SSH 协议：`git@github.com:zdx52/AIUsageMonitor.git`）

**发布版本（仅当需要发布时，在推送后做）：**

1. `source ~/.zshrc`（加载 GITHUB_TOKEN）
2. `gh release create vX.Y.Z --title "..."` 创建 Release
3. 上传 DMG 到 Release
4. **Release body 双语**：先英文一遍，`---` 分隔，再中文一遍，写完后显式检查是否双语齐全

## Why This Matters

- Git push ≠ Release。用户（大胖紫）明确纠正过：推了代码但没发 Release 等于没完成发布。
- About 不更新会导致仓库描述/话题过时，README 不更新则变更日志失准。
- Release body 漏中文会导致中文用户看不到更新说明。

## When to Apply

- 任何一次 `git push` 前
- 任何一次打 tag / 发版本前

## Examples

正确顺序（v1.5.x 发布）：

```bash
# 1. 改版本号 + 更新 README（英文+中文）
# 2. 更新 GitHub About
curl -X PATCH https://api.github.com/repos/zdx52/AIUsageMonitor \
  -H "Authorization: token $GITHUB_TOKEN" \
  -d '{"description": "...", "topics": ["..."]}'
# 3. 推送
git add -A && git commit -m "v1.5.3: ..." && git push
# 4. Release（双语 body）
gh release create v1.5.3 --title "v1.5.3" --notes "$(cat BODY.md)"
```

## Related

- [app-bundle-deploy.md](../deployment/app-bundle-deploy.md) — 部署到 .app 的配套流程
- [github-auth-token.md](../tooling/github-auth-token.md) — GITHUB_TOKEN 来源
