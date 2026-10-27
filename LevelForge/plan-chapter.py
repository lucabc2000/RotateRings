# Plans a chapter of fifty levels after 100: targets on the difficulty curve and one design per
# level, written out as the Swift tables for `DifficultyCurve.targets` (appended) and
# `Compositions.templates`.
#
#   python3 LevelForge/plan-chapter.py FIRST SEED LevelForge/chapter-trial-scores.json [snapshot.json]
#   (FIRST is 101 or 151; the seeds used are recorded in Compositions.templates)
#
# Levels 11-100 come from plan-curve.py and are left alone. Designs already used from level 50 on are
# scored with what they actually measured (levels-report.json, so a rerun re-plans from real
# numbers); new designs with the scores measured by `forge compose` (trial-scores.json:
# {expr: score}). See LEVEL-DESIGN.md §12 and §13.
import json, random, re, sys

FIRST = int(sys.argv[1]) if len(sys.argv) > 1 else 101
random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 30)
LAST = FIRST + 49
# Per chapter: the baseline it climbs, the highest target, and the opening offsets. 101 opens with a
# warm-up for players coming back after an update; 151 just lets go after the peak at 150.
CHAPTERS = {101: dict(base=(67, 76), cap=82, opening=[-9, -4]),
            151: dict(base=(68, 75), cap=80, opening=[-5])}
chapter = CHAPTERS[FIRST]

swift = open('RotateRings/Model/Generation/Compositions.swift').read()
table = {int(n): e for n, e in re.findall(r'case (\d+): return \[(.*)\]\n', swift)}
report = json.load(open('RotateRings/Levels/levels-report.json'))
# Measured scores per design. With a fourth argument they are read from (or, the first time,
# saved to) that file: replanning several chapters in a row changes the table the scores are
# paired with, so later chapters must use the snapshot taken before the first was rewritten.
snapshot = sys.argv[4] if len(sys.argv) > 4 else None
try:
    measured = json.load(open(snapshot)) if snapshot else None
except FileNotFoundError:
    measured = None
if measured is None:
    measured = {}
    for level in report['levels']:
        n = level['number']
        # Only levels generated from the current table; trial samples are single seeds.
        if 50 <= n <= 150 and n in table:
            base = re.sub(r', bombs: \d+', '', table[n])
            measured.setdefault(base, []).append(level['chosen']['difficulty'])
    measured = {k: sum(v) / len(v) for k, v in measured.items()}
    if snapshot:
        json.dump(measured, open(snapshot, 'w'), indent=1)
trial = json.load(open(sys.argv[3])) if len(sys.argv) > 3 else {}

def family(expr):
    """Board kind (never twice running), kind of difficulty, and the mask (outline) it is drawn on."""
    mask = (re.search(r'"(hubs-[a-z]+|weave-[a-z]+)"', expr) or [None, expr.split('(')[0]])[1]
    if expr.startswith('freeKnot'):
        # The board kinds without a grid (§13). The kind stands in for the outline.
        dense = 'dense: true' in expr
        if 'giant:' in expr:
            fam, grp, mask = 'R', 'picture', 'giant' + ('-large' if dense else '')
        elif 'gate: true' in expr:
            fam, grp, mask = 'G', 'gate', 'gates' + ('-large' if dense else '')
        else:
            fam, grp, mask = 'D' if dense else 'F', 'chain', 'thicket' if dense else 'wild'
    elif expr.startswith('knot'):
        bars, tails, us = 'bars:' in expr, 'tails:' in expr, 'uBars:' in expr
        fam = 'U' if us else 'KX' if bars and tails else 'KB' if bars else 'KT' if tails else 'K'
        grp = 'cross' if us or (bars and not tails) else 'obstacle' if tails else 'chain'
    elif expr.startswith('hubWeb'):
        fam, grp = ('WB', 'cross') if 'bars:' in expr else ('W', 'prep')
    elif expr.startswith('maze'):
        fam, grp = 'M', 'order'
    elif expr.startswith('cages'):
        fam, grp = 'C', 'order'
    else:
        fam, grp = 'T', 'picture'
    return fam, grp, mask

# Too light for this stretch: the column knot has 18 pieces and measured 44-65 here, the smaller
# tight maze 57.
EXCLUDE = ('knot("hubs-column"', 'maze(cols: 11, rows: 18')
C = []
for expr, exp in list(measured.items()) + list(trial.items()):
    if any(c['expr'] == expr for c in C) or expr.startswith(EXCLUDE):
        continue
    fam, grp, mask = family(expr)
    C.append(dict(expr=expr, fam=fam, grp=grp, mask=mask, exp=exp, used=0, new=expr in trial and expr not in measured))

# Waves, as in plan-curve.py: phrases of four to seven levels that build and let go.
phrases = [[-3, 3, 9, -10], [0, 6, -4, 12, -8, -1], [-11, 1, 5, 3, 14, -6], [3, -5, 8, 10, -12], [-2, 4, -9, 7],
           [5, -2, 2, 11, -3, -10, 6], [-6, 8, -1, 4, 15, -9], [2, 9, -7, -2, 6, 12, -13], [-4, 0, 7, -11, 10]]
count = LAST - FIRST + 1
offsets, last = [], None
while len(offsets) < count:
    p = random.choice([q for q in phrases if q is not last]); last = p
    offsets += [o + random.choice([-2, -1, 0, 1, 2]) for o in p]
offsets = offsets[:count]
offsets[:len(chapter['opening'])] = chapter['opening']
offsets[-1] = 12; offsets[-2] = -5    # the last level is a peak after a breath

history = [family(table[FIRST - 2]), family(table[FIRST - 1])]   # (fam, grp, mask) of the two levels before
# What the previous chapter leaned on counts a quarter against it here, so a chapter does not simply
# repeat the last (half was enough to push the heaviest designs out of the peaks).
mask_used = {}
if FIRST > 101:
    for n in range(FIRST - 50, FIRST):
        f = family(re.sub(r', bombs: \d+', '', table[n]))
        mask_used[f[2]] = mask_used.get(f[2], 0) + 0.25
        for c in C:
            if c['expr'] == re.sub(r', bombs: \d+', '', table[n]): c['used'] += 0.25
# Bombs: about one level in four, never two levels running, often two of them; only on knot boards
# bombs have been placed on before (the outlines with holes rarely leave a ring that turns freely
# from the start).
next_bomb = FIRST + 2
def bombable(c):
    return c['fam'] in ('K', 'KT', 'KB', 'KX', 'U') and c['mask'] in ('hubs-field', 'hubs-tall', 'hubs-column', 'hubs-grand', 'hubs-twelve')
def broad(fam): return 'knot' if fam in ('K', 'KT', 'KB', 'KX', 'U') else 'web' if fam in ('W', 'WB') else 'wild' if fam in ('F', 'G', 'R', 'D') else fam
def is_scene(c):
    """A change of scene: mazes, cage boards, tangles and ring figures, and the free-form kinds on
    the standard board (light: their rings do not pack as tightly as a grid)."""
    return c['fam'] in ('M', 'C', 'T') or (c['expr'].startswith('freeKnot') and 'dense: true' not in c['expr'])
next_scene = FIRST + random.choice([4, 5, 6])
plan = []
for i, level in enumerate(range(FIRST, LAST + 1)):
    # Pitched where the designs reach: the score's clamps put the heaviest boards in the high 70s.
    low, high = chapter['base']
    base = low + (high - low) * (i / (count - 1))
    target = max(50, min(chapter['cap'], base + 0.8 * offsets[i]))
    bomb_due = level >= next_bomb
    recent = [h[0] for h in history[-2:]]
    # Every five to eight levels, on a dip in the curve, the board changes scene entirely.
    scene = level >= next_scene and offsets[i] < 0
    def cost(c):
        k = abs(c['exp'] - target) + 2 * c['used'] + 2.5 * mask_used.get(c['mask'], 0)
        if scene != is_scene(c): k += 1000
        if c['fam'] == recent[-1]: k += 100
        if c['fam'] in recent: k += 6
        if c['grp'] == history[-1][1]: k += 5
        if c['mask'] == history[-1][2]: k += 8
        # Webs with or without bars look alike, and so do knots: no three of a kind running.
        kind = broad(c['fam'])
        if kind == broad(history[-1][0]): k += 6 if kind == 'knot' else 12
        # Knots over webs: in a web 40-50 % of the pieces can move, which reads easy (§7).
        if kind == 'web': k += 4
        if kind == broad(history[-1][0]) == broad(history[-2][0]): k += 100
        if level == LAST and c['exp'] < 74: k += 1000  # the finale is one of the heaviest boards
        if bomb_due and bombable(c): k -= 6
        if c['new'] and c['used'] < 1: k -= 7         # every new design gets its turn
        if kind == 'wild': k -= 10                      # the board kinds without a grid are the point of 101-200 (§13)
        if 'tails' in c['expr']: k -= 2                 # the owner wants tails often
        return k + random.random()
    c = min(C, key=cost); c['used'] += 1
    mask_used[c['mask']] = mask_used.get(c['mask'], 0) + 1
    if scene: next_scene = level + random.choice([5, 6, 7, 8])
    expr, bombs = c['expr'], 0
    if bomb_due and bombable(c):
        bombs = 2 if random.random() < 0.5 else 1
        expr = expr[:-1] + f', bombs: {bombs})'
        next_bomb = level + random.choice([3, 3, 4, 4, 5])
    history.append((c['fam'], c['grp'], c['mask']))
    plan.append(dict(level=level, target=round(target), offset=offsets[i], expr=expr, fam=c['fam'], exp=round(c['exp']), bombs=bombs))

for p in plan:
    print(f"// {p['level']} target {p['target']} ({p['offset']:+d}) {p['fam']}{'*' if p.get('bombs') else ''} usual {p['exp']}")
print('targets:', ', '.join(str(p['target']) for p in plan))
for p in plan:
    print(f"        case {p['level']}: return [{p['expr']}]")
