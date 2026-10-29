# Shared by plan-curve.py (11-100) and plan-chapter.py (101-200): the design catalogue with what each
# design measured (LevelForge/design-quality.json, written by `forge designs`), the waves of the
# curve, and the rules for choosing a design per level (LEVEL-DESIGN.md §15).
#
# Targets are on the scale of `LevelQuality.difficulty` (tier, moves, setup depth), not the legacy
# score. Each level gets the design whose usual difficulty is closest to its target, subject to:
#   - look families (`Look` in Looks.swift): never the same family within three levels (a web on a
#     rectangle counts as a grid field), at least five families in every block of ten, grid fields
#     at most 40 % of a chapter;
#   - mazes and cages only on dips (breathers and scene changes), never at peaks; every five to
#     eight levels a dip is a change of scene (maze, cage, figure, giant ring, free-form board);
#   - webs favoured at peaks; designs that are often unplanned (no bot plans them) never at peaks
#     until the owner has played them;
#   - locks: none on dips, one off-peak, two or three only at peaks; the first lock level is the
#     introduction (one lock on a small board);
#   - bombs on knot boards about one level in four, never two levels running.
import json, random, re

QUALITY = json.load(open('LevelForge/design-quality.json'))

# Waves: phrases of four to seven levels that build and let go (LEVEL-DESIGN.md §10), in points of
# the legacy score; scaled to the new one by OFFSET_SCALE.
PHRASES = [[-3, 3, 9, -10], [0, 6, -4, 12, -8, -1], [-11, 1, 5, 3, 14, -6], [3, -5, 8, 10, -12], [-2, 4, -9, 7],
           [5, -2, 2, 11, -3, -10, 6], [-6, 8, -1, 4, 15, -9], [2, 9, -7, -2, 6, 12, -13], [-4, 0, 7, -11, 10]]
OFFSET_SCALE = 1.0
PEAK = 6          # offsets (new scale) at or above this are peaks
# Breathers and changes of scene: every five to eight levels, on a dip, a board from these
# families, as light as it comes (they measure far below every target past the first levels).
SCENE = ('barMaze', 'figure', 'giant', 'freeform')
UNPLANNED_LIMIT = 0.5
INTRO = ('knot("hubs-twelve", holders: 2, locks: 1)', 'knot("hubs-nine", holders: 2, locks: 1)')
LOCKS_FROM = 30


def offsets(count, rng, opening=(), closing=()):
    result, last = [], None
    while len(result) < count:
        p = rng.choice([q for q in PHRASES if q is not last]); last = p
        result += [round((o + rng.choice([-2, -1, 0, 1, 2])) * OFFSET_SCALE) for o in p]
    result = result[:count]
    result[:len(opening)] = opening
    if closing:
        result[-len(closing):] = closing
    return result


def catalogue(exclude=()):
    designs = []
    for expr, q in sorted(QUALITY.items()):
        if q['valid'] < 3 or any(expr.startswith(x) for x in exclude):
            continue
        look = q['look']
        designs.append(dict(expr=expr, look=look, spacing='gridField' if look == 'hub' else look, exp=q['difficulty'],
                            interest=q['interest'], unplanned=q['unplannedShare'], locks=q['locks'], template=q['template'],
                            used=0, web=expr.startswith('hubWeb'), knot=expr.startswith('knot('),
                            breather=look == 'barMaze', intro=expr in INTRO))
    return designs


def bombable(d):
    return d['knot'] and d['locks'] == 0 and re.search(r'"hubs-(field|tall|column|grand|twelve)"', d['expr']) is not None


class Planner:
    """Chooses one design per level, carrying the look history across calls (and chapters)."""

    def __init__(self, designs, rng, history=(), lock_intro_done=False):
        self.designs, self.rng = designs, rng
        self.history = list(history)          # spacing looks of the levels before, oldest first
        self.lock_intro_done = lock_intro_done
        self.next_bomb = None
        self.next_scene = None
        self.scene_looks = []                 # families of the changes of scene so far

    def choose(self, level, target, offset, block_looks, block_left, field_count, field_limit, extra_cost=None, block_counts=None):
        block_counts = block_counts or {}
        peak, dip = offset >= PEAK, offset < 0
        recent = self.history[-2:]
        if self.next_scene is None:
            self.next_scene = level + self.rng.choice([4, 5, 6])
        scene = dip and level >= self.next_scene

        def cost(d):
            if scene:
                # Only a change of scene will do; closest from below, a little over is fine.
                k = (0 if d['look'] in SCENE else 1000) + max(0, d['exp'] - target) + 0.3 * max(0, target - d['exp']) + 3 * d['used']
                # Scenes take turns: not the family of either of the last two.
                if d['look'] in self.scene_looks[-2:]: k += 15
            else:
                k = abs(d['exp'] - target) + 3 * d['used']
            # Look families.
            if d['spacing'] in recent: k += 1000
            # Five families a block: a new one is welcome early, and a family already used three
            # times in the block is too many, so the block's last levels are not forced into a poor fit.
            if d['look'] not in block_looks and len(block_looks) < 5: k -= 8
            if d['look'] in block_looks and len(block_looks) + block_left - 1 < 5: k += 1000
            if block_counts.get(d['look'], 0) >= 3: k += 40
            if d['spacing'] == 'gridField' and field_count + 1 > field_limit: k += 60
            # Breathers and peaks.
            if d['breather'] and not dip: k += 1000
            if peak and d['unplanned'] > UNPLANNED_LIMIT: k += 1000
            if peak and d['web']: k -= 8
            # Locks: none on dips, two or three only at peaks, the introduction first.
            if d['locks'] > 0:
                if dip: k += 1000
                if d['locks'] >= 2 and not peak: k += 1000
                if not self.lock_intro_done and not d['intro']: k += 1000
                if self.lock_intro_done and d['intro']: k += 1000
                # The introduction comes once locks are allowed, on the first level that is no dip.
                if d['intro'] and not self.lock_intro_done and level >= LOCKS_FROM and not dip: k -= 25
                if not d['intro'] and not dip: k -= 3
            if extra_cost:
                k += extra_cost(d, level, peak, dip)
            return k + self.rng.random()

        d = min(self.designs, key=cost)
        d['used'] += 1
        if scene:
            self.next_scene = level + self.rng.choice([5, 6, 7, 8])
            self.scene_looks.append(d['look'])
        if d['intro']:
            self.lock_intro_done = True
        self.history.append(d['spacing'])
        return d

    def add_bombs(self, level, d, first_level, fatal_from=60):
        """Bombs: about one level in four, never two levels running, only on knot boards they suit."""
        if self.next_bomb is None:
            self.next_bomb = first_level
        if level < self.next_bomb or not bombable(d):
            return d['expr'], 0
        count = 2 if level >= 70 and self.rng.random() < 0.5 else 1
        self.next_bomb = level + self.rng.choice([3, 3, 4, 4, 5])
        return d['expr'][:-1] + f', bombs: {count})', count


def block_state(plan, level, first):
    """Looks used so far in this block of ten, the slots left in it including this one, and how
    often each look was used in it."""
    start = ((level - 1) // 10) * 10 + 1
    inside = [p['look'] for p in plan if p['level'] >= max(start, first)]
    return set(inside), start + 10 - level, {look: inside.count(look) for look in inside}


def print_plan(plan):
    for p in plan:
        print(f"// {p['level']} target {p['target']} ({p['offset']:+d}) {p['look']}{'*' if p.get('bombs') else ''} usual {p['exp']:.0f}")
    print('targets:', ', '.join(str(p['target']) for p in plan))
    for p in plan:
        print(f"        case {p['level']}: return [{p['expr']}]")


def table():
    swift = open('RotateRings/Model/Generation/Compositions.swift').read()
    return {int(n): e for n, e in re.findall(r'case (\d+): return \[(.*)\]\n', swift)}


def look_of(expr):
    base = re.sub(r', bombs: \d+', '', expr)
    if base in QUALITY:
        return QUALITY[base]['look']
    return 'gridField'


def apply(plan):
    """Writes the plan into Compositions.templates and DifficultyCurve.targets (on the new scale)."""
    path = 'RotateRings/Model/Generation/Compositions.swift'
    swift = open(path).read()
    for p in plan:
        swift, n = re.subn(rf'        case {p["level"]}: return \[.*\]\n', f'        case {p["level"]}: return [{p["expr"]}]\n', swift)
        assert n == 1, p['level']
    open(path, 'w').write(swift)
    path = 'RotateRings/Model/Generation/DifficultyCurve.swift'
    curve = open(path).read()
    m = re.search(r'static let targets: \[Double\] = \[(.*)\]', curve)
    targets = [float(x) for x in m.group(1).split(', ')]
    for p in plan:
        targets[p['level'] - 11] = p['target']
    curve = curve.replace(m.group(0), 'static let targets: [Double] = [' + ', '.join(f'{t:g}' for t in targets) + ']')
    curve = curve.replace('static let onQualityScale = false', 'static let onQualityScale = true')
    open(path, 'w').write(curve)
