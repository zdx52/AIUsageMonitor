#!/usr/bin/env python3
"""
check_duplicate_text.py — LLM 生成重复文本检测器

检测 novels/项目/chapters/ch_XX.md 中的两种重复：
  1. 紧邻重复：同一位置连续输出两遍的段落块（LLM 重复循环 bug，
     如 33 章"一半的账过他的手"六组问答整段 ×2）
  2. 远处重复：同章内相隔较远的相同段落块（复制粘贴/模型复发，
     内容段数 ≥3 才报，避免误伤"爹/嗯？"这类两段式场景呼应）

以"段落"（空行分隔的文本块）为比较单元，忽略空行数差异。

用法:
  python check_duplicate_text.py --project ../novels/书名
  python check_duplicate_text.py --project ../novels/书名 --chapters 33,34,35
  python check_duplicate_text.py --project ../novels/书名 --min-k 2   # 紧邻重复最小段数(默认2)

退出码: 有重复=1，无重复=0（便于接进写章流程自动卡点）
"""
import argparse
import sys
from pathlib import Path


def load_paras(path: Path):
    """返回 [(起始行号, 段落文本), ...]，跳过 # 标题行。"""
    lines = path.read_text(encoding="utf-8").splitlines()
    paras = []
    cur, cur_start = [], None
    for idx, l in enumerate(lines, 1):
        if l.strip():
            if cur_start is None:
                cur_start = idx
            cur.append(l)
        else:
            if cur:
                paras.append((cur_start, "\n".join(cur)))
                cur, cur_start = [], None
    if cur:
        paras.append((cur_start, "\n".join(cur)))
    return paras


def adjacent_dups(paras, min_k=2):
    """紧邻重复：paras[i:i+k] == paras[i+k:i+2k]，最大块优先，嵌套去重。"""
    n = len(paras)
    texts = [p[1] for p in paras]
    reported = set()
    res = []
    for k in range(n // 2, min_k - 1, -1):
        for i in range(n - 2 * k + 1):
            if (i, i + k) in reported:
                continue
            if texts[i:i + k] == texts[i + k:i + 2 * k]:
                res.append((k, i, i + k))
                reported.add((i, i + k))
                # 标记 k-1 窗口为已报，避免嵌套重复
                reported.add((i + 1, i + k))
    return res


def distant_dups(paras, min_k=3, skip=()):
    """远处重复：两处相隔的相同段落块，内容段数 ≥3。
    skip: 紧邻重复已覆盖的段落区间，跳过避免双报。"""
    n = len(paras)
    texts = [p[1] for p in paras]
    skip = set(skip)
    pos = {}
    res = []
    for i in range(n):
        if i in skip:
            continue
        t = texts[i]
        if t not in pos:
            pos[t] = i
            continue
        j = pos[t]
        if abs(j - i) <= 1:
            pos[t] = i
            continue
        # 从 j、i 起扩展相同块
        k = 0
        while i + k < n and texts[j + k] == texts[i + k]:
            k += 1
        if k >= min_k and i - j > k:
            # i-j > k 保证两块真正隔开（紧邻/重叠的归 adjacent_dups 管）
            res.append((k, j, i))
            # 跳过已匹配区间
            for m in range(i + 1, min(n, i + k)):
                pos[texts[m]] = m
    return res


def preview(text: str, width: int = 32) -> str:
    one = text.splitlines()[0]
    return one if len(one) <= width else one[:width] + "…"


def check_chapter(path: Path, min_k: int):
    paras = load_paras(path)
    adj = adjacent_dups(paras, min_k)
    # 紧邻重复覆盖的段落区间 → 远处重复跳过
    skip = set()
    for k, i, _ in adj:
        skip.update(range(i, i + 2 * k))
    dis = distant_dups(paras, skip=skip)
    return paras, adj, dis


def main():
    parser = argparse.ArgumentParser(description="章节重复文本检测")
    parser.add_argument("--project", "-p", required=True)
    parser.add_argument("--chapters", default=None, help="逗号分隔章节号，默认全部")
    parser.add_argument("--min-k", type=int, default=2,
                        help="紧邻重复最小段数（默认2；想只报大块可设3-4）")
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

    print(f"[min-k={args.min_k}] 紧邻重复≥{args.min_k}段 / 远处重复≥3段")
    print("-" * 70)
    total_issues = 0
    for n in nums:
        p = chdir / f"ch_{n:02d}.md"
        if not p.exists():
            print(f"⚠️ 缺少 ch_{n:02d}.md")
            continue
        paras, adj, dis = check_chapter(p, args.min_k)
        if not adj and not dis:
            print(f"{p.name:<10} ✅")
            continue
        print(f"{p.name:<10} ❌ 紧邻×{len(adj)} 远处×{len(dis)}")
        for k, i, i2 in adj:
            print(f"    紧邻 @行{paras[i][0]} ({k}段): 「{preview(paras[i][1])}」")
        for k, j, i in dis:
            print(f"    远处 @行{paras[j][0]} / {paras[i][0]} ({k}段): 「{preview(paras[j][1])}」")
        total_issues += len(adj) + len(dis)

    print("-" * 70)
    if total_issues:
        print(f"❌ 共 {total_issues} 处重复")
        sys.exit(1)
    print(f"✅ 全部 {len(nums)} 章无重复")


if __name__ == "__main__":
    main()
