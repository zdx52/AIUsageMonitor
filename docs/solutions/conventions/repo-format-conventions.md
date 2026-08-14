---
title: 仓库文档格式约定（README/About/目录命名）
date: 2026-08-05
category: conventions
module: 仓库维护
problem_type: convention
severity: medium
applies_when:
  - 新建或修改 README.md / README_CN.md
  - 修改 GitHub 仓库 About（description/topics）
  - 新增文件或目录
tags: [readme, github, conventions, naming]
---

# 仓库文档格式约定（README/About/目录命名）

## Context

用户（大胖紫）对仓库格式有明确约定，曾因文件里混入中文或目录命名不规范被纠正。
这些约定对所有 GitHub 仓库通用，不是本项目独有。

## Guidance

- **README.md = 纯英文**，顶部链到 `README_CN.md`（如 `<a href="README_CN.md">📖 中文版</a>`）
- **README_CN.md = 纯中文**
- **GitHub About**（description + topics）= 纯英文
- **所有文件/目录名用英文**（README_CN.md 是唯一含中文的文件，文件名本身仍用英文）
- 中文内容只出现在 README_CN.md 内部，不散落到其他文件
- **Changelog 语言随文件走**：README.md 的更新日志必须用英文写，不能照搬 README_CN.md 的中文条目（2026-08-14 教训：v1.6.0 changelog 误用中文被用户纠正）。UI 按钮名/目录名等专名引用（如「小说」按钮、封面/ 目录）可保留原文

## Why This Matters

- 混用中英文会让国际读者困惑，About 纯中文会导致搜索/展示异常
- 命名规范统一后，脚本、CI、链接都不会因编码/路径问题出错

## When to Apply

- 每次改 README 或仓库元信息时对照检查

## Examples

```markdown
<!-- README.md（英文）顶部 -->
# AIUsageMonitor

<p align="center">
  <a href="README_CN.md">📖 中文版</a>
</p>
```

## Related

- [git-push-release-workflow.md](../workflow/git-push-release-workflow.md) — 推送前要更新 README
