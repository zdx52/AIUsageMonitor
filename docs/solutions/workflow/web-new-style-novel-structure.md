---
title: Web 前端兼容新开书结构（设定/大纲/追踪 目录）
date: 2026-08-15
category: workflow
module: web/app.py
problem_type: architecture_pattern
severity: medium
applies_when:
  - 用 novel-bootstrapping 开书流程新建小说（设定/大纲/追踪 目录结构）后在 web 端看不到设定/人物/大纲
  - 新书没有 world.md/characters.md/outline.md 等平铺文件，网页显示"尚未创建世界观"
tags: [web-ui, novel-pipeline, novel-bootstrapping, 新结构, fallback]
---

# Web 前端兼容新开书结构（设定/大纲/追踪 目录）

## Context

novel-bootstrapping 开书流程（2026-08-11 定案）产出的新书目录结构：

```
八零绣娘：一针下去，全村跪了/
├── 设定/          ← 题材定位.md、关系.md、角色/姜绣.md、世界观/背景设定.md
├── 大纲/          ← 大纲.md、卷纲_第一卷.md、细纲_第001章.md...
└── 追踪/          ← 伏笔.md、角色状态.md、上下文.md
```

而 web 前端（AIUsageMonitor/web/app.py）只认老结构平铺文件（world.md /
characters.md / outline.md / seed.txt / voice.md / 连载追踪.md / chapters/）。
新书在网页上所有设定页都显示"尚未创建"，内容其实都在，只是 web 找不到。

## Guidance

在 `web/app.py` 加 **新结构 fallback 层**（老结构优先，找不到再 fallback），
集中在新加的几个函数里：

| web 需要的 | fallback 来源 | 函数 |
|---|---|---|
| world.md | `设定/世界观/*.md` | `_find_project_files()` 内建 mapping |
| 连载追踪.md | `追踪/*.md`（多文件合并，标题带文件名前缀） | `get_tracking_sections()` 循环合并 |
| characters.md | `设定/角色/*.md`（每文件一个人物卡，`# 主角人物卡：姜绣` 头部） | `parse_new_style_characters()` |
| seed.txt | `大纲/大纲.md` 的 `## 一句话总纲` / `设定/题材定位.md` 的 `## 一句话卖点` | `get_new_style_seed()` |
| outline.md | `大纲/` 目录合成（大纲.md + 卷纲_*.md + 细纲_*.md → 老格式文本） | `get_outline_sources()` |
| 卷概览 | 大纲卷信息派生（章节进度估算状态） | `get_volume_info()` 内建 fallback |
| 设置页书名 | `大纲/大纲.md` 第一行 `# 《书名》全书大纲` | novel_settings 路由 |
| 设置页类型/基调 | `设定/题材定位.md`、`设定/世界观/背景设定.md`、`追踪/上下文.md` 关键词 | novel_settings 路由 |

关键转换规则（`get_outline_sources()`）：

- `### 卷一《锈针》（第1-40章）` → `## 第一卷《锈针》（第1-40章）`（卷标题）
- `# 第1章：锈针` → `#### 第1章：锈针`（章节条目）
- `## 卷功能\n内容` → `**卷功能**：内容`（卷描述，取小节第一行）
- 细纲文件其余内容原样保留，parse_outline() 能直接吃

调用点统一改用新入口：`parse_all_outlines()` / `extract_parent_volume_defs()` /
总览页路由全部改走 `get_outline_sources()`；`novel_characters` /
`novel_character_detail` 空结果时 fallback `parse_new_style_characters()`。

⚠️ **老项目（七零年代）不受影响**：老结构文件存在时 fallback 不触发，
回归验证过全部页面 200。

## Why This Matters

novel-bootstrapping 是定案的开书流程，以后每本新书都是 设定/大纲/追踪 结构。
web 端不兼容 → 每次开新书都"看不到"，重复踩坑。加 fallback 层一次解决，
新书自动显示，老书行为不变。

## When to Apply

- 任何新书用 novel-bootstrapping 开书后，web 端应自动显示设定/人物/大纲
- 新增 web 数据源时沿用"老结构优先 + 新结构 fallback"模式

## Examples

验证命令（curl + grep）：

```bash
SLUG="%E5%85%AB%E9%9B%B6%E7%BB%A3%E5%A8%98%EF%BC%9A%E4%B8%80%E9%92%88%E4%B8%8B%E5%8E%BB%EF%BC%8C%E5%85%A8%E6%9D%91%E8%B7%AA%E4%BA%86"
curl -s "http://localhost:8080/novels/$SLUG/world" | grep -o "时代背景\|地理\|尚未创建世界观"
curl -s "http://localhost:8080/novels/$SLUG/characters" | grep -o "姜绣"
curl -s "http://localhost:8080/novels/$SLUG/outline" | grep -o "第一卷《锈针》\|第1章"
```

## Prevention

- 改 web 数据解析时先想"新书结构有没有这个文件"——用 `get_outline_sources()`
  等统一入口，不直接 `(project_path / "xxx.md").exists()` 硬判断
- 开新书后立刻在 web 端抽查世界观/人物/大纲三页，确认 fallback 生效
