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
LAST = FIRST + 49
# Per chapter: the baseline it climbs, the highest target, and the opening offsets. 101 opens with a
# warm-up for players coming back after an update; 151 just lets go after the peak at 150.
CHAPTERS = {101: dict(base=(28, 34), cap=60, opening=[-7, -3]),
            151: dict(base=(32, 40), cap=64, opening=[-4])}
chapter = CHAPTERS[FIRST]
count = LAST - FIRST + 1
offs = planlib.offsets(count, rng, opening=chapter['opening'], closing=[-4, 10])

table = planlib.table()
designs = planlib.catalogue()
history = [('gridField' if planlib.look_of(table[n]) == 'hub' else planlib.look_of(table[n])) for n in (FIRST - 2, FIRST - 1)]
intro_done = any('locks:' in table[n] for n in range(11, FIRST))
planner = planlib.Planner(designs, rng, history, intro_done)
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


plan, fields = [], 0
for i, level in enumerate(range(FIRST, LAST + 1)):
    low, high = chapter['base']
    base = low + (high - low) * (i / (count - 1))
    target = round(max(12, min(chapter['cap'], base + offs[i])))
    looks, left, counts = planlib.block_state(plan, level, FIRST)
    d = planner.choose(level, target, offs[i], looks, left, fields, 0.4 * count, extra, counts)
    fields += d['spacing'] == 'gridField'
    expr, bombs = planner.add_bombs(level, d, FIRST + 2)
    plan.append(dict(level=level, target=target, offset=offs[i], expr=expr, look=d['look'], exp=d['exp'], bombs=bombs))

planlib.print_plan(plan)
if '--apply' in sys.argv:
    planlib.apply(plan)
