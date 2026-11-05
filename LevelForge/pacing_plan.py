# The pacing targets of pacing_check.py read off the plan in Compositions.templates (every level's
# design and its usual piece count, interest and tier from design-quality.json), before anything is
# generated. LEVEL-DESIGN.md §16.
#
#   python3 LevelForge/pacing_plan.py [FIRST-LAST] [--pictures N]   (N: assume every picture has N pieces)
import re, sys
sys.path.insert(0, 'LevelForge')
import planlib

pictures = int(sys.argv[sys.argv.index('--pictures') + 1]) if '--pictures' in sys.argv else None
args = [a for a in sys.argv[1:] if '-' in a and not a.startswith('--')]
first, last = (int(x) for x in args[0].split('-')) if args else (11, 200)
plan = []
for level, expr in sorted(planlib.table().items()):
    if not first <= level <= last:
        continue
    key = re.sub(r', bombs: \d+', '', expr)
    q = planlib.QUALITY.get(key) or planlib.QUALITY.get(expr)
    if q is None:
        print(f'// {level}: {expr} is not in design-quality.json')
        continue
    plan.append(dict(level=level, pieces=pictures if pictures and expr.startswith('picture(') else q['pieces'], interest=q['interest'], tier=max(range(4), key=lambda t: q['tiers'][t]) if q['valid'] else 0))
planlib.print_pacing(plan)
