#!/usr/bin/env python3
"""
check_fanqie_quality.py — 番茄女频质量标准自动检测器

对 novels/项目/chapters/ch_XX.md 逐章检测 6 项指标：
  1. 纯汉字字数 2500-3000（--mode draft 时放宽为 2500-4000）
  2. 对话占比 ≥25%（引号内台词汉字/总汉字）
  3. 对话段落 ≥50%
  4. 平均段长 ≤30字
  5. 超60字段落 ≤1段
  6. AI 禁词 = 0（一丝/嘴角/心头一/深吸一口气/不知道的是/涌起/一定要/破折号/勾起一抹/一片寂静）
     （"一丝不差"等钳工术语豁免：单独计数提示，不判违规）

模式:
  --mode final  (默认) 字数 2500-3000，修订后终稿用
  --mode draft         字数 2500-4000，初稿用（初稿按 3500 写，给修订留砍字余量）

用法:
  python check_fanqie_quality.py --project ../novels/书名
  python check_fanqie_quality.py --project ../novels/书名 --chapters 4,5,6
  python check_fanqie_quality.py --project ../novels/书名 --mode draft
"""
import argparse
import re
import sys
from pathlib import Path

# 禁词（"一丝"作为钳工术语特殊处理）
BANNED = [
    "嘴角", "心头一", "深吸一口气", "不知道的是", "涌起",
    "一定要", "——", "勾起一抹", "一片寂静",
]
# 一丝：只有非"一丝不差/一丝半/一丝以内"等术语语境才算违规
YISI_TERM = re.compile(r"一丝(不差|半|以内|的公差|都不差)")
YISI_SUSPECT = re.compile(r"一丝(?!不差|半|以内|的公差|都不差)")

# 字数区间：final 严格 2500-3000；draft 放宽上限到 4000（初稿 3500 预留修订余量）
WORD_RANGE = {
    "final": (2500, 3000),
    "draft": (2500, 4000),
}


def hz(s: str) -> int:
    return len(re.findall(r"[\u4e00-\u9fff]", s))


def check_chapter(path: Path, mode: str = "final") -> dict:
    txt = path.read_text(encoding="utf-8")
    body = re.sub(r"^#.*$", "", txt, flags=re.M).strip()
    paras = [p.strip() for p in body.split("\n\n") if p.strip()]

    total = hz(body)
    quoted = re.findall(r"[“\"]([^”\"]*)[”\"]", body)
    q_chars = sum(hz(q) for q in quoted)
    dp = [p for p in paras if ("“" in p or '"' in p)]
    lens = [hz(p) for p in paras]

    banned_hits = {}
    for w in BANNED:
        c = body.count(w)
        if c:
            banned_hits[w] = c
    yisi = len(YISI_SUSPECT.findall(body))  # 可疑"一丝"（非术语）

    lo, hi = WORD_RANGE[mode]

    # 达标判定：6项全过才算 ok
    ok = (
        lo <= total <= hi
        and (q_chars / total >= 0.25 if total else False)
        and (len(dp) / len(paras) >= 0.50 if paras else False)
        and (sum(lens) // len(lens) <= 30 if lens else False)
        and sum(1 for l in lens if l > 60) <= 1
        and not banned_hits
        and yisi == 0
    )

    return {
        "file": path.name,
        "total": total,
        "dialogue_pct": round(q_chars / total * 100) if total else 0,
        "dialogue_para_pct": round(len(dp) / len(paras) * 100) if paras else 0,
        "avg_para": sum(lens) // len(lens) if lens else 0,
        "long_paras": sum(1 for l in lens if l > 60),
        "banned": banned_hits,
        "yisi_suspect": yisi,
        "ok": ok,
        "mode": mode,
        "word_range": (lo, hi),
    }


def main():
    parser = argparse.ArgumentParser(description="番茄女频质量检测")
    parser.add_argument("--project", "-p", required=True)
    parser.add_argument("--chapters", default=None, help="逗号分隔章节号，默认全部")
    parser.add_argument("--mode", choices=["final", "draft"], default="final",
                        help="final=严格2500-3000（默认）；draft=放宽上限到4000（初稿3500用）")
    args = parser.parse_args()

    proj = Path(args.project).resolve()
    chdir = proj / "chapters"
    if not chdir.exists():
        print(f"❌ 找不到 {chdir}")
        sys.exit(1)

    if args.chapters:
        nums = [int(x) for x in args.chapters.split(",")]
    else:
        nums = sorted(int(f.stem.split("_")[1]) for f in chdir.glob("ch_*.md"))

    lo, hi = WORD_RANGE[args.mode]
    results = []
    for n in nums:
        p = chdir / f"ch_{n:02d}.md"
        if not p.exists():
            print(f"⚠️ 缺少 ch_{n:02d}.md")
            continue
        results.append(check_chapter(p, args.mode))

    # 输出
    print(f"[mode={args.mode}] 字数区间: {lo}-{hi}")
    print(f"{'章':<5}{'汉字':<6}{'对话%':<6}{'对话段%':<7}{'均段':<5}{'超60':<5}禁词/一丝  状态")
    print("-" * 70)
    fails = []
    for r in results:
        issues = []
        if not (lo <= r["total"] <= hi):
            issues.append(f"字数{r['total']}")
        if r["dialogue_pct"] < 25:
            issues.append(f"对话{r['dialogue_pct']}%")
        if r["dialogue_para_pct"] < 50:
            issues.append(f"对话段{r['dialogue_para_pct']}%")
        if r["avg_para"] > 30:
            issues.append(f"均段{r['avg_para']}")
        if r["long_paras"] > 1:
            issues.append(f"超60×{r['long_paras']}")
        if r["banned"]:
            issues.append(f"禁词{list(r['banned'].keys())}")
        yisi_note = f"一丝×{r['yisi_suspect']}" if r["yisi_suspect"] else ""
        status = "✅" if not issues and not r["yisi_suspect"] else "❌"
        print(f"{r['file']:<5}{r['total']:<6}{r['dialogue_pct']}%  {r['dialogue_para_pct']}%  {r['avg_para']:<5}{r['long_paras']:<5}{yisi_note:<12}{status} {','.join(issues)}")
        if issues or r["yisi_suspect"]:
            fails.append((r["file"], issues, r["yisi_suspect"]))

    print("-" * 70)
    if fails:
        print(f"❌ {len(fails)} 章不达标")
        sys.exit(1)
    print(f"✅ 全部 {len(results)} 章达标")


if __name__ == "__main__":
    main()
