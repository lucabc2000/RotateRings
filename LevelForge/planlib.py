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
#     appear nowhere else, and the generator lets interest decide there (`DifficultyCurve.breathers`);
#   - piece count (§16): every level has a piece range next to its target (`piece_range`: a ramp from
#     about 8 pieces at level 11 to the low twenties, a peak heavier and a dip lighter), and a design
#     pays PIECE_COST a piece for leaving it. Through level 15 nothing over OPENING_CAP pieces. A level
#     whose range tops out at LIGHT_MAX is light: the most interesting design that fits wins, as on a
#     breather, and its target is set to what that design measures.
import json, os, random, re

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
# The lock introduction is a small board (nine or twelve rings, interest up to 0.88), which is what
# the opening levels need (§16); it used to wait until level 30.
LOCKS_FROM = 16
# Designs whose boards are usually tier 2 (only the 2-deep bot plans them; six to seven of eight
# seeds). A peak with a target of TIER2_FROM or more gets one of them: a tier-2 board measures 40 and
# up, so lower peaks keep the other designs.
TIER2 = ('hubWeb("hubs-heart", clips: 3...4,', 'hubWeb("hubs-grand", clips: 3...4,', 'hubWeb("hubs-column", clips: 3...4,',
         'hubWeb("hubs-ports", clips: 3...4,', 'hubWeb("hubs-arch", clips: 2...3,',
         # The late game (§17): the huge board's webs, 36-41 pieces, tier-2 boards at about 60.
         'hubWeb("hubs-citadel", clips: 2...3,', 'hubWeb("hubs-tower", clips: 2...3,', 'hubWeb("hubs-bastion", clips: 2...3,')
TIER2_FROM = 38


def tier2_target(level):
    """What a tier-2 board measures at this point of the curve: the TIER2 designs' tier-2 boards
    measure about 44 (Grand) to 56 (Arch); the target climbs through that range to LATE_FROM, then
    (§17) on to TIER2_TOP at 200, what the late designs' tier-2 boards measure."""
    if level > LATE_FROM:
        start = 45 + 7 * (LATE_FROM - 60) / 140
        return round(start + (TIER2_TOP - start) * (level - LATE_FROM) / (200 - LATE_FROM))
    return round(45 + 7 * max(0, level - 60) / 140)


# The late game (§17): the huge board and the designs drawn on it are for levels after LATE_FROM
# only; peak targets climb to TIER2_TOP at 200 (set from the measured late designs).
LATE_FROM = 120
TIER2_TOP = 63
HUGE_LIMIT = 8            # huge webs in 121-200, the two chapter ends included
HUGE_DISTANCE = 15        # the same outline (Citadel, Tower, Bastion) no sooner than this


# The chapter ends: the designs whose boards the owner pinned (level-selection.json of the set).
MILESTONES = {50: 'hubWeb("hubs-gem", clips: 2...3, holders: 3, tails: 0.85)',
              100: 'hubWeb("hubs-column", clips: 3...4, holders: 3, tails: 0.85)',
              # §17: the chapter ends after 120 are the biggest and hardest boards of their chapters.
              150: 'hubWeb("hubs-tower", clips: 2...3, holders: 3, bars: 2, tails: 0.85, huge: true)',
              200: 'hubWeb("hubs-citadel", clips: 2...3, holders: 3, bars: 2, tails: 0.85, huge: true)'}
MILESTONE_DISTANCE = 3
# Reward levels (§16, Step 5): a picture right after a peak, about every thirteen levels, the
# smallest pictures first, each the biggest board in its neighbourhood (LevelForge/pictures.py).
PICTURE_SLOTS = {18: 'picture("cherries", tails: 0)', 33: 'picture("snowman", tails: 0)', 46: 'picture("clock", tails: 0)',
                 68: 'picture("key", tails: 0)', 82: 'picture("lighthouse", tails: 0)', 95: 'picture("balloon", tails: 0)',
                 114: 'picture("snail", tails: 0)', 132: 'picture("anchor", tails: 0)', 143: 'picture("crown", tails: 0)',
                 159: 'picture("house", tails: 0)', 178: 'picture("padlock", tails: 0)', 194: 'picture("tree", tails: 0)'}
# Mirrored free-form knots: at most one in this many levels.
MIRRORED_FREE_EVERY = 20
# Breathers (§16, Step 3): about one level in four is a small board of SMALL_PIECES pieces, the most
# interesting that fits. One is due BREATHER_EVERY levels after the last and is taken on the first
# level after a peak, or at once when BREATHER_FORCE levels have passed without one; never on a peak,
# on a chapter end or beside one. The light levels of the opening count as breathers.
SMALL_FROM = 11
BREATHER_EVERY = (3, 4)
BREATHER_FORCE = 4
SMALL_PIECES = (7, 10)      # a breather has ten pieces at most; the generator holds it to that
# The families of the TIER2 designs; the two levels before a tier-2 peak must leave one of them free.
TIER2_SPACINGS = ('gridField', 'hubShape', 'hugeHub')
# Piece count (§16). The ramp's anchors (level, pieces at the centre of the range), how many pieces a
# point of offset adds (a peak at +15 is about five pieces heavier than the baseline), and the room
# either side of the centre by level.
PIECE_ANCHORS = [(11, 8), (20, 12), (40, 14), (60, 18), (100, 22), (120, 23), (200, 30)]
PIECE_SHIFT = 0.35
PIECE_HALF = ((19, 2), (60, 3), (200, 5))
PIECE_COST = 6            # per piece outside the level's range
# After level 60 size has a wave of its own (Step 4): big boards that are easy to read next to small
# ones that are hard. The same phrases as the difficulty waves, from a fixed seed, SIZE_SCALE pieces
# a point, so a level's size no longer follows its difficulty offset alone.
SIZE_FROM = 61
SIZE_SCALE = 0.6
OPENING_CAP = (15, 12)    # through level 15, no design with more than 12 pieces
LIGHT_MAX = 12            # a range that tops out here makes the level light: interest chooses
# The opening (11–40) is about learning to read boards: level 11 and one of 13–15 are confidence
# boards (tier 0, 6–9 pieces); the other light levels want tier 1; the 3×3 and 3×4 knots and webs
# (SMALL_GRID shapes) at most SMALL_GRID_LIMIT times, U-bars at most twice, no bombs; and the same
# board shape (mask, outline, size) within SHAPE_DISTANCE levels costs SHAPE_COST.
OPENING_LAST = 40
CONFIDENCE_PIECES = (6, 9)
TIER0_SHARE = 0.5
SMALL_GRID = ('nine', 'twelve', 'mini', 'mini12')   # the little gem is another outline
SMALL_GRID_LIMIT = 5      # 4 would leave the breathers no interesting board: at ten pieces only these reach 0.5
UBARS_LIMIT = 2
SHAPE_DISTANCE = 5
SHAPE_COST = 25
SILHOUETTE_DISTANCE = 10  # every outline reads as the same rounded blob: one family, a longer window
BIG_EASY_PIECES = (14, 16) # one big but easy board (tier 0–1) in the opening, so the sawtooth starts early


def shape_of(expr):
    """The board shape a design draws: a grid mask, an outline, a free-form size, a net, a maze."""
    m = re.search(r'"(?:hubs|weave|figure)-([a-z0-9]+)"', expr)
    if m:
        return m.group(1)
    if expr.startswith('freeKnot('):
        rings = re.search(r'rings: (\d+)\.\.\.(\d+)', expr)
        extra = ''.join(f'-{m.group(1)}{m.group(2)}' for m in re.finditer(r'(silhouette|giant|anchors): "?(\w+)"?', expr))
        return f'free{rings.group(1)}-{rings.group(2)}{extra}' + ('-dense' if 'dense: true' in expr else '') + ('-small' if 'small: true' in expr else '')
    m = re.match(r'(maze|cages)\((?:cols|across): (\d+), (?:rows|down): (\d+)', expr)
    if m:
        return f'{m.group(1)}{m.group(2)}x{m.group(3)}'
    m = re.match(r'tangle\(rings: (\d+)\.\.\.(\d+)', expr)
    if m:
        return f'tangle{m.group(1)}-{m.group(2)}'
    return expr.split('(')[0]


def piece_range(level, offset):
    """Pieces a level should have, (low, high): the ramp at this level, shifted by the offset and,
    from SIZE_FROM on, by the size wave."""
    for (a, va), (b, vb) in zip(PIECE_ANCHORS, PIECE_ANCHORS[1:]):
        if level <= b:
            base = va + (vb - va) * (level - a) / (b - a)
            break
    else:
        base = PIECE_ANCHORS[-1][1]
    centre = base + PIECE_SHIFT * offset
    if level >= SIZE_FROM:
        centre += SIZE_SCALE * SIZE_WAVE[level - SIZE_FROM]
    half = next(h for upto, h in PIECE_HALF if level <= upto)
    return max(5, round(centre - half)), max(6, round(centre + half))


def piece_cost(pieces, low, high):
    return PIECE_COST * max(0, low - pieces, pieces - high)


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


SIZE_WAVE = offsets(200 - SIZE_FROM + 1, random.Random(16))


def catalogue(exclude=()):
    designs = []
    for expr, q in sorted(QUALITY.items()):
        # Too few valid boards to plan with, unless the level is fixed to it (a pinned end, a picture).
        fixed = expr in MILESTONES.values() or expr in PICTURE_SLOTS.values()
        if (q['valid'] < 3 and not fixed) or any(expr.startswith(x) for x in exclude):
            continue
        # Of the huge board's designs only the webs carry their size into difficulty (§17); the free
        # knots and grid knots drawn on it were measured and cut.
        if 'huge: true' in expr and not expr.startswith('hubWeb('):
            continue
        look = q['look']
        # The huge board's webs are a family of their own (§17): zoomed out, they read nothing like
        # the grids, so they may follow one.
        if 'huge: true' in expr: look = 'hugeHub'
        designs.append(dict(expr=expr, look=look, spacing='gridField' if look == 'hub' else look, exp=q['difficulty'], pieces=q['pieces'],
                            interest=q['interest'], unplanned=q['unplannedShare'], locks=q['locks'], template=q['template'],
                            used=0, web=expr.startswith('hubWeb'), knot=expr.startswith('knot('),
                            breather=look == 'barMaze', intro=expr in INTRO, tier2=expr.startswith(TIER2),
                            shape=shape_of(expr), tier0=q['tiers'][0] / q['valid'] if q['valid'] else 0,
                            tier=max(range(4), key=lambda t: q['tiers'][t]) if q['valid'] else 0,
                            tier2share=(q['tiers'][2] + q['tiers'][3]) / q['valid'] if q['valid'] else 0))
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
        self.last_breather = 10               # the last breather so far (the tutorial counts)
        self.last_offset = None               # offset of the level before
        self.recent_exprs = []                # (level, expression) of the levels so far
        self.tier2_peaks = set()              # set by the planners: levels that want a tier-2 board
        self.last_light = False               # the level just chosen was light (interest chose)
        self.last_small = False               # it was a scheduled breather
        self.last_range = None                # its piece range
        self.confidence = set()               # set by the planners: levels that want a tier-0 board
        self.big_easy = set()                 # set by the planners: levels that want a big but easy board
        self.fixed = {level: next(d for d in designs if d['expr'] == expr) for level, expr in {**MILESTONES, **PICTURE_SLOTS}.items()
                      if any(d['expr'] == expr for d in designs)}
        # Levels that keep the breather they have (§17): their design is fixed, they count as the
        # breather they are, and no breather is added between them.
        self.keep_breathers = None
        # The huge webs (§17): on six to eight late peaks, never two peaks running, never the same
        # outline within HUGE_DISTANCE levels.
        self.last_peak_look = None

    def choose(self, level, target, offset, block_looks, block_left, field_count, field_limit, extra_cost=None, block_counts=None,
               before_tier2=False):
        """before_tier2: the next level is a tier-2 peak (`wants_tier2`)."""
        block_counts = block_counts or {}
        peak, dip = offset >= PEAK, offset < 0
        recent = self.history[-2:]
        if self.next_scene is None:
            self.next_scene = level + self.rng.choice([4, 5, 6])
        low, high = piece_range(level, offset)
        self.last_range = (low, high)
        # The pinned chapter ends and the pictures are fixed.
        if level in self.fixed:
            d = self.fixed[level]
            d['used'] += 1
            self.last_offset = offset
            if level in self.tier2_peaks or level in MILESTONES: self.last_peak_look = d['look']
            kept = self.keep_breathers is not None and level in self.keep_breathers
            self.last_small = self.last_light = kept
            if kept:
                self.last_range = SMALL_PIECES
                self.last_breather = level
                self.next_small = level + self.rng.choice(BREATHER_EVERY)
            self.history.append(d['spacing'])
            self.recent_exprs.append((level, d['expr']))
            return d
        # A small breather: due and right after a peak, or overdue; it stands in for a change of scene.
        due = level >= self.next_small
        after_peak = self.last_offset is not None and self.last_offset >= PEAK
        allowed = not peak and not any(abs(m - level) <= 1 for m in MILESTONES)
        small = allowed and ((due and after_peak) or level - self.last_breather >= BREATHER_FORCE
                             or (level >= 20 and high <= LIGHT_MAX))   # a dip this deep past the opening is a breather
        if self.keep_breathers is not None:
            small = False                     # the breathers are the kept ones and no other
        if small:
            low, high = SMALL_PIECES
        confidence = level in self.confidence
        if confidence:
            low, high = CONFIDENCE_PIECES
        big_easy = level in self.big_easy
        if big_easy:
            low, high = BIG_EASY_PIECES
        self.last_range = (low, high)
        self.last_small = small
        # A light level (the opening, and every breather): the most interesting design that fits wins.
        light = small or high <= LIGHT_MAX
        self.last_light = light
        opening = level <= OPENING_LAST
        small_grids = sum(1 for n, e in self.recent_exprs if n <= OPENING_LAST and shape_of(e) in SMALL_GRID)
        ubars = sum(1 for n, e in self.recent_exprs if n <= OPENING_LAST and 'uBars:' in e)
        scene = dip and level >= self.next_scene and not small
        # Late in the game a change of scene may be as big as it comes: big boards that are easy to
        # read, next to small ones that are hard (Step 4).
        free_size = scene and level > 60

        def cost(d):
            k = 0 if free_size else piece_cost(d['pieces'], low, high)
            # A late peak may be bigger than its range (size is the point, §17), and a tier-2 peak that
            # falls short of its target is the plateau the owner heard: short costs double.
            if peak and level > LATE_FROM and d['pieces'] > high: k -= piece_cost(d['pieces'], low, high)
            if wants_tier2(offset, target, level) and d['exp'] < target - 3: k += target - 3 - d['exp']
            # After LATE_FROM a change of scene may still be as big as it comes, but not smaller than
            # the ramp (§17: the late game climbs in size).
            if free_size and level > LATE_FROM and d['pieces'] < low: k += PIECE_COST * (low - d['pieces'])
            if level <= OPENING_CAP[0] and d['pieces'] > OPENING_CAP[1]: k += 1000
            if small and d['pieces'] > SMALL_PIECES[1]: k += 1000     # the generator holds a breather to ten pieces
            if big_easy and d['tier2share'] >= 0.5: k += 1000
            if light:
                # The most interesting board that fits the range; the target matters little, and a
                # breather may come round again sooner than other boards.
                k += -20 * d['interest'] + 0.3 * abs(d['exp'] - target) + 1 * d['used']
            elif scene:
                # Only a change of scene will do; closest from below, a little over is fine.
                k += (0 if d['look'] in SCENE else 1000) + max(0, d['exp'] - target) + 0.3 * max(0, target - d['exp']) + 3 * d['used']
                # Scenes take turns: not the family of either of the last two.
                if d['look'] in self.scene_looks[-2:]: k += 15
            else:
                k += abs(d['exp'] - target) + 3 * d['used']
            if scene and light and d['look'] not in SCENE: k += 1000
            # A light level wants a few pieces that fill the screen, not a zoomed-out board; the
            # opening ramp too.
            if (light or level < 20) and ('dense: true' in d['expr'] or 'giant: 176' in d['expr']): k += 1000
            # The huge board is the late game's (§17): on six to eight of its peaks, never two peaks
            # running, never the same outline within HUGE_DISTANCE levels, and only on peaks.
            if d['look'] == 'hugeHub':
                if level <= LATE_FROM or not peak: k += 1000
                if self.last_peak_look == 'hugeHub': k += 1000
                next_peak = min((p for p in self.tier2_peaks | set(MILESTONES) if p > level), default=None)
                if next_peak in MILESTONES and 'huge: true' in MILESTONES[next_peak]: k += 1000
                huge_before = [(n, e) for n, e in self.recent_exprs if 'huge: true' in e]
                if any(level - n <= HUGE_DISTANCE and shape_of(e) == d['shape'] for n, e in huge_before): k += 1000
                if len(huge_before) + sum(1 for m in MILESTONES if m > level and 'huge: true' in MILESTONES[m]) >= HUGE_LIMIT: k += 1000
            # Confidence boards are tier 0; the other light levels want tier 1.
            if confidence and d['tier0'] < TIER0_SHARE: k += 1000
            if light and not confidence and not scene and d['tier0'] >= TIER0_SHARE: k += 15
            # The opening: few grid boards of nine or twelve rings, few U-bars.
            if opening and d['shape'] in SMALL_GRID and small_grids >= SMALL_GRID_LIMIT: k += 1000
            if opening and 'uBars:' in d['expr'] and ubars >= UBARS_LIMIT: k += 1000
            if opening and 'bombs:' in d['expr']: k += 1000
            # The same board shape again soon reads as a repeat, whatever sits on it.
            if any(level - n <= SHAPE_DISTANCE and shape_of(e) == d['shape'] for n, e in self.recent_exprs): k += SHAPE_COST
            if d['look'] == 'shaped' and any(level - n <= SILHOUETTE_DISTANCE and look_of(e) == 'shaped' for n, e in self.recent_exprs): k += SHAPE_COST
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
            if d['look'] == 'small' and not light: k += 1000
            if d['look'] == 'picture': k += 1000                 # only on the reward levels
            # Not the family of a chapter end within three levels of it, nor another web.
            for m in MILESTONES:
                if 0 < abs(m - level) <= MILESTONE_DISTANCE and m in self.fixed and d['spacing'] == self.fixed[m]['spacing']: k += 1000
            if d['web'] and near_milestone(level): k += 1000
            # The very same design again within ten levels reads as a repeat.
            if any(level - n < 10 and e == d['expr'] for n, e in self.recent_exprs): k += 15
            # Mirrored free-form knots are a rare sight.
            if d['expr'].startswith('freeKnot(') and 'mirror: true' in d['expr'] and any(
                    level - n < MIRRORED_FREE_EVERY and e.startswith('freeKnot(') and 'mirror: true' in e for n, e in self.recent_exprs): k += 1000
            if peak and d['unplanned'] > UNPLANNED_LIMIT: k += 1000
            if peak and d['web'] and abs(d['exp'] - target) <= 10: k -= 8
            if wants_tier2(offset, target, level) and not d['tier2']: k += 1000
            # In the two levels before a tier-2 peak, leave the peak a family it may use: not those of
            # the two levels before it, nor a chapter end's within three levels of it.
            for peak_level in (level + 1, level + 2):
                if peak_level not in self.tier2_peaks:
                    continue
                barred = {self.fixed[m]['spacing'] for m in MILESTONES if m in self.fixed and 0 < abs(m - peak_level) <= MILESTONE_DISTANCE}
                before_peak = {d['spacing']} | (set(self.history[-1:]) if peak_level == level + 1 else set())
                spacings = set(TIER2_SPACINGS)
                # A huge web cannot follow a huge peak (§17), so it is no family to leave that peak.
                if self.last_peak_look == 'hugeHub': spacings.discard('hugeHub')
                if not spacings - barred - before_peak: k += 1000
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

        if os.environ.get('PLAN_DEBUG') == str(level):
            for d in sorted(self.designs, key=cost)[:8]:
                print(f"   {cost(d):8.1f}  {d['pieces']:5.1f} pcs  {d['exp']:5.1f}  i{d['interest']:.2f} T{d['tier']}  {d['expr']}")
            print(f"   level {level}: target {target}, offset {offset}, range {low}–{high}, light {light}, small {small}, scene {scene}, recent {recent}, last peak {self.last_peak_look}, tier-2 peak {level in self.tier2_peaks}")
        d = min(self.designs, key=cost)
        d['used'] += 1
        self.last_offset = offset
        if level in self.tier2_peaks: self.last_peak_look = d['look']
        self.recent_exprs.append((level, d['expr']))
        if small or (light and high <= SMALL_PIECES[1]):
            self.last_breather = level
            self.next_small = level + self.rng.choice(BREATHER_EVERY)
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


def light_target(d, target):
    """A light level's target: what its design measures, so the generator's band sits on it."""
    return round(d['exp'])


def print_blocks(plan, first=None):
    """Per block of twenty: median usual pieces, mean target, the three highest targets, tier-2 peaks."""
    import statistics as st
    first = first or plan[0]['level']
    print('block     pieces  target  top-3           tier-2')
    for a in range(first, plan[-1]['level'] + 1, 20):
        block = [p for p in plan if a <= p['level'] < a + 20]
        if not block:
            continue
        top = sorted((p['target'] for p in block), reverse=True)[:3]
        print(f"{block[0]['level']:>3}-{block[-1]['level']:<3}  {int(st.median(p['pieces'] for p in block)):>6}  {st.mean(p['target'] for p in block):6.1f}  "
              f"{str(top):<15} {sum(1 for p in block if p.get('peak'))}")


def print_plan(plan):
    for p in plan:
        pieces = f"  pieces {p['pieces']:.0f} of {p['range'][0]}–{p['range'][1]}" if 'range' in p else ''
        print(f"// {p['level']} target {p['target']} ({p['offset']:+d}) {p['look']}{'*' if p.get('bombs') else ''}{' ^' if p.get('peak') else ''}"
              f"{' light' if p.get('light') else ''} usual {p['exp']:.0f}{pieces}")
    print('targets:', ', '.join(str(p['target']) for p in plan))
    for p in plan:
        print(f"        case {p['level']}: return [{p['expr']}]")


def median_low(values):
    s = sorted(values)
    return s[(len(s) - 1) // 2] if s else None


def print_pacing(plan):
    """The pacing targets of LevelForge/pacing_check.py read off the plan, from each design's usual
    piece count (a built board differs by a piece or two). Only what the plan's levels can say."""
    pieces = {p['level']: round(p['pieces']) for p in plan}
    levels = sorted(pieces)
    first, last = levels[0], levels[-1]
    breathers = [n for n in levels if pieces[n] <= 10]
    gaps = [b - a for a, b in zip([first - 1] + breathers, breathers + [last + 1])]
    pics = [n for n in levels if n in PICTURE_SLOTS]
    ratios = []
    for n in pics:
        around = [pieces[k] for k in range(n - 5, n + 6) if k != n and k in pieces]
        if around: ratios.append(pieces[n] / median_low(around))
    lines = []
    if first <= 11: lines.append(('median pieces 11–20', median_low([pieces[n] for n in range(11, 21) if n in pieces]), (7, 11)))
    if first <= 21 and last >= 40: lines.append(('median pieces 21–40', median_low([pieces[n] for n in range(21, 41) if n in pieces]), (11, 15)))
    if first <= 11: lines.append(('most pieces 11–15', max(pieces[n] for n in range(11, 16) if n in pieces), (0, 12)))
    lines.append((f'breathers (≤10 pieces) {first}–{last}', round(len(breathers) / len(levels), 2), (0.25, 1)))
    lines.append((f'longest gap between breathers {first}–{last}', max(gaps), (0, 10 if first < 100 else 20)))
    late = [pieces[n] for n in levels if n > 60]
    if len(late) >= 10:
        mean = sum(late) / len(late)
        lines.append((f'size spread after 60 (cv)', round((sum((x - mean) ** 2 for x in late) / len(late)) ** 0.5 / mean, 2), (0.4, 9.9)))
    if ratios:
        lines.append(('picture ratio, min', round(min(ratios), 2), (1, 99)))
        lines.append(('picture ratio, median', round(median_low(ratios), 2), (1.5, 99)))
    print(f'// pacing of the plan ({first}–{last}), from usual piece counts:')
    for name, value, (lo, hi) in lines:
        print(f"//   {'PASS' if lo <= value <= hi else 'FAIL'}  {name:44s} {value!s:>6}   target {lo}–{hi}")
    by_level = {p['level']: p for p in plan}
    print('//   breathers (interest, tier):', ', '.join(f"{n} ({by_level[n].get('interest', 0):.2f} T{by_level[n].get('tier', 0)})" for n in breathers))
    good = sum(1 for n in breathers if by_level[n].get('interest', 0) >= 0.5)
    print(f'//   breathers with interest ≥ 0.5: {good} of {len(breathers)}')


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
