# Pictures for the reward levels 20, 40, ..., 180 (LEVEL-DESIGN.md §15, Step 6), all drawn here
# from rings a stem apart along the 45° lattice, so the builder can clip neighbours together.
# Writes one JSON file per picture into LevelForge/pictures/ (the format of `Picture`) and compiles
# them into RotateRings/Model/Generation/PictureLibrary.swift.
#
#   python3 LevelForge/pictures.py
#
# To change a picture, edit its function here (or its JSON file, then run with --from-json to
# compile the JSON files as they are). Coordinates: board units from the centre, y up; the
# standard board leaves about ±146 × ±286 for rings, the large one ±182 × ±350.
import json, math, os, re, sys

STEM = 18
OUT = 'LevelForge/pictures'


class Pic:
    def __init__(self, name, title, board=None, clips=None):
        self.name, self.title, self.board, self.clips = name, title, board, clips
        self.rings, self.bars = [], []

    def ring(self, x, y, r, closed=False, gap=None, color=None):
        ring = dict(x=x, y=y, r=r)
        if closed: ring['closed'] = True
        if gap is not None: ring['gap'] = gap
        if color: ring['color'] = color
        self.rings.append(ring)
        return len(self.rings) - 1

    def at(self, i, degrees, r, **kw):
        """A ring of radius r a stem from ring i, along `degrees`."""
        base = self.rings[i]
        d = base['r'] + r + STEM
        a = math.radians(degrees)
        return self.ring(base['x'] + d * math.cos(a), base['y'] + d * math.sin(a), r, **kw)

    def mirror(self, i):
        """The mirror image of ring i about the vertical axis."""
        ring = self.rings[i]
        gap = ring.get('gap')
        return self.ring(-ring['x'], ring['y'], ring['r'], ring.get('closed', False), None if gap is None else (180 - gap) % 360,
                         ring.get('color'))

    def walk(self, i, *steps, r=24, color=None):
        """A line of rings from ring i, one per direction in `steps`; returns their indices."""
        out = []
        for degrees in steps:
            i = self.at(i, degrees, r, color=color)
            out.append(i)
        return out

    def bar(self, i, degrees, length=None, stop=None, color=None):
        """A line: a bar poking into ring i along `degrees`, `length` long or reaching to ring `stop`."""
        bar = dict(ring=i, degrees=degrees)
        if length is not None: bar['length'] = length
        if stop is not None: bar['stop'] = stop
        if color: bar['color'] = color
        self.bars.append(bar)

    def ubar(self, a, b, degrees, length=46, color=None):
        """A U-bar with its arms in the gaps of rings a and b, its crossbar `length` beyond."""
        bar = dict(rings=[a, b], degrees=degrees, length=length)
        if color: bar['color'] = color
        self.bars.append(bar)

    def art(self, rows, legend, pitch=78):
        """Rings from a drawing: one character per cell of a square lattice `pitch` apart, the top
        row first; `legend` maps a character to a colour, or to (radius, colour). Returns the ring
        index per (column, row). A ring in a straight run (held on one side, holding on the other) or
        with three links needs a gap wide enough for a holder's clip to swing out, which only fits
        from radius 30 up; a leaf or a corner ring can be 24, and the builder moves it a stem from
        its neighbour. Returns the ring index per (column, row)."""
        height = len(rows)
        cells = {(col, row) for row, line in enumerate(rows) for col, char in enumerate(line) if char in legend}
        links = {cell: [(cell[0] + dx, cell[1] + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if (cell[0] + dx, cell[1] + dy) in cells]
                 for cell in cells}
        self.cells = {}
        for row, line in enumerate(rows):
            for col, char in enumerate(line):
                if char not in legend:
                    continue
                spec = legend[char]
                near = links[(col, row)]
                straight = any((2 * col - a[0], 2 * row - a[1]) in near for a in near)
                # Leaves and corners are 24: two of them side by side are then 30 apart, which the
                # builder still moves together (at 34 it no longer does).
                r, color = spec if isinstance(spec, tuple) else (30 if len(near) >= 3 or straight else 24, spec)
                self.cells[(col, row)] = self.ring(col * pitch, (height - 1 - row) * pitch, r, color=color)
        # What the builder needs besides (LEVEL-DESIGN.md §16, Step 5): every ring a lattice
        # neighbour; a ring with four is closed, and two closed rings cannot clip, so no two side by side.
        for cell, near in links.items():
            if not near:
                print(f'{self.name}: ring at {cell} has no neighbour')
            if len(near) == 4 and any(len(links[n]) == 4 for n in near):
                print(f'{self.name}: rings at {cell} and a neighbour both have four links')
        self.links, self.pitch = links, pitch
        return self.cells

    def line(self, cell, degrees, length=None, stop=None, color=None):
        """A bar as a line out of the ring at `cell`: the ring must have one link, opposite the bar,
        and the cells the bar runs through must be empty (a stop ring ends it)."""
        k = round(degrees / 45) % 8
        dx, dy = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)][k]
        dy = -dy    # rows count downwards
        near = self.links[cell]
        if len(near) != 1 or near[0] != (cell[0] - dx, cell[1] - dy):
            print(f'{self.name}: the bar at {cell} needs a single link opposite it, has {near}')
        r = self.rings[self.cells[cell]]['r']
        if stop is None and length < 46:
            print(f'{self.name}: the bar at {cell} is {length} long; a free bar slides 44 at least')
        reach = r - 10 + (length or 0) + 45      # where the bar's end gets to when it slides out
        for step in range(1, 4):
            c = (cell[0] + dx * step, cell[1] + dy * step)
            if c in self.cells:
                if stop is not None and self.cells[c] == stop:
                    break
                if stop is not None or step * self.pitch - self.rings[self.cells[c]]['r'] < reach + 14:
                    print(f'{self.name}: the bar at {cell} runs into the ring at {c}')
                break
        self.bar(self.cells[cell], degrees, length=length, stop=stop, color=color)


    def finish(self):
        """Centres the drawing on the board and rounds the numbers."""
        xs = [v for g in self.rings for v in (g['x'] - g['r'], g['x'] + g['r'])]
        ys = [v for g in self.rings for v in (g['y'] - g['r'], g['y'] + g['r'])]
        # A free bar's end, slid out, counts too (the builder wants it inside the margins).
        for bar in self.bars:
            if 'length' in bar and 'ring' in bar:
                g = self.rings[bar['ring']]
                reach = g['r'] + bar['length'] + 50
                xs.append(g['x'] + reach * math.cos(math.radians(bar['degrees'])))
                ys.append(g['y'] + reach * math.sin(math.radians(bar['degrees'])))
        dx, dy = -(min(xs) + max(xs)) / 2, -(min(ys) + max(ys)) / 2
        for g in self.rings:
            g['x'] = round(g['x'] + dx, 2)
            g['y'] = round(g['y'] + dy, 2)
        # Rings must not touch: a stem apart at least where they are neighbours, clear otherwise.
        for a in range(len(self.rings)):
            for b in range(a + 1, len(self.rings)):
                ra, rb = self.rings[a], self.rings[b]
                gap = math.hypot(ra['x'] - rb['x'], ra['y'] - rb['y']) - ra['r'] - rb['r']
                if gap < 10:
                    print(f'{self.name}: rings {a} and {b} are {gap:.0f} apart')
                # Neighbours sit up to 34 apart along the lattice (the builder moves them a stem
                # apart); anything closer than 34 off the lattice would be snapped the wrong way.
                angle = math.degrees(math.atan2(rb['y'] - ra['y'], rb['x'] - ra['x'])) % 45
                if 10 <= gap <= 34 and min(angle, 45 - angle) > 2:
                    print(f'{self.name}: rings {a} and {b} are {gap:.0f} apart at {angle:.0f}° off the lattice')
        # Room for rings inside the margins (and a tail's reach): standard, else the large board.
        half_w, half_h = (max(xs) - min(xs)) / 2, (max(ys) - min(ys)) / 2
        if not self.board and (half_w > 144 or half_h > 284):
            self.board = 'large'
        if self.board != 'huge' and (half_w > 180 or half_h > 348):
            self.board = 'huge'
        if half_w > 234 or half_h > 444:
            print(f'{self.name}: {2 * half_w:.0f} x {2 * half_h:.0f} does not fit even the huge board')
        out = dict(name=self.name, title=self.title, rings=self.rings)
        if self.bars: out['bars'] = self.bars
        if self.board: out['board'] = self.board
        if self.clips: out['clips'] = self.clips
        return out



# Colours: yellow, coral, sky, mint, purple (`ForgeRules.colors`). The huge board holds 6 × 11
# cells, the large one 4 × 9, the standard one 3 × 7. A free bar slides 46 at least and needs three
# empty cells; a bar to a stop ring may be shorter.


def key():
    p = Pic('key', 'Key', clips=3)
    p.art([' YYY',
           ' Y Y',
           ' YYY',
           '  Y ',
           '  Y ',
           '  YY',
           '  Y ',
           '  YY'], {'Y': 'yellow'})
    return p


def wheel():
    p = Pic('wheel', 'Ferris wheel', clips=3)
    p.art([' SCS ',
           'S P S',
           'CPYPC',
           'S P S',
           ' SCS ',
           ' Y Y '], {'S': 'sky', 'C': 'coral', 'P': 'purple', 'Y': 'yellow'})
    p.line((1, 5), 270, length=46, color='yellow')         # the stand
    p.line((3, 5), 270, length=46, color='yellow')
    return p


def snowman():
    """Three stacked large rings; the middle one is closed (it holds the mittens as well)."""
    p = Pic('snowman', 'Snowman', clips=3)
    base = p.ring(0, 0, 56, color='sky')
    middle = p.at(base, 90, 42, color='sky')
    head = p.at(middle, 90, 34, color='sky')
    hat = p.at(head, 90, 20, color='purple')
    p.bar(head, 0, length=46, color='coral')                 # nose
    for degrees in (180, 0):
        mitten = p.at(middle, degrees, 20, color='yellow')
        p.bar(mitten, degrees, length=52, color='yellow')    # arms
    p.at(base, 225, 20, color='sky'); p.at(base, 315, 20, color='sky')   # snow
    return p


def cherries():
    """Two large fruit side by side, bar stems down from the leaves."""
    p = Pic('cherries', 'Cherries', clips=3)
    left = p.ring(-57, 0, 48, color='coral')
    right = p.ring(57, 0, 48, color='coral')
    stalk_left = p.ring(-57, 232, 24, color='mint')
    stalk_right = p.ring(57, 232, 24, color='mint')
    leaf_left = p.ring(-57, 170, 22, color='mint')
    leaf_right = p.ring(57, 170, 22, color='mint')
    p.at(stalk_left, 90, 22, color='mint')
    p.bar(leaf_left, 270, stop=left, color='mint')
    p.bar(leaf_right, 270, stop=right, color='mint')
    return p


def padlock():
    p = Pic('padlock', 'Padlock', clips=3)
    p.art(['YYYYY',
           'Y   Y',
           'Y   Y',
           'Y   Y',
           'CCCCC',
           'C P C',
           'C P C',
           'C   C',
           'C   C',
           'CCCCC'], {'Y': 'yellow', 'C': 'coral', 'P': 'purple'})
    p.line((2, 6), 270, stop=p.cells[(2, 9)], color='purple')   # the keyhole's slot
    return p


def house():
    p = Pic('house', 'House', clips=3)
    p.art(['  C  ',
           ' CCC ',
           'CC CC',
           'SY YS',
           'S   S',
           'SY YS',
           'S   S',
           'S Y S',
           'SSSSS',
           'M M M'], {'C': 'coral', 'S': 'sky', 'Y': 'yellow', 'M': 'mint'})
    p.line((2, 0), 90, length=46, color='purple')          # chimney smoke
    return p


def bicycle():
    p = Pic('bicycle', 'Bicycle', clips=3)
    p.art(['  M  Y',
           ' YMM Y',
           ' P   P',
           'YP   P',
           'SSS SS',
           'S SP S',
           'SSSPSS'], {'S': 'sky', 'P': 'purple', 'Y': 'yellow', 'M': 'mint'})
    return p


def clock():
    """One large closed face with bells, feet, a button and hour markers; hands cannot be drawn
    (a bar runs outward from a ring's gap, never inside it)."""
    p = Pic('clock', 'Alarm clock', clips=3)
    face = p.ring(0, 0, 64, closed=True, color='sky')
    for degrees in (45, 135):
        bell = p.at(face, degrees, 22, color='yellow')
        p.bar(bell, degrees, length=46, color='yellow')     # hammers
    for degrees in (225, 315):
        foot = p.at(face, degrees, 22, color='purple')
        p.bar(foot, degrees, length=46, color='purple')     # legs
    p.at(face, 90, 20, color='coral')                        # the button
    for degrees in (0, 180):
        p.at(face, degrees, 20, color='mint')                # hour markers (16 leaves no gap wide enough)
    return p


def anchor():
    p = Pic('anchor', 'Anchor', clips=3)
    p.art(['  Y  ',
           'Y S Y',
           'SSSSS',
           '  S  ',
           '  S  ',
           '  S  ',
           '  S  ',
           'P S P',
           'P S P',
           'PSSSP'], {'S': 'sky', 'P': 'purple', 'Y': 'yellow'})
    p.line((0, 7), 90, length=46, color='purple')          # flukes
    p.line((4, 7), 90, length=46, color='purple')
    p.line((2, 0), 90, length=46, color='yellow')          # the chain's end
    return p


def crown():
    p = Pic('crown', 'Crown', clips=3)
    p.art(['C C C',
           'Y Y Y',
           'Y Y Y',
           'YYYYY',
           'YSSSY',
           'Y   Y',
           'YYYYY',
           'P P P'], {'Y': 'yellow', 'C': 'coral', 'S': 'sky', 'P': 'purple'})
    return p


def lighthouse():
    p = Pic('lighthouse', 'Lighthouse', clips=3)
    p.art(['  C  ',
           'YYYYY',
           ' S S ',
           ' C C ',
           ' S S ',
           ' C C ',
           ' S S ',
           ' CYC ',
           'SSSSS',
           'M   M'], {'C': 'coral', 'Y': 'yellow', 'S': 'sky', 'M': 'mint'})
    p.line((0, 9), 270, length=46, color='sky')            # waves
    p.line((4, 9), 270, length=46, color='sky')
    return p


def snail():
    p = Pic('snail', 'Snail', clips=3)
    p.art(['PPPPP ',
           'P P P ',
           'P P P ',
           'P   P ',
           'PPPPP ',
           'MMMMMM',
           '     M',
           '    MM'], {'P': 'purple', 'M': 'mint'})
    p.line((2, 2), 270, stop=p.cells[(2, 4)], color='purple')   # the shell's spiral centre
    p.line((4, 7), 180, length=46, color='mint')           # the foot
    return p


def balloon():
    p = Pic('balloon', 'Hot-air balloon', clips=3)
    p.art(['CYCYCY',
           'Y    C',
           'C    Y',
           'Y    C',
           'CYCYCY',
           ' Y  C ',
           ' CYYC ',
           '  YC  ',
           '  C   ',
           '  PP  '], {'C': 'coral', 'Y': 'yellow', 'P': (30, 'purple')})
    return p


def tree():
    p = Pic('tree', 'Tree', clips=3)
    p.art(['  MM  ',
           ' MAMM ',
           'M    M',
           'MMAMMM',
           'M    A',
           'MMMMAM',
           ' M  M ',
           ' MMMM ',
           '  T   ',
           '  T   ',
           ' TTT  '], {'M': 'mint', 'A': 'coral', 'T': 'yellow'})
    p.line((1, 10), 180, length=46, color='yellow')        # roots
    p.line((3, 10), 0, length=46, color='yellow')
    return p


def owl():
    p = Pic('owl', 'Owl', clips=3)
    p.art(['P    P',
           'PPPPPP',
           'PY  YP',
           'P CC P',
           'PPPPPP',
           'P    P',
           'P PP P',
           'P    P',
           'PPPPPP',
           ' S  S '], {'P': 'purple', 'Y': 'yellow', 'C': 'coral', 'S': 'sky'})
    return p


PICTURES = [key, cherries, snowman, house, padlock, tree, snail, owl, lighthouse, balloon, anchor, clock, bicycle, crown, wheel]
# The reward levels (planlib.PICTURE_SLOTS): right after a peak, about every thirteen levels, the
# smaller pictures first, each the biggest board around it.
sys.path.insert(0, os.path.dirname(__file__))
from planlib import PICTURE_SLOTS
MILESTONES = {level: re.search(r'picture\("(\w+)"', expr).group(1) for level, expr in PICTURE_SLOTS.items()}


def main():
    os.makedirs(OUT, exist_ok=True)
    if '--from-json' in sys.argv:
        pictures = [json.load(open(os.path.join(OUT, f))) for f in sorted(os.listdir(OUT)) if f.endswith('.json')]
    else:
        pictures = [f().finish() for f in PICTURES]
        for picture in pictures:
            with open(os.path.join(OUT, picture['name'] + '.json'), 'w') as fh:
                json.dump(picture, fh, indent=2)
                fh.write('\n')
    text = json.dumps({p['name']: p for p in pictures}, separators=(',', ':'), sort_keys=True)
    swift = f'''//
//  PictureLibrary.swift
//  RotateRings
//
//  Generated by LevelForge/pictures.py from LevelForge/pictures/*.json; do not edit by hand. The
//  milestone pictures (`Picture`, LEVEL-DESIGN.md §15).
//

import Foundation

enum PictureLibrary {{
    static let all: [String: Picture] = {{
        let json = #"{text}"#
        return try! JSONDecoder().decode([String: Picture].self, from: Data(json.utf8))
    }}()

    /// Milestone level → picture.
    static let milestones: [Int: String] = [{', '.join(f'{n}: "{name}"' for n, name in sorted(MILESTONES.items()))}]
}}
'''
    open('RotateRings/Model/Generation/PictureLibrary.swift', 'w').write(swift)
    print(f'{len(pictures)} pictures')


main()
