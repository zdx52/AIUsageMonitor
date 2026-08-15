#!/usr/bin/env python3
"""
autonovel-cn Web UI v2
结构化展示小说信息：世界观、人物、故事架构、风格设置。
"""
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import markdown
from dotenv import load_dotenv
from flask import Flask, jsonify, redirect, render_template, request, send_file, url_for

# ── Paths ──────────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent.parent
ENV_PATH = BASE_DIR / ".env"

# Load novels path from .env, default to ../novels
def _get_novels_dir():
    """Get novels directory from .env or default."""
    default = BASE_DIR.parent / "novels"
    env_path = BASE_DIR / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("NOVELS_PATH="):
                custom = line.split("=", 1)[1].strip()
                if custom:
                    custom_path = Path(custom).expanduser().resolve()
                    if custom_path.exists():
                        return custom_path
    return default

NOVELS_DIR = _get_novels_dir()

# ── Reuse quality-check scripts (scripts/) ─────────────
SCRIPTS_DIR = BASE_DIR / "web" / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))
try:
    from check_fanqie_quality import check_chapter, BANNED
    from check_duplicate_text import load_paras, adjacent_dups, distant_dups
    from scan_cast import extract_cast
    from check_continuity import YEAR_RE, cn2int
    HAS_QUALITY_SCRIPTS = True
except Exception:
    HAS_QUALITY_SCRIPTS = False

# ── Flask ──────────────────────────────────────────────
app = Flask(__name__)

# ── Novel Config (novel.json) ──────────────────────────

# 封面文件优先级（novels/<slug>/封面/ 目录下）
COVER_PRIORITY = [
    "cover_v3_compressed.jpg", "cover_v3.png", "cover_base.png",
    "cover.png", "cover.jpg", "封面.png", "封面.jpg",
]


def find_cover(project_path):
    """查找小说封面文件，返回文件名或 None。"""
    cover_dir = project_path / "封面"
    if not cover_dir.exists():
        return None
    for name in COVER_PRIORITY:
        p = cover_dir / name
        if p.exists():
            return name
    for p in sorted(cover_dir.glob("*.jpg")) + sorted(cover_dir.glob("*.png")):
        return p.name
    return None

DEFAULT_NOVEL_CONFIG = {
    "title": "",
    "author": "大胖紫",
    "genre": "",
    "tone": "",
    "status": "构思中",
    "target_chapters": 200,
    "target_words_per_chapter": 2800,
    "one_liner": "",
    "platform": "",
    "tags": [],
}


def get_novel_config(project_path):
    """Read novel.json config."""
    config_path = project_path / "novel.json"
    if config_path.exists():
        try:
            data = json.loads(config_path.read_text())
            return {**DEFAULT_NOVEL_CONFIG, **data}
        except Exception:
            pass
    return dict(DEFAULT_NOVEL_CONFIG)


def save_novel_config(project_path, config):
    """Save novel.json config."""
    config_path = project_path / "novel.json"
    config_path.write_text(json.dumps(config, indent=2, ensure_ascii=False), encoding="utf-8")


# ── Novels Index ───────────────────────────────────────

def get_novels():
    """Scan novels/ directory with stats, respecting saved order."""
    if not NOVELS_DIR.exists():
        return []

    # Load saved order
    order_path = BASE_DIR / "web" / ".novel_order.json"
    saved_order = []
    if order_path.exists():
        try:
            saved_order = json.loads(order_path.read_text())
        except Exception:
            saved_order = []

    # Build novel list with saved order
    novel_map = {}
    for entry in sorted(NOVELS_DIR.iterdir()):
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        config = get_novel_config(entry)
        volumes = []
        chapters_total = 0
        chars_total = 0
        for sub in sorted(entry.iterdir()):
            if sub.is_dir() and "卷" in sub.name:
                ch_dir = sub / "chapters"
                if ch_dir.exists():
                    chs = sorted(ch_dir.glob("ch_*.md"))
                    vc = sum(1 for ch in chs for c in ch.read_text(encoding="utf-8") if "\u4e00" <= c <= "\u9fff")
                    volumes.append({"name": sub.name, "chapters": len(chs), "chars": vc})
                    chapters_total += len(chs)
                    chars_total += vc
                vconfig = get_novel_config(sub)
                if vconfig["title"]:
                    volumes[-1]["title"] = vconfig["title"]
        ch_dir = entry / "chapters"
        if ch_dir.exists() and not volumes:
            chs = sorted(ch_dir.glob("ch_*.md"))
            chapters_total = len(chs)
            chars_total = sum(1 for ch in chs for c in ch.read_text(encoding="utf-8") if "\u4e00" <= c <= "\u9fff")
        novel_map[entry.name] = {
            "name": entry.name,
            "config": config,
            "volumes": volumes,
            "chapters": chapters_total,
            "chars": chars_total,
            "cover": find_cover(entry),
            "progress_pct": min(int(chapters_total / max(config.get("target_chapters", 200), 1) * 100), 100) if chapters_total > 0 else 0,
            "latest_chapter": "",
        }
        # Get latest chapter title
        if chapters_total > 0:
            ch_dir = entry / "chapters"
            if not ch_dir.exists() and volumes:
                # Find last volume with chapters
                for v in reversed(volumes):
                    vd = entry / v["name"]
                    if (vd / "chapters").exists():
                        ch_dir = vd / "chapters"
                        break
            if ch_dir and ch_dir.exists():
                ch_files = sorted(ch_dir.glob("ch_*.md"))
                if ch_files:
                    try:
                        first_line = ch_files[-1].read_text(encoding="utf-8").strip().split("\n")[0]
                        novel_map[entry.name]["latest_chapter"] = first_line.lstrip("# ").strip()
                    except Exception:
                        pass
        if entry.name not in saved_order:
            saved_order.append(entry.name)

    # Order by saved_order, then add any new ones at end
    ordered = []
    seen = set()
    for name in saved_order:
        if name in novel_map:
            ordered.append(novel_map[name])
            seen.add(name)
    for name, novel in sorted(novel_map.items()):
        if name not in seen:
            ordered.append(novel)
            seen.add(name)

    return ordered


# ── Routes ──────────────────────────────────────────────

@ app.route("/")
def index():
    novels = get_novels()
    return render_template("index.html", novels=novels)


@ app.route("/api/novels/reorder", methods=["POST"])
def api_novels_reorder():
    """Save novel order from drag-and-drop."""
    try:
        data = request.get_json()
        order = data.get("order", [])
        order_path = BASE_DIR / "web" / ".novel_order.json"
        order_path.write_text(json.dumps(order, ensure_ascii=False, indent=2))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/covers/<slug>")
def novel_cover(slug):
    """Serve novel cover image from 封面/ directory."""
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "", 404
    name = find_cover(project_path)
    if not name:
        return "", 404
    return send_file(project_path / "封面" / name)


def parse_world(text):
    """Parse world.md into sections."""
    sections = {}
    current_section = "概述"
    lines = []
    has_content = False
    for line in text.split("\n"):
        if line.startswith("## "):
            if lines and (has_content or any(l.strip() for l in lines)):
                sections[current_section] = "\n".join(lines).strip()
            current_section = line.lstrip("# ").strip()
            lines = []
            has_content = False
        elif line.startswith("# "):
            continue
        else:
            lines.append(line)
            if line.strip():
                has_content = True
    if lines and has_content:
        sections[current_section] = "\n".join(lines).strip()
    return sections


def parse_characters(text):
    """Parse characters.md into a list of character dicts.

    Supports two formats:
    - Legacy: `## 女主：林小满` (each ## heading = one character)
    - Grouped (new-style books): `## 主角（核心人物）` + `### 姜绣`
      (## = role group, ### = one character card; groups without any
      ### child like 角色说话方式速查 are skipped)
    """
    lines = text.split("\n")
    if any(line.startswith("### ") for line in lines):
        return _parse_grouped_characters(lines)

    characters = []
    current = None
    current_lines = []
    for line in lines:
        if line.startswith("## "):
            if current:
                current["text"] = "\n".join(current_lines).strip()
                characters.append(current)
            heading = line.lstrip("# ").strip()
            # Detect role from heading: 女主/男主/女配/男配/主角/配角
            name, role = heading, "配角"
            for prefix, r in [("女主", "主角"), ("男主", "主角"), ("女配", "配角"), ("男配", "配角")]:
                if prefix in heading:
                    role = r
                    name = heading.replace(prefix, "").lstrip("：:").strip()
                    break
            current = {"name": name, "role": role, "heading": heading, "text": ""}
            current_lines = []
        elif current:
            current_lines.append(line)
            # Try to extract role from first few lines (fallback)
            lower = line.lower()
            if not current.get("role_from_content") and ("role" in lower or "角色" in lower):
                for sep in [":", "："]:
                    if sep in line:
                        val = line.split(sep, 1)[1].strip().lower()
                        # 精确判断主角，避免 "主要配角"/"主角团" 等含 "主" 的值误判
                        if "main" in val or "lead" in val or ("主角" in val and "配角" not in val):
                            current["role"] = "主角"
                        current["role_from_content"] = True
                        break
    if current:
        current["text"] = "\n".join(current_lines).strip()
        characters.append(current)
    return characters


def _parse_grouped_characters(lines):
    """Parse grouped format: `## 主角（核心人物）` group + `### 姜绣` character cards."""
    characters = []
    current = None
    current_lines = []
    group_role = "配角"
    for line in lines:
        if line.startswith("## "):
            if current:
                current["text"] = "\n".join(current_lines).strip()
                characters.append(current)
            heading = line.lstrip("# ").strip()
            group_role = "主角" if "主角" in heading and "配角" not in heading else "配角"
            current = None
            current_lines = []
        elif line.startswith("### "):
            if current:
                current["text"] = "\n".join(current_lines).strip()
                characters.append(current)
            name = line.lstrip("# ").strip()
            current = {"name": name, "role": group_role, "heading": name, "text": ""}
            current_lines = []
        elif current:
            current_lines.append(line)
    if current:
        current["text"] = "\n".join(current_lines).strip()
        characters.append(current)
    return characters


def parse_outline(text):
    """Parse outline.md into structured volumes with chapters and details."""
    # Split into volume blocks by ## 第X卷 / ## 卷N / ## 卷N 上/下 / ## 第X-Y章 headings
    vol_pattern = re.compile(r'^##\s*(?:第[一二三四五六七八九十]+卷|卷\d+(?:[上中下])?[《·（( ]|第\d+\s*[-–—~至]\s*\d+\s*章)', re.MULTILINE)
    splits = list(vol_pattern.finditer(text))
    
    volumes = []
    all_chapters = []
    
    for idx, m in enumerate(splits):
        start = m.start()
        end = splits[idx + 1].start() if idx + 1 < len(splits) else len(text)
        block = text[start:end].strip()
        
        lines = block.split('\n')
        title = lines[0].lstrip('# ').strip()
        
        # Extract chapter range from title: （第1-35章）/ 卷2 上（41-60 · 洋尺子）/ 卷2 上·洋尺子（41-60）
        range_m = re.search(r'第(\d+)[-–—~至](\d+)章|[（(](\d+)[-–—~至](\d+)', title)
        if range_m:
            if range_m.group(1):
                ch_start, ch_end = int(range_m.group(1)), int(range_m.group(2))
            else:
                ch_start, ch_end = int(range_m.group(3)), int(range_m.group(4))
        else:
            ch_start, ch_end = 1, 0
        
        # Volume display name: strip all parenthesized content + 卷纲 suffix
        display_name = re.sub(r'[（(][^）)]*[)）]', '', title).strip()
        display_name = re.sub(r'\s*卷纲\s*', '', display_name).strip()
        display_name = display_name or title
        
        # Extract volume-level descriptions (**key**: value)
        descriptions = {}
        for line in lines:
            m2 = re.match(r'\*\*([^*]+)\*\*[：:]?\s*(.*)', line)
            if m2:
                key = m2.group(1).strip()
                val = m2.group(2).strip()
                descriptions[key] = val
        
        # Extract per-chapter entries: ###/#### 第X章 (detailed outline only, not - list items)
        chapters = []
        ch_pattern = re.compile(r'^#{3,4}\s*第(\d+)章[：:]?\s*(.+?)(?:\n|$)', re.MULTILINE)
        for cm in ch_pattern.finditer(block):
            ch_num = int(cm.group(1))
            ch_title_raw = cm.group(2).strip().rstrip('》').strip()
            
            # Extract chapter details from following lines until next #### or end
            ch_start_pos = cm.end()
            ch_end_pos = len(block)
            next_ch = ch_pattern.search(block, ch_start_pos)
            if next_ch:
                ch_end_pos = next_ch.start()
            ch_block = block[ch_start_pos:ch_end_pos].strip()
            
            ch_details = {}
            for line in ch_block.split('\n'):
                stripped_line = line.strip().lstrip("- ").strip()
                for sep in [":", "："]:
                    if sep in stripped_line:
                        key, val = stripped_line.split(sep, 1)
                        key = key.strip().strip('*').strip()
                        if key:
                            ch_details[key] = val.strip()
                        break
            
            chapters.append({
                "num": ch_num,
                "title": ch_title_raw,
                "details": ch_details,
            })
        
        # Fill all_chapters from range or detailed entries
        if range_m:
            for n in range(ch_start, ch_end + 1):
                # Find matching detailed entry, or use generic
                detail = next((c for c in chapters if c["num"] == n), None)
                if detail:
                    all_chapters.append({"num": n, "title": detail["title"], "act": title, "summary": ""})
                else:
                    all_chapters.append({"num": n, "title": f"第{n}章", "act": title, "summary": ""})
        else:
            for ch in chapters:
                all_chapters.append({"num": ch["num"], "title": ch["title"], "act": title, "summary": ""})
        
        volumes.append({
            "name": display_name,
            "range": (ch_start, ch_end) if range_m else None,
            "descriptions": descriptions,
            "chapters": chapters,
        })
    
    # Fill vol chapters with full range if missing generic entries
    for vol in volumes:
        if vol["range"] and len(vol["chapters"]) < vol["range"][1] - vol["range"][0] + 1:
            existing_nums = {c["num"] for c in vol["chapters"]}
            for n in range(vol["range"][0], vol["range"][1] + 1):
                if n not in existing_nums:
                    vol["chapters"].append({"num": n, "title": f"第{n}章", "details": {}})
            vol["chapters"].sort(key=lambda c: c["num"])
    
    # Enrich chapter titles from chapter files
    return volumes, all_chapters


def get_outline_files(project_path):
    """Return all outline files (outline.md + outline_ch*.md), sorted by range.

    Generic: 续写新章时新建 outline_ch81_120.md 等文件会自动被读取。
    """
    files = []
    root = project_path / "outline.md"
    if root.exists():
        files.append(root)
    for f in sorted(project_path.glob("outline_ch*.md")):
        files.append(f)
    return files


def extract_parent_volume_defs(project_path):
    """Extract parent-volume definitions from H1 annotations in outline files.

    Supported annotations (in `# ` H1 lines):
      # 第二部（第41-80章）· 卷2《活过三十岁》（卷1《杀穿红星厂》= 第1-40章，已完成）
    → 卷1《杀穿红星厂》= 第1-40章, 卷2《活过三十岁》= 第41-80章

    Returns {vol_num: {"name": "卷1《杀穿红星厂》", "range": (1, 40)}, ...}
    """
    defs = {}
    for name, text in get_outline_sources(project_path):
        for line in text.splitlines():
            if not line.startswith("# "):
                continue
            # Explicit: 卷N《名》= 第A-B章
            for m in re.finditer(r'卷(\d+)《([^》]+)》\s*=\s*第?(\d+)[-–—~至](\d+)章?', line):
                num = int(m.group(1))
                defs[num] = {
                    "name": f"卷{num}《{m.group(2)}》",
                    "range": (int(m.group(3)), int(m.group(4))),
                }
            # Implicit: X部（第A-B章）· 卷N《名》
            part_m = re.search(r'第[一二三四五六七八九十]+部（第?(\d+)[-–—~至](\d+)章?）', line)
            for m in re.finditer(r'卷(\d+)《([^》]+)》', line):
                num = int(m.group(1))
                if num not in defs and part_m:
                    defs[num] = {
                        "name": f"卷{num}《{m.group(2)}》",
                        "range": (int(part_m.group(1)), int(part_m.group(2))),
                    }
    return defs


def group_volumes_by_parent(volumes, parent_defs):
    """Group flat volumes under parent volumes by chapter range.

    Volumes whose range falls inside a parent's range become subvolumes.
    Unmatched volumes stay flat. Returns list of parent dicts + unmatched volumes.
    """
    if not parent_defs:
        return volumes
    parents = []
    for num in sorted(parent_defs):
        p = parent_defs[num]
        parents.append({
            "name": p["name"],
            "range": p["range"],
            "subvolumes": [],
            "is_parent": True,
        })
    remaining = []
    for v in volumes:
        placed = False
        if v.get("range"):
            lo, hi = v["range"]
            for p in parents:
                plo, phi = p["range"]
                if plo <= lo and hi <= phi:
                    p["subvolumes"].append(v)
                    placed = True
                    break
        if not placed:
            remaining.append(v)
    return parents + remaining


def parse_all_outlines(project_path):
    """Parse all outline files and merge same-named volumes (e.g. 卷1 in outline.md + outline_ch41_80.md).

    Returns (volumes, all_chapters) merged by volume display name, chapters sorted by num.
    If parent-volume annotations exist (卷N《名》= 第A-B章), volumes are grouped two-level.
    """
    volumes, all_chapters = [], []
    seen_vols = {}
    for name, text in get_outline_sources(project_path):
        vols, chs = parse_outline(text)
        all_chapters.extend(chs)
        for vol in vols:
            # Merge key: chapter range if present, else display name.
            # Same range with different names (卷2 上·洋尺子 vs 卷2 上) merge together.
            key = ("range", vol["range"]) if vol.get("range") else ("name", vol["name"])
            if key in seen_vols:
                existing = seen_vols[key]
                # Prefer the more complete name (containing · 标题 or 《》)
                if "·" in vol["name"] and "·" not in existing["name"]:
                    existing["name"] = vol["name"]
                elif "《" in vol["name"] and "《" not in existing["name"]:
                    existing["name"] = vol["name"]
                # Merge descriptions (new file wins on conflict)
                existing["descriptions"].update(vol["descriptions"])
                # Merge chapters by num (new file wins on conflict)
                by_num = {c["num"]: c for c in existing["chapters"]}
                for c in vol["chapters"]:
                    by_num[c["num"]] = c
                existing["chapters"] = sorted(by_num.values(), key=lambda c: c["num"])
            else:
                seen_vols[key] = vol
                volumes.append(vol)

    # Dedup all_chapters by num (keep the one with a real title)
    ch_by_num = {}
    for c in all_chapters:
        if c["num"] not in ch_by_num or (c["title"] != f"第{c['num']}章" and c["title"] != c["num"]):
            ch_by_num[c["num"]] = c
    all_chapters = [ch_by_num[n] for n in sorted(ch_by_num)]

    # Re-assign chapters to volumes by num (handles `# 单元N 细纲` H1 blocks that
    # would otherwise dump chapters into the wrong volume by text order)
    vol_by_num = {}
    for v in volumes:
        if v["range"]:
            lo, hi = v["range"]
            for n in range(lo, hi + 1):
                vol_by_num[n] = v

    if vol_by_num:
        collected = []
        for v in volumes:
            collected.extend(v["chapters"])
            v["chapters"] = []

        def ch_quality(c):
            """Higher = more real content. Placeholder = 1, real title/details = 2."""
            if c.get("details"):
                return 2
            title = c.get("title", "")
            if title and title != f"第{c['num']}章" and str(title) != str(c["num"]):
                return 2
            return 1

        for c in collected:
            target = vol_by_num.get(c["num"], None)
            if target is None:
                # fall back: first volume whose range starts at or before this num
                for v in volumes:
                    if v["range"] and c["num"] >= v["range"][0]:
                        target = v
            if target is None:
                target = volumes[0] if volumes else None
            if target is None:
                continue
            existing = next((x for x in target["chapters"] if x["num"] == c["num"]), None)
            if existing is None:
                target["chapters"].append(c)
            elif ch_quality(c) > ch_quality(existing):
                target["chapters"].remove(existing)
                target["chapters"].append(c)
        for v in volumes:
            v["chapters"].sort(key=lambda c: c["num"])

    # Fill missing chapters in ranged volumes (generic placeholders)
    for v in volumes:
        if v["range"] and len(v["chapters"]) < v["range"][1] - v["range"][0] + 1:
            existing_nums = {c["num"] for c in v["chapters"]}
            for n in range(v["range"][0], v["range"][1] + 1):
                if n not in existing_nums:
                    v["chapters"].append({"num": n, "title": f"第{n}章", "details": {}})
            v["chapters"].sort(key=lambda c: c["num"])

    # Rebuild all_chapters from the final, correctly-assigned volumes (handles
    # chapters that fell into a later volume block by text order, e.g. `# 单元N 细纲`)
    rebuilt = []
    for v in volumes:
        for c in v["chapters"]:
            rebuilt.append({
                "num": c["num"],
                "title": c.get("title", f"第{c['num']}章"),
                "act": v["name"],
                "summary": "",
                "details": c.get("details", {}),
            })
    all_chapters = sorted(rebuilt, key=lambda c: c["num"])

    # Group volumes under parent volumes (卷1《杀穿红星厂》= 第1-40章 annotations)
    parent_defs = extract_parent_volume_defs(project_path)
    if parent_defs:
        volumes = group_volumes_by_parent(volumes, parent_defs)

    return volumes, all_chapters


def parse_voice(text):
    """Parse voice.md — extract style parameters if structured."""
    params = {}
    sections = {}
    current_section = "概述"
    lines = []
    has_content = False
    for line in text.split("\n"):
        if line.startswith("## "):
            if lines and has_content:
                sections[current_section] = "\n".join(lines).strip()
            current_section = line.lstrip("# ").strip()
            lines = []
            has_content = False
        elif line.startswith("# "):
            continue
        else:
            lines.append(line)
            if line.strip():
                has_content = True
    if lines and has_content:
        sections[current_section] = "\n".join(lines).strip()
    return sections


def parse_markdown_tables(text):
    """Parse markdown file into sections with tables and bullet lists.

    Returns list of:
      {"title": "一、角色状态表", "tables": [{"subtitle": "", "headers": [...], "rows": [[...]]}],
       "lists": [...], "notes": [...]}
    """
    sections = []
    current = None
    cur_table = None

    def flush_table():
        nonlocal cur_table
        if cur_table and current is not None:
            current["tables"].append(cur_table)
        cur_table = None

    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("## "):
            flush_table()
            current = {"title": line.lstrip("# ").strip(), "tables": [], "lists": [], "notes": []}
            sections.append(current)
        elif line.startswith("### ") and current is not None:
            flush_table()
            cur_table = {"subtitle": line.lstrip("# ").strip(), "headers": [], "rows": []}
        elif line.startswith("|") and current is not None:
            cells = [c.strip() for c in line.strip("|").split("|")]
            if cur_table is None:
                cur_table = {"subtitle": "", "headers": [], "rows": []}
            if not cur_table["headers"]:
                cur_table["headers"] = cells
            elif all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
                pass  # separator row
            else:
                cur_table["rows"].append(cells)
        elif line.startswith("- ") and current is not None:
            flush_table()
            current["lists"].append(line[2:].strip())
        elif line.startswith(">") and current is not None:
            flush_table()
            current["notes"].append(line.lstrip("> ").strip())
        else:
            flush_table()
    flush_table()
    return sections


def get_tracking_sections(project_path):
    """Load and parse 连载追踪.md from root or sub-volumes.

    New-style fallback: 追踪/ 目录下的多个文件（伏笔.md/角色状态.md/上下文.md）
    合并为多个 section，标题带文件名前缀区分。
    """
    sections = []
    found = False
    for vol_name, content in _find_project_files(project_path, "连载追踪.md"):
        parsed = parse_markdown_tables(content)
        for s in parsed:
            if vol_name:
                s["title"] = f"{vol_name} · {s['title']}"
            sections.append(s)
        found = True
    return sections, found


def parse_canon(text):
    """Parse canon.md (正典数据库) into structured sections.

    Format: `## section` headings, `### subsection` headings (e.g. 事件-第N章),
    `- bullet` lists, `> notes`, plain paragraphs. canon.md has no tables.
    Returns [{"title", "children": [{"subtitle", "lists", "notes", "paragraphs"}]}]
    where a section without subsections keeps its content in its own
    lists/notes/paragraphs (children empty).
    """
    sections = []
    current = None
    child = None

    def bucket():
        target = child if child is not None else current
        assert target is not None, "bucket() called without active section"
        return target

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("# "):
            continue
        if line.startswith("## "):
            current = {"title": line.lstrip("# ").strip(), "children": [],
                       "lists": [], "notes": [], "paragraphs": []}
            child = None
            sections.append(current)
        elif line.startswith("### "):
            if current is None:
                continue
            child = {"subtitle": line.lstrip("# ").strip(), "lists": [], "notes": [], "paragraphs": []}
            current["children"].append(child)
        elif current is None:
            continue
        elif line.startswith("- "):
            bucket()["lists"].append(line[2:].strip())
        elif line.startswith("> "):
            bucket()["notes"].append(line.lstrip("> ").strip())
        elif line.strip():
            bucket()["paragraphs"].append(line)
    return sections


def get_canon_sections(project_path):
    """Load and parse canon.md (正典数据库) from root or sub-volumes."""
    sections = []
    found = False
    for vol_name, content in _find_project_files(project_path, "canon.md"):
        for s in parse_canon(content):
            if vol_name:
                s["title"] = f"{vol_name} · {s['title']}"
            sections.append(s)
        found = True
    return sections, found


def _find_project_files(project_path, filename):
    """Search for a file in project root and sub-volumes. Returns list of (volume_name, content).

    Falls back to novel-bootstrapping new-style structure (设定/世界观, 追踪 dirs):
      world.md      → 设定/世界观/*.md
      连载追踪.md    → 追踪/*.md
    """
    results = []
    fp = project_path / filename
    if fp.exists():
        results.append(("", fp.read_text()))
    for sub in sorted(project_path.iterdir()):
        if sub.is_dir() and "卷" in sub.name:
            fp = sub / filename
            if fp.exists():
                results.append((sub.name, fp.read_text()))
    if results:
        return results
    # New-style fallback
    mapping = {
        "world.md": ("设定", "世界观"),
        "连载追踪.md": ("追踪", None),
    }
    if filename in mapping:
        subdir, subsub = mapping[filename]
        base = project_path / subdir
        if subsub:
            base = base / subsub
        if base.exists():
            for f in sorted(base.glob("*.md")):
                results.append((f.stem, f.read_text(encoding="utf-8")))
    return results


def parse_new_style_characters(project_path):
    """Parse new-style character cards: 设定/角色/*.md (each file = one character).

    File format: `# 主角人物卡：姜绣` heading, then ## 基本信息 etc.
    Returns list of {"name", "role", "heading", "text"} compatible with parse_characters.
    """
    d = project_path / "设定" / "角色"
    if not d.exists():
        return []
    characters = []
    for f in sorted(d.glob("*.md")):
        text = f.read_text(encoding="utf-8")
        heading = ""
        name, role = f.stem, "配角"
        for line in text.split("\n"):
            if line.startswith("# "):
                heading = line.lstrip("# ").strip()
                break
        if "主角" in heading:
            role = "主角"
            for sep in ["：", ":"]:
                if sep in heading:
                    cand = heading.split(sep, 1)[1].strip()
                    if cand:
                        name = cand
                    break
        characters.append({"name": name, "role": role, "heading": heading, "text": text})
    return characters


def get_new_style_seed(project_path):
    """Extract one-line pitch from new-style scaffolding as seed fallback.

    Sources: 大纲/大纲.md `## 一句话总纲`, then 设定/题材定位.md `## 一句话卖点`.
    """
    for fname, key in [("大纲/大纲.md", "一句话总纲"), ("设定/题材定位.md", "一句话卖点")]:
        p = project_path / fname
        if p.exists():
            text = p.read_text(encoding="utf-8")
            m = re.search(rf"##\s*{key}\s*\n\s*(.+)", text)
            if m:
                return m.group(1).strip()
    return ""


def get_outline_sources(project_path):
    """Return [(name, text)] for outline files.

    Legacy: outline.md + outline_ch*.md (unchanged).
    Fallback to new-style 大纲/ dir (大纲.md + 卷纲_*.md + 细纲_*.md), synthesized
    into legacy outline.md format so parse_outline() can consume it:
      `### 卷一《锈针》（第1-40章）` → `## 第一卷《锈针》（第1-40章）`
      `# 第N章：标题` → `#### 第N章：标题`
    """
    files = get_outline_files(project_path)
    if files:
        return [(f.name, f.read_text(encoding="utf-8")) for f in files]
    d = project_path / "大纲"
    if not d.exists():
        return []
    parts = []
    main = d / "大纲.md"
    if main.exists():
        lines = main.read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            m = re.match(r"^#{2,3}\s*卷([一二三四五六七八九十]+)《([^》]+)》[（(]第(\d+)-(\d+)章[）)]", line)
            if m:
                lines[i] = f"## 第{m.group(1)}卷《{m.group(2)}》（第{m.group(3)}-{m.group(4)}章）"
        parts.append("\n".join(lines))
    for vf in sorted(d.glob("卷纲_*.md")):
        text = vf.read_text(encoding="utf-8")
        lines = text.split("\n")
        for i, line in enumerate(lines):
            m = re.match(r"^##\s*([^#\n]+)$", line)
            if m:
                key = m.group(1).strip()
                if i + 1 < len(lines) and lines[i + 1].strip() and not lines[i + 1].startswith("#"):
                    lines[i] = f"**{key}**：{lines[i + 1].strip()}"
        parts.append("\n".join(lines))
    for cf in sorted(d.glob("细纲_*.md")):
        lines = cf.read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            m = re.match(r"^#\s*第(\d+)章[：:]\s*(.*)", line)
            if m:
                lines[i] = f"#### 第{m.group(1)}章：{m.group(2)}"
                break
        parts.append("\n".join(lines))
    return [("大纲(新结构)", "\n\n".join(parts))]


def get_chapter_stats(project_path):
    """Get per-chapter stats."""
    chapters = []
    ch_dir = project_path / "chapters"
    if ch_dir.exists():
        for ch in sorted(ch_dir.glob("ch_*.md")):
            text = ch.read_text(encoding="utf-8")
            chapters.append({
                "name": ch.stem,
                "chars": sum(1 for c in text if '\u4e00' <= c <= '\u9fff'),
                "words": len(text.split()),
                "volume": None,
                "path": str(ch),
            })
    for sub in sorted(project_path.iterdir()):
        if sub.is_dir() and "卷" in sub.name:
            vch_dir = sub / "chapters"
            if vch_dir.exists():
                for ch in sorted(vch_dir.glob("ch_*.md")):
                    text = ch.read_text(encoding="utf-8")
                    chapters.append({
                        "name": ch.stem,
                        "chars": sum(1 for c in text if '\u4e00' <= c <= '\u9fff'),
                        "words": len(text.split()),
                        "volume": sub.name,
                        "path": str(ch),
                    })
    return chapters


def get_volume_info(project_path):
    """Get sub-volume info.

    Legacy: 扫描「卷」子目录。New-style fallback: 从大纲（outline / 大纲/ 目录）
    解析卷名和章节范围，卷状态按章节进度估算。
    """
    volumes = []
    for sub in sorted(project_path.iterdir()):
        if sub.is_dir() and "卷" in sub.name:
            config = get_novel_config(sub)
            ch_dir = sub / "chapters"
            chs = sorted(ch_dir.glob("ch_*.md")) if ch_dir.exists() else []
            chars_total = sum(len(ch.read_text(encoding="utf-8")) for ch in chs)
            volumes.append({
                "name": sub.name,
                "title": config.get("title", ""),
                "chapters": len(chs),
                "chars": chars_total,
                "status": config.get("status", "构思中"),
            })
    if not volumes:
        # New-style: derive from outline volumes (大纲/目录 or outline.md)
        try:
            def _ch_num(name):
                m = re.search(r"(\d+)", name or "")
                return int(m.group(1)) if m else None

            outline_vols, _ = parse_all_outlines(project_path)
            chapters = get_chapter_stats(project_path)
            written = {_ch_num(c["name"]) for c in chapters}
            written.discard(None)
            for v in outline_vols:
                if v.get("is_parent"):
                    sub_total = sum(len(sub.get("chapters", [])) for sub in v.get("subvolumes", []))
                    sub_written = sum(1 for sub in v.get("subvolumes", []) for c in sub.get("chapters", []) if c["num"] in written)
                    total, cnt = sub_total, sub_written
                else:
                    total = v["range"][1] - v["range"][0] + 1 if v.get("range") else len(v.get("chapters", []))
                    cnt = sum(1 for c in v.get("chapters", []) if c["num"] in written)
                if total <= 0:
                    continue
                pct = cnt / total
                status = "已完成" if pct >= 1.0 else ("起草中" if pct > 0 else "构思中")
                name = re.sub(r"[（(].*[）)]", "", v["name"]).strip()
                vol_nums = {cc["num"] for cc in v.get("chapters", [])}
                volumes.append({
                    "name": name,
                    "title": "",
                    "chapters": cnt,
                    "chars": sum(c.get("chars", 0) for c in chapters if _ch_num(c["name"]) in vol_nums),
                    "status": status,
                })
        except Exception:
            pass
    return volumes



# ── Data Parsing ───────────────────────────────────────

def get_env_config():
    config = {}
    if ENV_PATH.exists():
        for line in ENV_PATH.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, val = line.partition("=")
                config[key.strip()] = val.strip()
    return config


def save_env_config(config):
    key_order = ["LLM_API_KEY", "LLM_BASE_URL", "LLM_WRITER_MODEL", "LLM_JUDGE_MODEL", "LLM_REVIEW_MODEL"]
    lines = []
    written = set()
    for key in key_order:
        if key in config:
            lines.append(f"{key}={config[key]}")
            written.add(key)
    for key, val in config.items():
        if key not in written:
            lines.append(f"{key}={val}")
    ENV_PATH.write_text("\n".join(lines) + "\n")


@app.route("/settings", methods=["GET", "POST"])
def settings():
    if request.method == "POST":
        config = {}
        for key in request.form:
            config[key] = request.form[key]
        save_env_config(config)
        return redirect(url_for("settings"))
    env = get_env_config()
    models = ["deepseek-v4-flash", "deepseek-v4-flash", "deepseek-v4-pro", "deepseek-v4-flash-pro", "qwen3.7-plus"]
    return render_template("settings.html", env=env, models=models, novels_dir=str(NOVELS_DIR))


# ── Novel Overview ─────────────────────────────────────

@app.route("/novels/<slug>")
def novel_overview(slug):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    config = get_novel_config(project_path)
    volumes = get_volume_info(project_path)
    chapters = get_chapter_stats(project_path)
    total_chars = sum(c["chars"] for c in chapters)
    total_chapters = len(chapters)

    # Parse content files
    world_text = ""
    world_sections = {}
    for vol_name, wtext in _find_project_files(project_path, "world.md"):
        world_text = wtext
        world_sections.update(parse_world(wtext))

    characters = []
    for vol_name, ctext in _find_project_files(project_path, "characters.md"):
        characters.extend(parse_characters(ctext))
    if not characters:
        characters = parse_new_style_characters(project_path)

    outline_chapters, outline_acts = [], []
    for name, otext in get_outline_sources(project_path):
        ch, ac = parse_outline(otext)
        outline_chapters.extend(ch)
        outline_acts.extend(ac)

    voice_sections = {}
    for vol_name, vtext in _find_project_files(project_path, "voice.md"):
        voice_sections.update(parse_voice(vtext))
    # Parse content files
    seed = ""
    for vol_name, stext in _find_project_files(project_path, "seed.txt"):
        seed = stext
        break
    if not seed:
        seed = get_new_style_seed(project_path)

    # Progress info
    target = config.get("target_chapters", 200)
    progress_pct = min(int(total_chapters / max(target, 1) * 100), 100) if total_chapters > 0 else 0
    # Latest chapter title
    latest_chapter = ""
    if total_chapters > 0:
        ch_dir = project_path / "chapters"
        if not ch_dir.exists() and volumes:
            for v in reversed(volumes):
                vd = project_path / v["name"]
                if (vd / "chapters").exists():
                    ch_dir = vd / "chapters"
                    break
        if ch_dir and ch_dir.exists():
            ch_files = sorted(ch_dir.glob("ch_*.md"))
            if ch_files:
                try:
                    first_line = ch_files[-1].read_text(encoding="utf-8").strip().split("\n")[0]
                    latest_chapter = first_line.lstrip("# ").strip()
                except Exception:
                    pass

    # Load latest full evaluation (from root or sub-volumes)
    eval_scores = {}
    dirs_to_check = [project_path / "eval_logs"]
    for sub in sorted(project_path.iterdir()):
        if sub.is_dir() and "卷" in sub.name:
            dirs_to_check.append(sub / "eval_logs")
    for eval_logs_dir in dirs_to_check:
        if not eval_logs_dir.exists():
            continue
        full_evals = sorted(eval_logs_dir.glob("*_full.json"))
        if not full_evals:
            continue
        try:
            data = json.loads(full_evals[-1].read_text())
            for key, val in data.items():
                if isinstance(val, dict) and "score" in val:
                    eval_scores[key] = val["score"]
        except Exception:
            pass

    # Quality summary (from scripts/ quality checks)
    q_summary = None
    if HAS_QUALITY_SCRIPTS:
        try:
            quality = run_quality_checks(project_path)
            q_chapters = quality.get("chapters", [])
            q_summary = {
                "total": len(q_chapters),
                "passed": sum(1 for c in q_chapters if c.get("ok")),
                "duplicates": len(quality.get("duplicates", [])),
                "cast": len(quality.get("cast", [])),
                "timeline": len(quality.get("timeline", [])),
            }
        except Exception as e:
            print(f"⚠️ 质量摘要计算失败: {e}")
            q_summary = None

    return render_template(
        "novel.html",
        slug=slug,
        config=config,
        volumes=volumes,
        chapters=chapters,
        total_chars=total_chars,
        total_chapters=total_chapters,
        progress_pct=progress_pct,
        latest_chapter=latest_chapter,
        eval_scores=eval_scores,
        q_summary=q_summary,
        cover=find_cover(project_path),
        world_sections=world_sections,
        characters=characters,
        outline_chapters=outline_chapters,
        outline_acts=outline_acts,
        voice_sections=voice_sections,
        seed=seed,
    )


# ── Novel Settings ─────────────────────────────────────

@app.route("/novels/<slug>/settings", methods=["GET", "POST"])
def novel_settings(slug):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    if request.method == "POST":
        config = {}
        for key in request.form:
            val = request.form[key]
            if val.isdigit():
                val = int(val)
            config[key] = val
        save_novel_config(project_path, config)
        return redirect(url_for("novel_settings", slug=slug))

    config = get_novel_config(project_path)
    # Count chapters
    total_chapters = 0
    ch_dir = project_path / "chapters"
    if ch_dir.exists():
        total_chapters = len(sorted(ch_dir.glob("ch_*.md")))
    else:
        for sub in sorted(project_path.iterdir()):
            if sub.is_dir() and "卷" in sub.name:
                sd = sub / "chapters"
                if sd.exists():
                    total_chapters += len(sorted(sd.glob("ch_*.md")))

    # Auto-detect title from seed.txt first line or config
    detected_title = config.get("title", "")
    if not detected_title:
        for fp in _find_project_files(project_path, "seed.txt"):
            first_line = fp[1].strip().split("\n")[0]
            # Strip markdown heading markers
            title = first_line.lstrip("# ").strip()
            # Remove common prefixes like "书名：" or "《"
            for prefix in ["书名：", "书名:", "《"]:
                if title.startswith(prefix):
                    title = title[len(prefix):]
            if "》" in title:
                title = title.split("》")[0]
            if title:
                detected_title = title
                break
    if not detected_title:
        # New-style: 大纲/大纲.md 第一行 `# 《八零绣娘：一针下去，全村跪了》全书大纲`
        p = project_path / "大纲" / "大纲.md"
        if p.exists():
            first = p.read_text(encoding="utf-8").strip().split("\n")[0].lstrip("# ").strip()
            if "《" in first:
                detected_title = first.split("《", 1)[1].split("》")[0].strip()
    if not detected_title:
        for fp in _find_project_files(project_path, "voice.md"):
            first_line = fp[1].strip().split("\n")[0]
            title = first_line.lstrip("# ").strip()
            if "风格" in title:  # "风格定义 — 女强打脸爽文"
                parts = title.split("—")
                if len(parts) > 1:
                    # Try to get novel name from path
                    pass
                title_parts = title.split("—")[0].replace("风格定义", "").strip().lstrip("—").strip()
                if title_parts:
                    detected_title = title_parts
                break

    # Auto-detect genre from voice/world/outline
    detected_genre = ""
    detected_tone = ""
    detect_texts = []
    for fname in ["voice.md", "world.md", "outline.md"]:
        for _v, text in _find_project_files(project_path, fname):
            detect_texts.append(text)
    if not detect_texts:
        # New-style: 设定/题材定位.md 含 年代重生/非遗/爽点 等关键词
        for sub in ["设定/题材定位.md", "设定/世界观/背景设定.md", "追踪/上下文.md"]:
            p = project_path / sub
            if p.exists():
                detect_texts.append(p.read_text(encoding="utf-8"))
    for text in detect_texts:
        text = text.lower()
        # Genre hints
        for kw, g in [("修真", "玄幻修真"), ("修仙", "玄幻修真"), ("重生", "重生"), ("穿越", "穿越"),
                      ("悬疑", "悬疑"), ("推理", "悬疑"), ("凶兽", "玄幻修真"), ("饕餮", "玄幻修真"),
                      ("宗门", "玄幻修真"), ("妖怪", "怪谈"), ("都市", "都市"), ("校园", "青春"),
                      ("末世", "末世"), ("星际", "科幻"), ("游戏", "游戏竞技")]:
            if kw in text:
                detected_genre = g
        # Tone hints
        for kw, t in [("冷峻", "冷峻"), ("悬疑", "悬疑"), ("幽默", "幽默"), ("温暖", "温暖"),
                      ("黑暗", "黑暗"), ("轻松", "轻松"), ("热血", "热血"), ("甜宠", "甜宠"),
                      ("打脸", "爽文"), ("爽文", "爽文"), ("搞笑", "幽默")]:
            if kw in text:
                detected_tone = t
        if detected_genre and detected_tone:
            break

    # Auto-detect status
    target = config.get("target_chapters", 200)
    if total_chapters == 0:
        detected_status = "构思中"
    elif total_chapters < target * 0.3:
        detected_status = "构建中"
    elif total_chapters < target:
        detected_status = "起草中"
    else:
        detected_status = "已完本"

    return render_template("novel_settings.html", slug=slug, config=config, total_chapters=total_chapters,
                           detected_title=detected_title, detected_genre=detected_genre, detected_tone=detected_tone, detected_status=detected_status)


# ── World View ─────────────────────────────────────────

@app.route("/novels/<slug>/world")
def novel_world(slug):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    sections = {}
    for vol_name, text in _find_project_files(project_path, "world.md"):
        vol_sections = parse_world(text)
        for key, val in vol_sections.items():
            label = f"{vol_name} / {key}" if vol_name else key
            sections[label] = val

    return render_template("world.html", slug=slug, sections=sections)


# ── Characters View ────────────────────────────────────

@app.route("/novels/<slug>/characters")
def novel_characters(slug):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    characters = []
    for vol_name, text in _find_project_files(project_path, "characters.md"):
        vol_chars = parse_characters(text)
        for ch in vol_chars:
            if vol_name:
                ch["name"] = f"{ch['name']}"
        characters.extend(vol_chars)
    if not characters:
        characters = parse_new_style_characters(project_path)

    # Group by role with global index
    all_chars = characters
    mains = [(i, c) for i, c in enumerate(all_chars) if c.get("role") == "主角"]
    supports = [(i, c) for i, c in enumerate(all_chars) if c.get("role") != "主角"]

    return render_template("characters.html", slug=slug, mains=mains, supports=supports)


@app.route("/novels/<slug>/character/<int:ch_index>")
def novel_character_detail(slug, ch_index):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    characters = []
    for vol_name, text in _find_project_files(project_path, "characters.md"):
        characters.extend(parse_characters(text))
    if not characters:
        characters = parse_new_style_characters(project_path)

    if ch_index < 0 or ch_index >= len(characters):
        return "人物不存在", 404

    ch = characters[ch_index]
    return render_template("character_detail.html", slug=slug, ch=ch, index=ch_index, total=len(characters))


def cn_num(n):
    """阿拉伯数字转中文数字：1→一, 12→十二, 54→五十四, 105→一百零五"""
    digits = "零一二三四五六七八九"
    if n < 10:
        return digits[n]
    if n < 20:
        return "十" + (digits[n % 10] if n % 10 else "")
    if n < 100:
        t, o = divmod(n, 10)
        return digits[t] + "十" + (digits[o] if o else "")
    h, rest = divmod(n, 100)
    s = digits[h] + "百"
    if rest:
        s += "零" + digits[rest] if rest < 10 else cn_num(rest)
    return s


# ── Outline / Story Structure ──────────────────────────

@app.route("/novels/<slug>/outline")
def novel_outline(slug):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    volumes, chapters = parse_all_outlines(project_path)

    # Enrich chapter titles from actual chapter files
    for c in chapters:
        if c["num"]:
            ch_filename = f"ch_{c['num']:02d}.md"
            ch_paths = [project_path / "chapters" / ch_filename]
            for sub in sorted(project_path.iterdir()):
                if sub.is_dir() and "卷" in sub.name:
                    ch_paths.append(sub / "chapters" / ch_filename)
            for ch_path in ch_paths:
                if ch_path.exists():
                    first_line = ch_path.read_text(encoding="utf-8").strip().split("\n")[0]
                    first_line = first_line.lstrip("# ").strip()
                    if first_line:
                        c["title"] = first_line
                    break

    # Chapters without a chapter file keep their outline title; prefix with
    # 第X章 so the format stays consistent (第五十四章  班子) even before 正文 exists.
    for c in chapters:
        if c.get("num") and not re.match(r'^第[一二三四五六七八九十百零\d]+章', c.get("title", "")):
            c["title"] = f"第{cn_num(c['num'])}章  {c['title']}"

    # Also enrich per-chapter titles in volumes (handle parent volumes with subvolumes)
    for vol in volumes:
        if vol.get("is_parent"):
            for sub in vol["subvolumes"]:
                for c in sub["chapters"]:
                    for ch2 in chapters:
                        if ch2["num"] == c["num"] and ch2.get("title"):
                            c["title"] = ch2["title"]
                            break
        else:
            for c in vol["chapters"]:
                for ch2 in chapters:
                    if ch2["num"] == c["num"] and ch2.get("title"):
                        c["title"] = ch2["title"]
                        break

    return render_template(
        "outline.html",
        slug=slug,
        volumes=volumes,
        chapters=chapters,
    )


# ── Chapter list ───────────────────────────────────────

@app.route("/novels/<slug>/chapters")
def novel_chapters(slug):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    chapters = get_chapter_stats(project_path)
    total_chars = sum(c["chars"] for c in chapters)
    config = get_novel_config(project_path)

    # Get volume info from outline (all outline files, generic, parent-aware)
    volumes, _ = parse_all_outlines(project_path)

    # Build a volume lookup: ch_num -> vol_name (parent volume name if present)
    vol_map = {}
    for vol in volumes:
        if vol.get("is_parent"):
            parent_name = vol["name"]
            for sub in vol["subvolumes"]:
                if sub.get("range"):
                    for n in range(sub["range"][0], sub["range"][1] + 1):
                        vol_map[n] = parent_name
                elif sub.get("chapters"):
                    for ch in sub["chapters"]:
                        vol_map[ch["num"]] = parent_name
        elif vol["range"]:
            for n in range(vol["range"][0], vol["range"][1] + 1):
                # Only take the volume name portion before the range parentheses
                vol_name = vol["name"]
                m = re.search(r'^(.+?)[（(]', vol_name)
                if m:
                    vol_name = m.group(1).strip()
                vol_map[n] = vol_name
        elif vol["chapters"]:
            for ch in vol["chapters"]:
                vol_name = re.sub(r'[（(].*[）)]', '', vol["name"]).strip()
                vol_map[ch["num"]] = vol_name

    # Enrich chapters with titles and volume names
    for c in chapters:
        m = re.search(r"(\d+)", c["name"])
        ch_num = int(m.group(1)) if m else None
        # Title from chapter file first line
        try:
            first_line = Path(c["path"]).read_text(encoding="utf-8").strip().split("\n")[0]
            c["title"] = first_line.lstrip("# ").strip()
        except Exception:
            c["title"] = c["name"]
        # Volume name
        c["vol_name"] = vol_map.get(ch_num, c.get("volume", ""))

    # Load latest full evaluation
    # [removed: eval_scores on chapter list — 质量检测页已覆盖，2026-08-13]

    # Mark chapters with export status
    vol_groups = []
    seen_vols = {}
    for c in chapters:
        m = re.search(r"(\d+)", c["name"])
        ch_num = int(m.group(1)) if m else None
        
        # Check export status
        ch_exported = False
        ch_export_current = False
        if ch_num:
            export_paths = [project_path / "export" / f"第{ch_num:02d}章.txt",
                            project_path / "export" / f"第{ch_num}章.txt"]
            for sub in sorted(project_path.iterdir()):
                if sub.is_dir() and "卷" in sub.name:
                    export_paths.append(sub / "export" / f"第{ch_num:02d}章.txt")
                    export_paths.append(sub / "export" / f"第{ch_num}章.txt")
            for ep in export_paths:
                if ep.exists():
                    ch_exported = True
                    try:
                        ch_mtime = Path(c["path"]).stat().st_mtime
                        export_mtime = ep.stat().st_mtime
                        ch_export_current = export_mtime >= ch_mtime
                    except Exception:
                        ch_export_current = False
                    break
        
        c["ch_exported"] = ch_exported
        c["ch_export_current"] = ch_export_current
        vname = c.get("vol_name", "") or c.get("volume", "") or "未分类"
        if vname not in seen_vols:
            seen_vols[vname] = {"name": vname, "chapters": [], "chars": 0}
            vol_groups.append(seen_vols[vname])
        seen_vols[vname]["chapters"].append(c)
        seen_vols[vname]["chars"] += c["chars"]
    
    # If no volumes found from outline, fall back to volume from file path
    all_uncategorized = len(vol_groups) == 1 and vol_groups[0]["name"] == "未分类"
    if all_uncategorized:
        for c in chapters:
            vol_from_path = c.get("volume", "")
            if vol_from_path:
                c["vol_name"] = vol_from_path
        vol_groups = []
        seen_vols = {}
        for c in chapters:
            vname = c.get("vol_name", "") or "未分类"
            if vname not in seen_vols:
                seen_vols[vname] = {"name": vname, "chapters": [], "chars": 0}
                vol_groups.append(seen_vols[vname])
            seen_vols[vname]["chapters"].append(c)
            seen_vols[vname]["chars"] += c["chars"]

    return render_template(
        "chapter_list.html",
        slug=slug,
        chapters=chapters,
        vol_groups=vol_groups,
        total_chars=total_chars,
        config=config,
    )


# ── Voice / Style ──────────────────────────────────────

@app.route("/novels/<slug>/voice")
def novel_voice(slug):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    sections = {}
    for vol_name, text in _find_project_files(project_path, "voice.md"):
        vol_sections = parse_voice(text)
        for key, val in vol_sections.items():
            label = f"{vol_name} / {key}" if vol_name else key
            sections[label] = val

    return render_template("voice.html", slug=slug, sections=sections)


# ── 连载追踪 ───────────────────────────────────────────

@app.route("/novels/<slug>/tracking")
def novel_tracking(slug):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    sections, has_tracking = get_tracking_sections(project_path)
    return render_template("tracking.html", slug=slug, sections=sections, has_tracking=has_tracking)


# ── 正典数据库 ─────────────────────────────────────────

@app.route("/novels/<slug>/canon")
def novel_canon(slug):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    sections, has_canon = get_canon_sections(project_path)
    return render_template("canon.html", slug=slug, sections=sections, has_canon=has_canon)


# ── 质量检测（复用 scripts/ 质检工具） ──────────────────

def run_quality_checks(project_path):
    """Run all quality checks. Returns dict with per-chapter results."""
    ch_dir = project_path / "chapters"
    result = {
        "has_scripts": HAS_QUALITY_SCRIPTS,
        "chapters": [],       # fanqie 6 指标
        "duplicates": [],     # 重复检测
        "cast": [],           # 角色出场
        "timeline": [],       # 时间线表述
        "warns": [],          # 时间线疑似冲突
    }
    if not HAS_QUALITY_SCRIPTS:
        return result

    files = sorted(ch_dir.glob("ch_*.md")) if ch_dir.exists() else []
    for fp in files:
        n = int(fp.stem.split("_")[1])
        # 番茄 6 指标
        r = check_chapter(fp, "final")
        r["num"] = n
        result["chapters"].append(r)

        # 重复检测
        paras = load_paras(fp)
        adj = adjacent_dups(paras, min_k=2)
        dist = distant_dups(paras, min_k=3)
        if adj or dist:
            result["duplicates"].append({
                "num": n,
                "adjacent": len(adj),
                "distant": len(dist),
            })

        # 时间线表述
        for ln, line in enumerate(fp.read_text(encoding="utf-8").splitlines(), 1):
            for m in YEAR_RE.finditer(line):
                v = cn2int(m.group(1))
                ctx = line[max(0, m.start() - 14):m.end() + 10]
                is_year = v >= 1900 or re.search(r"一九|198|197|199", m.group(0))
                is_dur = v < 100 and re.search(r"(前|来|了|头|多|整|断|查|等|压|攒|练|学|记|听)", ctx[:16])
                if not (is_year or is_dur):
                    continue
                result["timeline"].append({
                    "num": n, "line": ln,
                    "kind": "硬年份" if is_year else "年限",
                    "text": ctx.strip()[:44],
                })

    # 角色出场（从 characters.md 提取角色名 + 别名）
    names = []
    chars_path = project_path / "characters.md"
    if chars_path.exists():
        names = extract_cast(chars_path)
    appear = {nm: [] for nm in names}
    for fp in files:
        n = int(fp.stem.split("_")[1])
        txt = fp.read_text(encoding="utf-8")
        for nm in names:
            if nm in txt:
                appear[nm].append(n)
    for nm in names:
        if appear[nm]:
            result["cast"].append({
                "name": nm,
                "first": appear[nm][0],
                "last": appear[nm][-1],
                "chapters": appear[nm],
                "count": len(appear[nm]),
            })
    result["cast"].sort(key=lambda c: (-c["count"], c["first"]))
    return result


@app.route("/novels/<slug>/quality")
def novel_quality(slug):
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return "小说不存在", 404

    config = get_novel_config(project_path)
    quality = run_quality_checks(project_path)
    total = len(quality["chapters"])
    passed = sum(1 for c in quality["chapters"] if c["ok"])
    return render_template(
        "quality.html",
        slug=slug,
        config=config,
        quality=quality,
        total=total,
        passed=passed,
    )


# ── File editor (fallback for raw editing) ─────────────

@app.route("/api/novels/<slug>/save", methods=["POST"])
def api_save_file(slug):
    data = request.get_json()
    file_path = data.get("file", "")
    content = data.get("content", "")
    project_path = NOVELS_DIR / slug

    full_path = project_path
    for part in file_path.split("/"):
        full_path = full_path / part
    try:
        full_path = full_path.resolve()
        if not str(full_path).startswith(str(project_path.resolve())):
            return jsonify({"ok": False, "error": "路径非法"}), 403
    except Exception:
        return jsonify({"ok": False, "error": "路径解析失败"}), 400

    try:
        full_path.parent.mkdir(parents=True, exist_ok=True)
        full_path.write_text(content, encoding="utf-8")
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# [removed: pipeline and export routes]

# ── Directory Browser ──────────────────────────────────

# ── Directory Browser ──────────────────────────────────

@app.route("/api/browse-directory")
def api_browse_directory():
    """List subdirectories of a given path."""
    path = request.args.get("path", "~")
    try:
        p = Path(path).expanduser().resolve()
        if not p.is_dir():
            return jsonify({"ok": False, "error": "不是目录"})
        items = []
        for child in sorted(p.iterdir()):
            if child.is_dir() and not child.name.startswith("."):
                items.append({
                    "name": child.name,
                    "path": str(child),
                })
        return jsonify({"ok": True, "current": str(p), "parent": str(p.parent) if p.parent != p else None, "items": items})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})


# ── Main ───────────────────────────────────────────────

@app.route("/api/novels/<slug>/chapter/<int:ch_num>/content")
def api_chapter_content(slug, ch_num):
    """Return chapter content as JSON."""
    project_path = NOVELS_DIR / slug
    if not project_path.exists():
        return jsonify({"ok": False, "error": "小说不存在"}), 404
    
    # Search for export file first, then chapter file
    ch_path = None
    for ext_path in [
        project_path / "export" / f"第{ch_num:02d}章.txt",
        project_path / "export" / f"第{ch_num}章.txt",
    ]:
        if ext_path.exists():
            ch_path = ext_path
            break
    
    if not ch_path:
        ch_filename = f"ch_{ch_num:02d}.md"
        ch_path = project_path / "chapters" / ch_filename
        if not ch_path.exists():
            for sub in sorted(project_path.iterdir()):
                if sub.is_dir() and "卷" in sub.name:
                    ch_path = sub / "chapters" / ch_filename
                    if ch_path.exists():
                        break
                    # Also check export in sub-volume
                    for ep in [
                        sub / "export" / f"第{ch_num:02d}章.txt",
                        sub / "export" / f"第{ch_num}章.txt",
                    ]:
                        if ep.exists():
                            ch_path = ep
                            break
    
    if not ch_path or not ch_path.exists():
        return jsonify({"ok": False, "error": f"第{ch_num}章不存在"}), 404
    
    text = ch_path.read_text(encoding="utf-8")
    lines = text.strip().split("\n")
    title = lines[0].lstrip("# ").strip() if lines else f"第{ch_num}章"
    content = "\n".join(lines[1:]).strip() if len(lines) > 1 else ""
    
    return jsonify({"ok": True, "title": title, "content": content, "num": ch_num})

if __name__ == "__main__":
    print(f"🚀 autonovel-cn Web UI v2")
    print(f"📂 Novels: {NOVELS_DIR}")
    print(f"🌐 http://localhost:8080")
    app.run(host="0.0.0.0", port=8080, debug=False)
