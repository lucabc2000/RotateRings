# Plans levels 11-100: targets on the difficulty curve (scale of `LevelQuality.difficulty`) and one
# design per level, chosen from the catalogue with what each design measured (planlib.py,
# LevelForge/design-quality.json). LEVEL-DESIGN.md §10 for the waves, §15 for the rules.
#
#   python3 LevelForge/plan-curve.py [SEED] [--apply]
#
# Prints the plan and the Swift tables; with --apply writes them into Compositions.templates and
# DifficultyCurve.targets.
import random, sys
sys.path.insert(0, 'LevelForge')
import planlib

args = [a for a in sys.argv[1:] if not a.startswith('--')]
rng = random.Random(int(args[0]) if args else 7)
FIRST, LAST = 11, 100
count = LAST - FIRST + 1
# A gentle start; the last level is a peak after a breath.
offs = planlib.offsets(count, rng, opening=[-2], closing=[-3, 10])
designs = planlib.catalogue()
planner = planlib.Planner(designs, rng)


def extra(d, level, peak, dip):
    k = 0
    if d['look'] == 'gridBars' and level < 20: k += 1000      # no U-bars before level 20
    if d['locks'] > 0 and level < planlib.LOCKS_FROM: k += 1000   # locks from level 30
    if d['look'] == 'hubShape' and level < 40: k += 1000      # outlined webs are for later
    if d['used'] < 1 and d['look'] == 'gridBars': k -= 5      # every U-bar board gets its turn
    return k


plan, fields = [], 0
for i, level in enumerate(range(FIRST, LAST + 1)):
    base = 12 + 18 * (i / (count - 1)) ** 0.9
    target = round(max(10, min(64, base + offs[i])))
    looks, left, counts = planlib.block_state(plan, level, FIRST)
    d = planner.choose(level, target, offs[i], looks, left, fields, 0.4 * count, extra, counts)
    fields += d['spacing'] == 'gridField'
    expr, bombs = planner.add_bombs(level, d, 26)
    plan.append(dict(level=level, target=target, offset=offs[i], expr=expr, look=d['look'], exp=d['exp'], bombs=bombs))

planlib.print_plan(plan)
if '--apply' in sys.argv:
    planlib.apply(plan)
