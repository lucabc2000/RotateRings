#!/usr/bin/env python3
"""Pacing check for Rotate Rings level sets.

Measures the pacing targets from LEVEL-IMPROVEMENT-PROMPT.md on a folder of level files
(level1.json ... levelN.json in the game's own format) and prints PASS/FAIL per target.
Reads only the level files; the report is optional (used for picture detection by template id).

    python3 pacing_check.py RotateRings/Levels
    python3 pacing_check.py LevelForge/sets/pacing-v1 --json

Targets come from measuring the 122 levels of the Yandex Games "Rotate Rings" (Nov 2026),
adapted to a 200-level game. They are starting points, to be retuned after play-tests.
"""
import json, os, re, sys, statistics as st

BREATHER_MAX = 10          # a breather has at most this many pieces
TARGETS = {
    "median_pieces_11_20": (7, 11),      # Yandex: 9
    "median_pieces_21_40": (11, 15),     # Yandex: 13
    "max_pieces_first5_after_tutorial": (0, 12),  # levels 11-15; Yandex max 12, yours today 20
    "breather_share_11_plus": (0.25, 1.0),        # Yandex: 28 %
    "max_breather_gap_11_100": (0, 10),           # levels between breathers; Yandex: 10
    "max_breather_gap_101_plus": (0, 20),         # Yandex: 20
    "size_cv_61_plus": (0.40, 9.9),               # Yandex: 0.47
    "picture_ratio_min": (1.0, 99.0),             # picture pieces / median of the 10 levels around it; Yandex min 1.08
    "picture_ratio_median": (1.5, 99.0),          # Yandex median 2.0
}


def load_levels(folder):
    files = [f for f in os.listdir(folder) if re.fullmatch(r"level\d+\.json", f)]
    levels = {}
    for f in files:
        d = json.load(open(os.path.join(folder, f)))
        levels[int(re.findall(r"\d+", f)[0])] = d
    return dict(sorted(levels.items()))


def picture_levels(folder, levels):
    """Levels whose report template starts with 'picture', else levels named in PICTURE_NAMES."""
    rep_path = os.path.join(folder, "levels-report.json")
    if os.path.exists(rep_path):
        rep = json.load(open(rep_path))["levels"]
        return sorted(e["number"] for e in rep
                      if (e.get("chosen", {}).get("template") or "").startswith("picture"))
    return []


def median_low(a):
    s = sorted(a)
    return s[(len(s) - 1) // 2] if s else None


def main():
    folder = sys.argv[1]
    as_json = "--json" in sys.argv
    lv = load_levels(folder)
    n = max(lv)
    pieces = {k: len(v["pieces"]) for k, v in lv.items()}
    after = [k for k in lv if k > 10]
    breathers = [k for k in after if pieces[k] <= BREATHER_MAX]
    pairs = list(zip([10] + breathers, breathers + [n + 1]))
    gaps_early = [b - a for a, b in pairs if a < 100]
    gaps_late = [b - a for a, b in pairs if a >= 100]
    late = [pieces[k] for k in lv if k > 60]
    pics = picture_levels(folder, lv)
    pic_ratio = []
    for p in pics:
        around = [pieces[k] for k in range(p - 5, p + 6) if k != p and k in pieces and k > 10]
        pic_ratio.append((p, pieces[p], round(pieces[p] / median_low(around), 2)))

    m = {
        "median_pieces_11_20": median_low([pieces[k] for k in range(11, 21) if k in pieces]),
        "median_pieces_21_40": median_low([pieces[k] for k in range(21, 41) if k in pieces]),
        "max_pieces_first5_after_tutorial": max(pieces[k] for k in range(11, 16) if k in pieces),
        "breather_share_11_plus": round(len(breathers) / len(after), 3),
        "max_breather_gap_11_100": max(gaps_early, default=0),
        "max_breather_gap_101_plus": max(gaps_late, default=0),
        "size_cv_61_plus": round(st.pstdev(late) / st.mean(late), 3) if late else None,
        "picture_ratio_min": min((r for _, _, r in pic_ratio), default=None),
        "picture_ratio_median": median_low([r for _, _, r in pic_ratio]),
    }
    result = {k: {"value": v, "target": TARGETS[k],
                  "pass": v is not None and TARGETS[k][0] <= v <= TARGETS[k][1]} for k, v in m.items()}
    extra = {
        "levels": n,
        "breathers": breathers,
        "pictures (level, pieces, ratio to neighbours)": pic_ratio,
        "median pieces per block of 20": {f"{a}-{a+19}": median_low([pieces[k] for k in range(a, a + 20) if k in pieces])
                                          for a in range(1, n + 1, 20)},
    }
    if as_json:
        print(json.dumps({"targets": result, "detail": extra}, indent=2))
        return
    for k, r in result.items():
        lo, hi = r["target"]
        print(f"{'PASS' if r['pass'] else 'FAIL'}  {k:36s} {r['value']!s:>8}   target {lo}–{hi}")
    print()
    for k, v in extra.items():
        print(f"{k}: {v}")
    sys.exit(0 if all(r["pass"] for r in result.values()) else 1)


if __name__ == "__main__":
    main()
