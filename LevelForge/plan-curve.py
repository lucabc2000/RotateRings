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


targets = [round(max(10, min(64, 12 + 18 * (i / (count - 1)) ** 0.9 + offs[i]))) for i in range(count)]
# Tier-2 peaks aim at what tier-2 boards measure.
targets = [max(t, planlib.tier2_target(FIRST + i)) if planlib.wants_tier2(offs[i], t, FIRST + i) else t for i, t in enumerate(targets)]
planner.tier2_peaks = {FIRST + i for i in range(count) if planlib.wants_tier2(offs[i], targets[i], FIRST + i)}
plan, fields = [], 0
for i, level in enumerate(range(FIRST, LAST + 1)):
    target = targets[i]
    looks, left, counts = planlib.block_state(plan, level, FIRST)
    before_tier2 = i + 1 < count and planlib.wants_tier2(offs[i + 1], targets[i + 1], level + 1)
    d = planner.choose(level, target, offs[i], looks, left, fields, 0.4 * count, extra, counts, before_tier2)
    fields += d['spacing'] == 'gridField'
    expr, bombs = planner.add_bombs(level, d, 26)
    plan.append(dict(level=level, target=target, offset=offs[i], expr=expr, look=d['look'], exp=d['exp'], bombs=bombs,
                     peak=planlib.wants_tier2(offs[i], target, level) and level not in planlib.PICTURE_SLOTS,
                     breather=d['look'] in ('small', 'picture')))

planlib.print_plan(plan)
if '--apply' in sys.argv:
    planlib.apply(plan)
