"""Regression check for 卷3 (H1-range parent volumes) parsing.

Run from web/:  .venv/bin/python ../web/test_vol3_parse.py
(or anywhere with app importable). Asserts the tree that the
UI (故事架构/章节列表/总览) depends on.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import app as a

PROJ = Path("/Users/zdx52/Documents/Hermes/小说创作/novels/七零年代：手艺人她杀疯了")


def main():
    vols, chs = a.parse_all_outlines(PROJ)
    # Locate by name — the novel keeps growing new volumes, so the count is not asserted
    by_name = {v["name"]: v for v in vols}
    v1 = by_name["卷1《杀穿红星厂》"]
    v2 = by_name["卷2《活过三十岁》"]
    v3 = by_name["卷3《路是走出来的》"]

    # 卷1/卷2 content lives in subvolumes; no own-chapter duplication
    assert v1["chapters"] == [] and len(v1["subvolumes"]) == 5
    assert v2["chapters"] == [] and len(v2["subvolumes"]) == 2
    for v in (v1, v2):
        own = {c["num"] for c in v["chapters"]}
        sub = {c["num"] for sub in v["subvolumes"] for c in sub["chapters"]}
        assert not (own & sub), f"{v['name']} overlaps own/sub chapters"

    # 卷3 has its own 40 chapters 81-120 (no subvolumes)
    assert v3["subvolumes"] == []
    nums = [c["num"] for c in v3["chapters"]]
    assert nums == list(range(81, 121)), nums[:3]
    # real details present where the 细纲 was written
    c81 = next(c for c in v3["chapters"] if c["num"] == 81)
    assert c81["title"] == "省城的路" and "核心事件" in c81["details"]

    # global chapter list: contiguous from chapter 1, no duplicates
    all_nums = [c["num"] for c in chs]
    assert all_nums == sorted(all_nums), "chapter list not sorted"
    assert len(set(all_nums)) == len(all_nums), "duplicate chapter numbers"
    assert all_nums[0] == 1 and all_nums == list(range(1, all_nums[-1] + 1)), "chapter numbers have gaps"

    print(f"OK: 卷1/卷2/卷3 tree correct, chapters 1-{all_nums[-1]} contiguous and unique")


if __name__ == "__main__":
    main()
