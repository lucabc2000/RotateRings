# Writes RotateRings/Model/Generation/DesignCatalogue.swift: every design the planners may choose,
# as the exact expression text they write into `Compositions.templates` next to the design itself,
# so `forge designs` can measure each one under the planners' own key.
#
#   python3 LevelForge/catalogue.py
#
# The list: every design in the current table (bombs stripped: the planners add them), the designs
# the planners offered before (chapter-trial-scores.json, the measured snapshot, the catalogue as it
# stands), and the new ones of LEVEL-DESIGN.md §15 (outlined webs, locks, the lock introduction,
# mirrored knots, silhouettes and anchors, hole patterns, small breathers).
import json, re

swift = open('RotateRings/Model/Generation/Compositions.swift').read()
table = {int(n): e for n, e in re.findall(r'case (\d+): return \[(.*)\]\n', swift)}
exprs = set(re.sub(r', bombs: \d+', '', e) for e in table.values())
exprs |= set(json.load(open('LevelForge/chapter-trial-scores.json')))
exprs |= set(json.load(open('LevelForge/chapter-measured-snapshot.json')))
# The designs already in the catalogue stay (the first catalogue also took plan-curve.py's old list).
try:
    current = open('RotateRings/Model/Generation/DesignCatalogue.swift').read()
    exprs |= {m.replace('\\"', '"').replace('\\\\', '\\') for m in re.findall(r'Design\(expr: "((?:[^"\\]|\\.)*)"', current)}
except FileNotFoundError:
    pass

NEW = []
# Webs with an outline of their own (§15, Step 1b).
for mask in ['gem', 'cross', 'arch', 'hourglass', 'heart', 'frame']:
    for clips in ['3...4', '2...3']:
        NEW.append(f'hubWeb("hubs-{mask}", clips: {clips}, holders: 3, tails: 0.85)')
# Webs on the tall field with fewer clips per hub: fewer unplanned boards.
NEW.append('hubWeb("hubs-tall", clips: 2...3, holders: 3, tails: 0.85)')
NEW.append('hubWeb("hubs-field", clips: 2...3, holders: 3, tails: 0.85)')
# Locks: the introduction (one lock on a small board), then locks on the knots.
NEW.append('knot("hubs-twelve", holders: 2, locks: 1)')
NEW.append('knot("hubs-nine", holders: 2, locks: 1)')
for e in sorted(exprs):
    m = re.fullmatch(r'knot\("hubs-(twelve|grand|column|field|tall|gaps|sieve|final)", holders: (\d)(, tails: [0-9.]+)?\)', e)
    if m:
        for locks in (1, 2, 3):
            NEW.append(e[:-1] + f', locks: {locks})')
# Mirror images (§15, Step 2): every knot without locks and every free-form knot, mirrored left to right.
for e in sorted(exprs):
    if (e.startswith('knot(') and 'locks:' not in e or e.startswith('freeKnot(')) and 'mirror:' not in e \
            and 'silhouette:' not in e and 'anchors:' not in e and 'holes:' not in e and 'small:' not in e:
        NEW.append(e[:-1] + ', mirror: true)')
# Free-form knots inside an outline, and around large anchor rings (§15, Step 3). Mirrored too where
# the outline is symmetric.
SYMMETRIC = ('circle', 'donut', 'heart', 'diamond', 'arch')
for sil in ('circle', 'donut', 'scurve', 'crescent', 'heart', 'diamond', 'arch'):
    # Arch and crescent are bands about one ring wide on the standard board: only the large one.
    if sil not in ('arch', 'crescent'):
        NEW.append(f'freeKnot(rings: 7...12, holders: 3, tails: 0.4, silhouette: "{sil}")')
    NEW.append(f'freeKnot(rings: 10...16, holders: 3, tails: 0.4, dense: true, silhouette: "{sil}")')
    if sil in SYMMETRIC and sil != 'arch':
        NEW.append(f'freeKnot(rings: 6...10, holders: 3, tails: 0.4, mirror: true, silhouette: "{sil}")')
NEW.append('freeKnot(rings: 7...12, holders: 3, tails: 0.4, silhouette: "circle", anchors: 1)')
NEW.append('freeKnot(rings: 7...12, holders: 3, tails: 0.4, silhouette: "diamond", anchors: 1)')
NEW.append('freeKnot(rings: 6...10, holders: 3, tails: 0.4, mirror: true, silhouette: "heart", anchors: 2)')
NEW.append('freeKnot(rings: 14...20, holders: 3, tails: 0.4, anchors: 1)')
NEW.append('freeKnot(rings: 14...20, holders: 3, tails: 0.4, anchors: 2)')
NEW.append('freeKnot(rings: 12...18, holders: 3, tails: 0.4, mirror: true, anchors: 2)')
# Holes with intent in grid knots (§15, Step 4): every pattern on the plain fields, a few on the big
# rings, and mirrored where the pattern is symmetric.
for shape in ('field', 'tall'):
    for pattern in ('cross', 'center', 'diagonal', 'checker', 'frame', 'sieve'):
        NEW.append(f'knot("hubs-{shape}", holders: 3, bars: 3, tails: 0.4, holes: "{pattern}")')
    for pattern in ('cross', 'center', 'frame'):
        NEW.append(f'knot("hubs-{shape}", holders: 3, bars: 3, tails: 0.4, mirror: true, holes: "{pattern}")')
for shape, holders in (('grand', 2), ('column', 3), ('twelve', 2)):
    for pattern in ('center', 'frame', 'cross'):
        NEW.append(f'knot("hubs-{shape}", holders: {holders}, bars: 2, holes: "{pattern}")')
# Small breathers (§15, Step 5): eight to twelve pieces on the small board, drawn larger.
NEW += ['knot("hubs-mini", holders: 2, small: true)', 'knot("hubs-mini", holders: 2, tails: 0.4, small: true)',
        'knot("hubs-mini", holders: 2, bars: 1, small: true)', 'knot("hubs-mini", holders: 2, locks: 1, small: true)',
        'knot("hubs-mini12", holders: 2, small: true)', 'knot("hubs-mini12", holders: 2, tails: 0.4, small: true)',
        'knot("hubs-mini12", holders: 2, mirror: true, small: true)', 'knot("hubs-minigem", holders: 2, small: true)',
        'knot("hubs-minigem", holders: 2, tails: 0.4, mirror: true, small: true)',
        'hubWeb("hubs-mini", clips: 2...3, holders: 3, tails: 0.85, small: true)', 'hubWeb("hubs-mini12", clips: 2...3, holders: 3, small: true)',
        'freeKnot(rings: 8...12, holders: 3, tails: 0.4, small: true)', 'freeKnot(rings: 8...12, holders: 3, tails: 0.4, mirror: true, small: true)']
# Pictures for the reward levels (§15, Step 6), as the planner writes them (planlib.PICTURE_SLOTS).
NEW += ['picture("key", locks: 1)', 'picture("tree")', 'picture("house")', 'picture("snail", locks: 1)',
        'picture("lighthouse", locks: 1)', 'picture("anchor", locks: 1)', 'picture("padlock")', 'picture("crown", locks: 1)']
exprs |= set(NEW)
# The designs of Steps 3 and 5 come only from the lists above, so retuned ones replace the old.
exprs = {e for e in exprs if e in NEW or not any(k in e for k in ('silhouette:', 'anchors:', 'small:', 'picture('))}

def locks(e):
    m = re.search(r'locks: (\d+)', e)
    return int(m.group(1)) if m else 0

lines = []
for e in sorted(exprs):
    text = e.replace('\\', '\\\\').replace('"', '\\"')
    lines.append(f'            Design(expr: "{text}", locks: {locks(e)}, template: {e}),')
out = f'''//
//  DesignCatalogue.swift
//  RotateRings
//
//  Generated by LevelForge/catalogue.py; do not edit by hand. Every design the planners may choose,
//  under the exact expression they write into `Compositions.templates`, so `forge designs` can
//  measure each one under that key (LevelForge/design-quality.json, LEVEL-DESIGN.md §15).
//

import Foundation

extension Compositions {{
    struct Design {{
        let expr: String
        /// Locks in the design (`Knot.Options.locks`).
        let locks: Int
        let template: LevelTemplate
    }}

    static var catalogue: [Design] {{
        let lock = 1...4
        return [
{chr(10).join(lines)}
        ]
    }}
}}
'''
open('RotateRings/Model/Generation/DesignCatalogue.swift', 'w').write(out)
print(len(lines), 'designs,', len(NEW), 'new')
