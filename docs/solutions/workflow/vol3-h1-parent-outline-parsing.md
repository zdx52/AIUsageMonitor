# 卷3「H1 父卷标注文件」解析修复（2026-09-02）

## 症状

《七零年代》新增卷3（outline.md H1 `# 第三部（第81-120章）· 卷3《路是走出来的》` + `outline_ch81_120.md` 细纲，章条目挂在 `# 单元N 细纲` H1 下，**没有** `## 卷3…(81-120)` 或 `## 81-90` 这类范围块），看板显示不准确：

1. 故事架构页：卷3 卡片存在但点开是**空 body**（无章节）
2. 章节列表页：ch81-95（已写的 15 章）掉进「未分类」
3. 总览页「各卷概览」：只有卷1/卷2 两张卡，卷3 不出现

## 根因

`parse_outline()` 只按 `##` 标题切卷块。`outline_ch81_120.md` 的章节条目
`### 第81章…` 位于 `# 单元N 细纲` H1 之下、且全文件没有任何 `##` 范围标题，
导致 81-120 章从未进入解析树。而 `extract_parent_volume_defs()` 已能从 H1
读出父卷定义 `卷3《路是走出来的》= 81-120`，于是出现「父卷卡片存在但体内无章节」的空壳。

旧文件（卷2 的 outline_ch41_80.md）有 `## 卷2 单元1-2（41-60）` 这类范围块，
所以旧卷不受影响——卷3 的新格式是新坑：**父卷 H1 标注 + 全 H1 单元细纲文件**。

## 修复（web/app.py + web/templates/outline.html）

1. `parse_outline()` vol_pattern 升级为 `^#{1,2}`（H1/H2 都认），并加第三分支
   `第X部（第A-B章）` 标注标题 → H1 父卷标注行也成为一个卷块起点，其文件尾部的
   `### 第XX章` 细纲被收进该卷块。
2. `display_name` 归一：H1 如 `# 第三部（第81-120章）细纲 — 卷3《路是走出来的》`
   解析后取 `卷3《路是走出来的》`（去掉「第X部…—」前缀），保证与 `extract_parent_volume_defs`
   的父卷名一致 → 合并/分组能对上。
3. `group_volumes_by_parent()` 改为两遍：第一遍把严格子范围卷挂为 subvolumes；
   第二遍处理**同 range 平级卷**（父卷 H1 自己产生的 flat vol，如卷3）——
   父卷还没有 subvolumes 时才把章节/描述上提到父卷自身（卷3 场景），已有子卷则丢弃
   平级壳（否则卷2 会 double 显示 41-80）。
4. parent 构造时预置 `chapters/descriptions` 空键，模板/测试不再 KeyError。
5. `parse_all_outlines()` rebuilt 阶段按 num 去重（占位章让位于有 details 的真章），
   修掉 41-80 被 H1 平级卷占位章重复收集成 160 章的问题 → 120 章唯一。
6. outline.html 父卷 body 内渲染父卷自身 chapters/descriptions（原来只渲染 subvolumes）。
7. `novel_chapters` 路由 vol_map 增加父卷自身 chapters 映射（卷3 无 subvolumes 时）。
8. `get_volume_info()` 父卷章节数 = subvolumes + 自身 chapters → 总览页出现卷3 卡。

## 顺手修复

ch_66-70.md 文件头有 UTF-8 BOM，导致故事架构页标题显示
`第六十六章  ﻿# 第六十六章  何永发`（第一行 `\ufeff#` 被当标题内容）。
已把 5 个文件 BOM 剥掉，标题正常。这是源文件 artifacts，不是解析器问题。

## 预防

- 新卷开书，若细纲文件**没有** `## 第A-B章` 范围块，H1 必须带 `（第A-B章）` 范围，
  web 端已能识别；若两种格式混排（范围块 + H1 标注都出现），父卷仍以子卷范围显示，
  H1 平级壳会被丢弃，不会 double。
- 章节标题含重复 `# 第六十六章` 字样 = BOM 或其他前缀污染源文件第一行，检查 `xxd | head -1`。
- 改动解析后跑 `web/.venv/bin/python web/test_vol3_parse.py`（卷1/2/3 树结构回归断言）。
