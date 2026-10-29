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
#     until the owner has played them; a peak whose target a tier-2 board can reach gets one of the
#     designs whose boards are usually tier 2 (TIER2), and the generator then wants a tier-2 board
#     there (`DifficultyCurve.peaks`);
#   - locks: none on dips, one off-peak, two or three only at peaks; the first lock level is the
#     introduction (one lock on a small board);
#   - bombs on knot boards about one level in four, never two levels running;
#   - the chapter ends 50, 100, 150 and 200 keep the boards the owner pinned (MILESTONES), and no level
#     within three of one shares its family or is another web (they are webs); pictures on the reward levels (PICTURE_SLOTS), played as
#     breathers; at most one mirrored free-form knot in twenty levels;
#   - tier-2 peaks aim at what tier-2 boards measure (`tier2_target`), so the late game climbs;
#   - small breathers: every eight to twelve levels, the level right after a peak is a small board
#     (eight to twelve pieces, drawn larger), the most interesting small design; small designs
#     appear nowhere else, and the generator lets interest decide there (`DifficultyCurve.breathers`).
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
# Designs whose boards are usually tier 2 (only the 2-deep bot plans them; six to seven of eight
# seeds). A peak with a target of TIER2_FROM or more gets one of them: a tier-2 board measures 40 and
# up, so lower peaks keep the other designs.
TIER2 = ('hubWeb("hubs-heart", clips: 3...4,', 'hubWeb("hubs-grand", clips: 3...4,', 'hubWeb("hubs-column", clips: 3...4,',
         'hubWeb("hubs-ports", clips: 3...4,', 'hubWeb("hubs-arch", clips: 2...3,')
TIER2_FROM = 38


def tier2_target(level):
    """What a tier-2 board measures at this point of the curve: the TIER2 designs' tier-2 boards
    measure about 44 (Grand) to 56 (Arch); the target climbs through that range."""
    return round(45 + 7 * max(0, level - 60) / 140)


# The chapter ends: the designs whose boards the owner pinned (level-selection.json of the set).
MILESTONES = {50: 'hubWeb("hubs-gem", clips: 2...3, holders: 3, tails: 0.85)',
              100: 'hubWeb("hubs-column", clips: 3...4, holders: 3, tails: 0.85)',
              150: 'hubWeb("hubs-arch", clips: 2...3, holders: 3, tails: 0.85)',
              200: 'hubWeb("hubs-ports", clips: 3...4, holders: 3, bars: 2, tails: 0.85)'}
MILESTONE_DISTANCE = 3
# Reward levels: a picture, with a lock where it stays solvable (LevelForge/pictures.py).
PICTURE_SLOTS = {20: 'picture("key", locks: 1)', 40: 'picture("tree")', 60: 'picture("house")', 80: 'picture("snail", locks: 1)',
                 120: 'picture("lighthouse", locks: 1)', 140: 'picture("anchor", locks: 1)', 160: 'picture("padlock")',
                 180: 'picture("crown", locks: 1)'}
# Mirrored free-form knots: at most one in this many levels.
MIRRORED_FREE_EVERY = 20
# Small breathers: from this level, every SMALL_EVERY levels, on the level after a peak.
SMALL_FROM = 15
SMALL_EVERY = range(8, 13)
SMALL_PIECES = (8, 12)
# The families of the TIER2 designs; the two levels before a tier-2 peak must leave one of them free.
TIER2_SPACINGS = ('gridField', 'hubShape')


def near_milestone(level):
    return any(0 < abs(m - level) <= MILESTONE_DISTANCE for m in MILESTONES)


def wants_tier2(offset, target, level):
    """The TIER2 designs are webs, so a peak beside a chapter end takes another design."""
    return offset >= PEAK and target >= TIER2_FROM and not near_milestone(level)


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
        # Too few valid boards to plan with, unless the level is fixed to it (a pinned end, a picture).
        fixed = expr in MILESTONES.values() or expr in PICTURE_SLOTS.values()
        if (q['valid'] < 3 and not fixed) or any(expr.startswith(x) for x in exclude):
            continue
        look = q['look']
        designs.append(dict(expr=expr, look=look, spacing='gridField' if look == 'hub' else look, exp=q['difficulty'], pieces=q['pieces'],
                            interest=q['interest'], unplanned=q['unplannedShare'], locks=q['locks'], template=q['template'],
                            used=0, web=expr.startswith('hubWeb'), knot=expr.startswith('knot('),
                            breather=look == 'barMaze', intro=expr in INTRO, tier2=expr.startswith(TIER2)))
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
        self.next_small = SMALL_FROM
        self.last_offset = None               # offset of the level before
        self.recent_exprs = []                # (level, expression) of the levels so far
        self.tier2_peaks = set()              # set by the planners: levels that want a tier-2 board
        self.fixed = {level: next(d for d in designs if d['expr'] == expr) for level, expr in {**MILESTONES, **PICTURE_SLOTS}.items()
                      if any(d['expr'] == expr for d in designs)}

    def choose(self, level, target, offset, block_looks, block_left, field_count, field_limit, extra_cost=None, block_counts=None,
               before_tier2=False):
        """before_tier2: the next level is a tier-2 peak (`wants_tier2`)."""
        block_counts = block_counts or {}
        peak, dip = offset >= PEAK, offset < 0
        recent = self.history[-2:]
        if self.next_scene is None:
            self.next_scene = level + self.rng.choice([4, 5, 6])
        # The pinned chapter ends and the pictures are fixed.
        if level in self.fixed:
            d = self.fixed[level]
            d['used'] += 1
            self.last_offset = offset
            self.history.append(d['spacing'])
            self.recent_exprs.append((level, d['expr']))
            return d
        # A small breather right after a peak, when one is due; it stands in for a change of scene.
        small = level >= self.next_small and self.last_offset is not None and self.last_offset >= PEAK and offset < PEAK \
            and level - 1 not in self.fixed and level + 1 not in self.fixed \
            and not any(abs(level - n) <= 3 for n in PICTURE_SLOTS)    # not a second breather beside a picture
        scene = dip and level >= self.next_scene and not small

        def cost(d):
            if small:
                # The most interesting small board with eight to twelve pieces; the target matters little.
                fits = d['look'] == 'small' and SMALL_PIECES[0] <= d['pieces'] <= SMALL_PIECES[1]
                k = (0 if fits else 1000) - 20 * d['interest'] + 0.3 * abs(d['exp'] - target) + 3 * d['used']
            elif scene:
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
            if d['look'] == 'small' and not small: k += 1000
            if d['look'] == 'picture': k += 1000                 # only on the reward levels
            # Not the family of a chapter end within three levels of it, nor another web.
            for m in MILESTONES:
                if 0 < abs(m - level) <= MILESTONE_DISTANCE and m in self.fixed and d['spacing'] == self.fixed[m]['spacing']: k += 1000
            if d['web'] and near_milestone(level): k += 1000
            # Mirrored free-form knots are a rare sight.
            if d['expr'].startswith('freeKnot(') and 'mirror: true' in d['expr'] and any(
                    level - n < MIRRORED_FREE_EVERY and e.startswith('freeKnot(') and 'mirror: true' in e for n, e in self.recent_exprs): k += 1000
            if peak and d['unplanned'] > UNPLANNED_LIMIT: k += 1000
            if peak and d['web']: k -= 8
            if wants_tier2(offset, target, level) and not d['tier2']: k += 1000
            # In the two levels before a tier-2 peak, leave the peak a family it may use: not those of
            # the two levels before it, nor a chapter end's within three levels of it.
            for peak_level in (level + 1, level + 2):
                if peak_level not in self.tier2_peaks:
                    continue
                barred = {self.fixed[m]['spacing'] for m in MILESTONES if m in self.fixed and 0 < abs(m - peak_level) <= MILESTONE_DISTANCE}
                before_peak = {d['spacing']} | (set(self.history[-1:]) if peak_level == level + 1 else set())
                if not set(TIER2_SPACINGS) - barred - before_peak: k += 1000
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
        self.last_offset = offset
        self.recent_exprs.append((level, d['expr']))
        if small:
            self.next_small = level + self.rng.choice(SMALL_EVERY)
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
        return with_bombs(d['expr'], count), count


def with_bombs(expr, count):
    """The design with `bombs:` where Swift wants it: after the arguments before it in `knot(…)` and
    `freeKnot(…)`, before those after it."""
    later = [i for i in (expr.find(f', {name}:') for name in ('locks', 'lockClips', 'mirror', 'mirrorColors', 'holes', 'small',
                                                              'giant', 'dense', 'silhouette', 'anchors')) if i >= 0]
    at = min(later) if later else len(expr) - 1
    return expr[:at] + f', bombs: {count}' + expr[at:]


def block_state(plan, level, first):
    """Looks used so far in this block of ten, the slots left in it including this one, and how
    often each look was used in it."""
    start = ((level - 1) // 10) * 10 + 1
    inside = [p['look'] for p in plan if p['level'] >= max(start, first)]
    return set(inside), start + 10 - level, {look: inside.count(look) for look in inside}


def print_plan(plan):
    for p in plan:
        print(f"// {p['level']} target {p['target']} ({p['offset']:+d}) {p['look']}{'*' if p.get('bombs') else ''}{' ^' if p.get('peak') else ''} usual {p['exp']:.0f}")
    print('targets:', ', '.join(str(p['target']) for p in plan))
    for p in plan:
        print(f"        case {p['level']}: return [{p['expr']}]")


def table():
    swift = open('RotateRings/Model/Generation/Compositions.swift').read()
    return {int(n): e for n, e in re.findall(r'case (\d+): return \[(.*)\]\n', swift)}


def look_of(expr):
    for key in (expr, re.sub(r', bombs: \d+', '', expr)):
        if key in QUALITY:
            return QUALITY[key]['look']
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
    # Tier-2 peaks: this plan's levels replace whatever the table had for them.
    levels = {p['level'] for p in plan}
    for name, flag in (('peaks', 'peak'), ('breathers', 'breather')):
        m = re.search(rf'static let {name}: Set<Int> = \[(.*)\]', curve)
        chosen = {int(x) for x in m.group(1).split(', ') if x} - levels | {p['level'] for p in plan if p.get(flag)}
        curve = curve.replace(m.group(0), f'static let {name}: Set<Int> = [' + ', '.join(str(n) for n in sorted(chosen)) + ']')
    curve = curve.replace('static let onQualityScale = false', 'static let onQualityScale = true')
    open(path, 'w').write(curve)
