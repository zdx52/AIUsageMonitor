#!/usr/bin/env python3
"""
scan_cast.py — 角色出场扫描（连载追踪辅助）

扫描 novels/项目/chapters/ch_XX.md，统计每个角色出现的章节，
自动得出"首出场章/最后出场章"，供连载追踪.md 的角色状态表维护。
注意：粗扫是"名字出现"，提及≠真身出场，审计时人工确认标记。

用法:
  python scan_cast.py --project ../novels/书名 --chars 林巧,张建国,吴振山
  python scan_cast.py --project ../novels/书名          # 自动从 characters.md 的 ### 标题提取角色名
  --aliases "孙师傅=孙德厚,陈厂长=陈永年"                # 别名合并（同一人的不同称呼）
"""
import argparse
import re
import sys
from pathlib import Path


def extract_cast(chars_path: Path):
    """从 characters.md 的 ### 标题提取角色名（含括号里的全名）。"""
    txt = chars_path.read_text(encoding="utf-8")
    names = []
    for m in re.finditer(r"^###\s+(.+)$", txt, flags=re.M):
        head = m.group(1).strip()
        # "孙师傅（孙德厚）" → 孙师傅 + 孙德厚
        mm = re.match(r"^(.*?)[（(](.*?)[)）]$", head)
        if mm:
            names.append(mm.group(1).strip())
            names.append(mm.group(2).strip())
        else:
            names.append(head)
    return [n for n in names if n and not re.match(r"^[A-Za-z]", n)]


def main():
    ap = argparse.ArgumentParser(description="角色出场章节扫描")
    ap.add_argument("--project", "-p", required=True)
    ap.add_argument("--chars", default=None, help="逗号分隔角色名；缺省从 characters.md 提取")
    ap.add_argument("--aliases", default=None, help="别名合并，如 '孙师傅=孙德厚,陈厂长=陈永年'")
    args = ap.parse_args()

    proj = Path(args.project).resolve()
    chdir = proj / "chapters"
    if not chdir.exists():
        print(f"❌ 找不到 {chdir}")
        sys.exit(1)

    if args.chars:
        names = [c.strip() for c in args.chars.split(",") if c.strip()]
    else:
        cp = proj / "characters.md"
        if not cp.exists():
            print(f"❌ 找不到 characters.md，请用 --chars 手动指定")
            sys.exit(1)
        names = extract_cast(cp)
        print(f"# 角色名单来自 characters.md（{len(names)} 个）")

    # 别名合并
    alias_map = {}
    if args.aliases:
        for pair in args.aliases.split(","):
            if "=" in pair:
                a, b = pair.split("=", 1)
                alias_map[a.strip()] = b.strip()

    files = sorted(chdir.glob("ch_*.md"))
    if not files:
        print("❌ chapters/ 下没有 ch_*.md")
        sys.exit(1)

    # 出现章（按名字精确子串匹配，先粗扫）
    appear = {n: [] for n in names}
    for fp in files:
        n = int(fp.stem.split("_")[1])
        txt = fp.read_text(encoding="utf-8")
        for name in names:
            if name in txt:
                appear[name].append(n)

    # 别名合并：把别名出现并入主名
    for alias, main in alias_map.items():
        if alias in appear and main in appear:
            appear[main] = sorted(set(appear[main]) | set(appear[alias]))
            appear[alias] = appear[main]  # 显示同一结果

    # 输出
    print(f"\n{'角色':<12}{'出场章数':<6}{'首章':<6}{'末章':<6}出场章")
    print("-" * 60)
    for name in names:
        chs = appear[name]
        if not chs:
            print(f"{name:<12}{'—':<6}{'—':<6}{'—':<6}未出场")
            continue
        span = chs
        # 压缩连续区间
        groups, start, prev = [], span[0], span[0]
        for c in span[1:]:
            if c == prev + 1:
                prev = c
            else:
                groups.append((start, prev)); start = prev = c
        groups.append((start, prev))
        span_str = ",".join(f"{a}" if a == b else f"{a}-{b}" for a, b in groups)
        print(f"{name:<12}{len(chs):<6}{chs[0]:<6}{chs[-1]:<6}{span_str}")


if __name__ == "__main__":
    main()
