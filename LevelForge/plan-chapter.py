# Plans a chapter of fifty levels after 100 (FIRST is 101 or 151): targets on the difficulty curve
# (scale of `LevelQuality.difficulty`) and one design per level from the measured catalogue
# (planlib.py). Continues the look history of the levels before it in Compositions.templates, so
# run plan-curve.py --apply first. LEVEL-DESIGN.md §12-§13 for the chapters, §15 for the rules.
#
#   python3 LevelForge/plan-chapter.py FIRST [SEED] [--apply]
import random, re, sys
sys.path.insert(0, 'LevelForge')
import planlib

args = [a for a in sys.argv[1:] if not a.startswith('--')]
FIRST = int(args[0]) if args else 101
rng = random.Random(int(args[1]) if len(args) > 1 else 30)
# --count N: the levels to plan (fifty, or the eighty of 121-200 in §17).
count = next((int(a.split('=')[1]) for a in sys.argv[1:] if a.startswith('--count=')), 50)
LAST = FIRST + count - 1
# Per chapter: the baseline it climbs, the highest target, and the opening offsets. 101 opens with a
# warm-up for players coming back after an update; 151 just lets go after the peak at 150; 121 (§17)
# climbs through two chapters to the heaviest board at 200.
CHAPTERS = {101: dict(base=(28, 34), cap=60, opening=[-7, -3]),
            121: dict(base=(31, 46), cap=72, opening=[]),
            151: dict(base=(32, 40), cap=64, opening=[-4])}
chapter = CHAPTERS[FIRST]
offs = planlib.offsets(count, rng, opening=chapter['opening'], closing=[-4, 10])

table = planlib.table()
designs = planlib.catalogue()
# --keep: the breathers and pictures in the range stay exactly as the table has them (§17): their
# design, their target and their place in the breather set.
curve = open('RotateRings/Model/Generation/DifficultyCurve.swift').read()
current_targets = [float(x) for x in re.search(r'static let targets: \[Double\] = \[(.*)\]', curve).group(1).split(', ')]
current_breathers = {int(x) for x in re.search(r'static let breathers: Set<Int> = \[(.*)\]', curve).group(1).split(', ') if x}
keep = {n for n in range(FIRST, LAST + 1) if n in current_breathers} if '--keep' in sys.argv else set()
# --keep-from=DIR: every level of that set with ten pieces or fewer counts as a breather to keep
# (pacing_check.py's definition), whether or not the curve lists it.
keep_from = next((a.split('=')[1] for a in sys.argv[1:] if a.startswith('--keep-from=')), None)
kept_expr, kept_target = {}, {}
if keep_from:
    import json
    report = json.load(open(keep_from + '/levels-report.json'))
    by_template = {q['template']: expr for expr, q in planlib.QUALITY.items() if q.get('template')}
    for l in report['levels']:
        n = l['number']
        if FIRST <= n <= LAST and l['chosen']['pieceCount'] <= 10:
            keep.add(n)
            kept_expr[n] = by_template[l['chosen']['template']]       # the set's own design, whatever the table says now
            kept_target[n] = l['targetDifficulty']
history = [('gridField' if planlib.look_of(table[n]) == 'hub' else planlib.look_of(table[n])) for n in (FIRST - 2, FIRST - 1)]
intro_done = any('locks:' in table[n] for n in range(11, FIRST))
planner = planlib.Planner(designs, rng, history, intro_done)
if keep:
    for n in keep:
        expr = kept_expr.get(n) or re.sub(r', bombs: \d+', '', table[n])
        planner.fixed[n] = next(d for d in designs if d['expr'] == expr)
    planner.keep_breathers = keep
# What the levels before leaned on counts against a design here, so a chapter does not repeat the last.
for n in range(FIRST - 50, FIRST):
    base = re.sub(r', bombs: \d+', '', table[n])
    for d in designs:
        if d['expr'] == base: d['used'] += 0.25


def extra(d, level, peak, dip):
    k = 0
    if d['look'] == 'freeform': k -= 4                        # the boards without a grid are the point of 101-200 (§13)
    if 'tails' in d['expr']: k -= 2                          # the owner wants tails often
    if level == LAST and (d['exp'] < 50 or d['unplanned'] > planlib.UNPLANNED_LIMIT): k += 1000  # the finale is heavy and planned
    return k


low, high = chapter['base']
targets = [round(max(12, min(chapter['cap'], low + (high - low) * (i / (count - 1)) + offs[i]))) for i in range(count)]
# Tier-2 peaks aim at what tier-2 boards measure.
targets = [max(t, planlib.tier2_target(FIRST + i)) if planlib.wants_tier2(offs[i], t, FIRST + i) else t for i, t in enumerate(targets)]
# Kept breathers keep their targets too. A chapter end (§17) is the hardest level of its chapter:
# its target tops every other in the fifty before it, on a peak offset.
for n in keep:
    targets[n - FIRST] = kept_target.get(n, current_targets[n - 11])
for m in planlib.MILESTONES:
    if FIRST < m <= LAST:
        offs[m - FIRST] = planlib.PEAK + 4
        targets[m - FIRST] = max(max(targets[max(0, m - 49 - FIRST):m - FIRST + 1]), planlib.tier2_target(m))
    # The levels before a chapter end build up to it and the one after lets go (as 151 did before):
    # no peak within three levels of the hardest board.
    for k in (-3, -2, -1, 1):
        n = m + k
        if FIRST < n <= LAST and offs[n - FIRST] > (3 if k < 0 else -2):
            offs[n - FIRST] = 3 if k < 0 else -4
            targets[n - FIRST] = round(max(12, low + (high - low) * ((n - FIRST) / (count - 1)) + offs[n - FIRST]))
planner.tier2_peaks = {FIRST + i for i in range(count) if planlib.wants_tier2(offs[i], targets[i], FIRST + i)}
plan, fields = [], 0
for i, level in enumerate(range(FIRST, LAST + 1)):
    target = targets[i]
    looks, left, counts = planlib.block_state(plan, level, FIRST)
    before_tier2 = i + 1 < count and planlib.wants_tier2(offs[i + 1], targets[i + 1], level + 1)
    d = planner.choose(level, target, offs[i], looks, left, fields, 0.4 * count, extra, counts, before_tier2)
    fields += d['spacing'] == 'gridField'
    expr, bombs = planner.add_bombs(level, d, FIRST + 2)
    if planner.last_light:
        target = planlib.light_target(d, target)
    plan.append(dict(level=level, target=target, offset=offs[i], expr=expr, look=d['look'], exp=d['exp'], bombs=bombs,
                     pieces=d['pieces'], range=planner.last_range, light=planner.last_light, interest=d['interest'], tier=d['tier'],
                     peak=(planlib.wants_tier2(offs[i], target, level) or level in planlib.MILESTONES) and level not in planlib.PICTURE_SLOTS,
                     breather=level in keep or planner.last_small or (planner.last_light and planner.last_range[1] <= 10)))

planlib.print_plan(plan)
planlib.print_pacing(plan)
planlib.print_blocks(plan)
if '--apply' in sys.argv:
    planlib.apply(plan)
