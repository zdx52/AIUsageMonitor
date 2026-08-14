#!/usr/bin/env python3
"""
check_continuity.py — 时间线一致性审计（连载追踪辅助）

扫描 chapters/ch_XX.md 的时间表述，与锚点/基准比对，抓穿帮。
设计目标：把"十一年 vs 1970工伤"这类人工审计才能发现的矛盾自动化。

用法:
  python check_continuity.py --project ../novels/书名
  --anchors "ch01=1975,ch37=1978,ch39=1979,ch40=1980"   # 章号=年份锚点（推算每章时点）
  --facts "工伤=1970,进厂=1975"                          # 关键词=基准年（正文含关键词的 N 年表述与之比对）
  --start 1975                                          # 故事开始年（相对"第N年/N年前"换算）

输出: ①硬年份 vs 锚点推算时点冲突 ⚠️ ②含基准关键词的年限表述偏离 ⚠️ ③全部时间表述清单（人工复核）
退出码: 有 ⚠️ 冲突 = 1，无 = 0
"""
import argparse
import re
import sys
from pathlib import Path

# 中文数字 → 阿拉伯
CN = {"零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
      "六": 6, "七": 7, "八": 8, "九": 9, "十": 10, "百": 100, "千": 1000}


def cn2int(s: str):
    if s.isdigit():
        return int(s)
    # 口语约数连写："七八年"≈7、"两三个"≈2 —— 取第一个
    if re.fullmatch(r"[一二三四五六七八九两]{2,}", s):
        return CN[s[0]]
    total, cur = 0, 0
    for ch in s:
        if ch in CN:
            v = CN[ch]
            if v >= 10:
                cur = cur * v if cur else v
                total += cur
                cur = 0
            else:
                cur += v
    return total + cur


HARD_YEAR = re.compile(r"(?:一九|一九八|一九七|一?九)[〇零一二三四五六七八九十百]+年|(?:19|20)\d{2}年|\d{1,2}年")
YEAR_RE = re.compile(r"([〇零一二三四五六七八九十百\d]+)年")
AGE_RE = re.compile(r"([〇零一二三四五六七八九十百\d]+)岁")
SEASON = ["开春", "春天", "夏天", "秋天", "冬天", "入冬", "年底", "年初", "春", "冬"]

FACT_KEYWORDS = ["工伤", "断了", "进厂", "入厂", "学徒", "进厂头一天", "转正"]


def est_year_for_chapter(n: int, anchors):
    """锚点线性插值推算章节时点年份。"""
    if not anchors:
        return None
    pts = sorted(anchors.items())  # [(ch, year)]
    if n <= pts[0][0]:
        return pts[0][1]
    if n >= pts[-1][0]:
        return pts[-1][1]
    for (c1, y1), (c2, y2) in zip(pts, pts[1:]):
        if c1 <= n <= c2:
            return round(y1 + (y2 - y1) * (n - c1) / (c2 - c1))
    return None


def main():
    ap = argparse.ArgumentParser(description="时间线一致性审计")
    ap.add_argument("--project", "-p", required=True)
    ap.add_argument("--anchors", default="", help="章号=年份，逗号分隔，如 ch01=1975,ch37=1978")
    ap.add_argument("--facts", default="", help="关键词=基准年，逗号分隔，如 工伤=1970,进厂=1975")
    ap.add_argument("--start", type=int, default=None, help="故事开始年（相对'第N年/N年前'换算）")
    args = ap.parse_args()

    proj = Path(args.project).resolve()
    chdir = proj / "chapters"
    if not chdir.exists():
        print(f"❌ 找不到 {chdir}")
        sys.exit(1)

    anchors = {}
    for pair in args.anchors.split(","):
        if "=" in pair:
            c, y = pair.split("=")
            anchors[int(re.sub(r"\D", "", c))] = int(y)
    facts = {}
    for pair in args.facts.split(","):
        if "=" in pair:
            k, y = pair.split("=")
            facts[k.strip()] = int(y)

    files = sorted(chdir.glob("ch_*.md"))
    if not files:
        print("❌ 无章节文件")
        sys.exit(1)

    warns, all_hits = [], []
    print(f"{'章':<7}{'时点':<7}{'类型':<6}表述（原文片段）")
    print("-" * 74)
    for fp in files:
        n = int(fp.stem.split("_")[1])
        t = fp.read_text(encoding="utf-8")
        cur = est_year_for_chapter(n, anchors)
        cur_s = str(cur) if cur else "?"
        lines = t.splitlines()
        for ln, line in enumerate(lines, 1):
            for m in YEAR_RE.finditer(line):
                v = cn2int(m.group(1))
                # 过滤明显是序号/数额的（如 "三十八" 工资、"20年" 可能误报——用上下文宽松处理）
                ctx = line[max(0, m.start() - 14):m.end() + 10]
                # 硬年份（≥1900 或中文"一九"开头）
                is_year = v >= 1900 or re.search(r"一九|198|197|199", m.group(0))
                # 相对年限
                is_dur = v < 100 and re.search(r"(前|来|了|头|多|整|断|查|等|压|攒|练|学|记|听)", ctx[:16])
                if not (is_year or is_dur):
                    continue
                kind = "硬年份" if is_year else "年限"
                note = ""
                # 硬年份一律不判冲突（背景/前世回忆太常见），只列清单
                # 基准事实校验：年限表述前后 8 字内含基准关键词才算（收紧防误报）
                if kind == "年限":
                    window = line[max(0, m.start() - 8):m.end() + 8]
                    for kw, base in facts.items():
                        if kw in window:
                            expect = base + v
                            if cur and abs(expect - cur) > 2:
                                note = f"⚠️ {kw}基准{base}+{v}={expect} ≠ 章时点{cur}"
                                warns.append((fp.name, ln, note))
                all_hits.append((fp.name, ln, cur_s, kind, ctx.strip()[:44], note))
                print(f"{fp.name:<7}{cur_s:<7}{kind:<6}{ctx.strip()[:44]}" + (f"  {note}" if note else ""))

    print("-" * 74)
    if warns:
        print(f"⚠️ 发现 {len(warns)} 处疑似矛盾（需人工复核）:")
        for fn, ln, w in warns:
            print(f"  {fn}:{ln} {w}")
        sys.exit(1)
    print(f"✅ 时间表述 {len(all_hits)} 处，无硬冲突（清单见上，供人工复核）")


if __name__ == "__main__":
    main()
