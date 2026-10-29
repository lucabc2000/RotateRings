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
import json, math, os, sys

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

    def ubar(self, a, b, degrees, length=40, color=None):
        """A U-bar with its arms in the gaps of rings a and b, its crossbar `length` beyond."""
        bar = dict(rings=[a, b], degrees=degrees, length=length)
        if color: bar['color'] = color
        self.bars.append(bar)

    def finish(self):
        """Centres the drawing on the board and rounds the numbers."""
        xs = [v for g in self.rings for v in (g['x'] - g['r'], g['x'] + g['r'])]
        ys = [v for g in self.rings for v in (g['y'] - g['r'], g['y'] + g['r'])]
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
        # Room for rings inside the margins (and a tail's reach): standard, else the large board.
        half_w, half_h = (max(xs) - min(xs)) / 2, (max(ys) - min(ys)) / 2
        if not self.board and (half_w > 144 or half_h > 284):
            self.board = 'large'
        if half_w > 180 or half_h > 348:
            print(f'{self.name}: {2 * half_w:.0f} x {2 * half_h:.0f} does not fit even the large board')
        out = dict(name=self.name, title=self.title, rings=self.rings)
        if self.bars: out['bars'] = self.bars
        if self.board: out['board'] = self.board
        if self.clips: out['clips'] = self.clips
        return out


def key():
    p = Pic('key', 'Key')
    bow = p.ring(0, 0, 48, color='yellow')
    p.at(bow, 135, 24, color='yellow'); p.at(bow, 45, 24, color='yellow')
    bit = p.ring(0, -250, 26, color='yellow')
    p.bar(bow, 270, stop=bit, color='yellow')
    tooth = p.at(bit, 0, 22, color='yellow')
    p.at(tooth, 90, 22, color='yellow')
    p.at(bit, 270, 22, color='yellow')
    return p


def house():
    p = Pic('house', 'House')
    apex = p.ring(0, 92, 26, color='coral')
    roof_left = p.walk(apex, 225, 225, r=24, color='coral')
    roof_right = p.walk(apex, 315, 315, r=24, color='coral')
    wall_left = p.walk(roof_left[-1], 270, 270, r=24, color='sky')
    wall_right = p.walk(roof_right[-1], 270, 270, r=24, color='sky')
    p.at(wall_left[-1], 0, 46, color='yellow')
    p.at(apex, 45, 20, color='purple')
    return p


def lighthouse():
    p = Pic('lighthouse', 'Lighthouse', board='large')
    base = p.ring(0, 0, 42, color='coral')
    t = base
    for r, color in ((34, 'sky'), (30, 'coral'), (27, 'sky')):
        t = p.at(t, 90, r, color=color)
    lamp = p.at(t, 90, 30, color='yellow')
    p.at(lamp, 90, 20, color='coral')
    p.bar(lamp, 0, length=46, color='yellow')
    rock = p.ring(-150, 0, 26, color='mint')
    p.at(rock, 270, 22, color='mint')
    p.bar(base, 180, stop=rock, color='mint')
    return p


def padlock():
    p = Pic('padlock', 'Padlock')
    top = p.ring(0, 0, 30, color='coral')
    left = p.at(top, 180, 30, color='coral'); right = p.at(top, 0, 30, color='coral')
    low = p.at(top, 270, 34, color='coral')
    p.at(left, 270, 30, color='coral'); p.at(right, 270, 30, color='coral')
    p.ubar(left, right, 90, length=46, color='yellow')
    p.bar(low, 270, length=56, color='sky')
    return p


def crown():
    p = Pic('crown', 'Crown', board='large')
    band = p.ring(-136, 0, 26, color='yellow')
    b = [band] + p.walk(band, 0, 0, 0, 0, r=26, color='yellow')
    # Ten pieces (a reward level stays short): a jewel straight on each end of the band.
    for i in (0, 4):
        p.at(b[i], 90, 22, color='coral')
    middle = p.walk(b[2], 90, 90, r=28, color='yellow')
    p.at(middle[-1], 90, 30, color='sky')
    return p


def anchor():
    p = Pic('anchor', 'Anchor', clips=3)
    eye = p.ring(0, 0, 30, color='sky')
    neck = p.at(eye, 270, 24, color='sky')
    stock = p.at(neck, 180, 24, color='sky'); p.at(neck, 0, 24, color='sky')
    crown = p.ring(0, -270, 30, color='purple')
    p.bar(neck, 270, stop=crown, color='sky')
    fluke = p.at(crown, 180, 26, color='purple'); other = p.at(crown, 0, 26, color='purple')
    p.at(fluke, 90, 22, color='purple'); p.at(other, 90, 22, color='purple')
    return p


def planet():
    p = Pic('planet', 'Planet and moon')
    body = p.ring(0, 0, 70, closed=True, color='sky')
    left = p.at(body, 180, 26, color='yellow'); right = p.at(body, 0, 26, color='yellow')
    moon = p.at(body, 45, 34, color='purple')
    p.at(moon, 90, 20, color='yellow')
    p.at(body, 225, 24, color='mint')
    p.at(body, 270, 22, color='mint')
    return p


def tree():
    p = Pic('tree', 'Tree')
    crown = p.ring(0, 0, 34, color='mint')
    left = p.at(crown, 180, 28, color='mint'); right = p.at(crown, 0, 28, color='mint')
    p.at(crown, 90, 30, color='mint')
    p.at(left, 90, 22, color='mint'); p.at(right, 90, 22, color='mint')
    bottom = p.at(crown, 270, 26, color='mint')
    root = p.ring(0, -280, 28, color='yellow')
    p.bar(bottom, 270, stop=root, color='yellow')
    p.at(root, 180, 22, color='yellow'); p.at(root, 0, 22, color='yellow')
    return p


def snail():
    p = Pic('snail', 'Snail')
    shell = p.ring(0, 0, 56, color='purple')
    p.at(shell, 135, 30, color='purple')
    foot = p.at(shell, 270, 24, color='mint')
    p.at(foot, 180, 20, color='mint')
    front = p.walk(foot, 0, 0, r=24, color='mint')
    head = p.at(front[-1], 90, 28, color='mint')
    p.bar(head, 90, length=60, color='mint')
    return p


# Milestone level → picture, in order.
# Reward levels every twenty levels (not the chapter ends, which have their own milestone boards):
# the best eight of the pictures, by how they measured (`forge pictures`).
SLOTS = [20, 40, 60, 80, 120, 140, 160, 180]
PICTURES = [key, house, lighthouse, padlock, crown, anchor, planet, tree, snail]
ORDER = ['key', 'tree', 'house', 'snail', 'lighthouse', 'anchor', 'padlock', 'crown']
MILESTONES = dict(zip(SLOTS, ORDER))


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
