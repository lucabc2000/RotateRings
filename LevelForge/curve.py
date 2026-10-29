# Draws the difficulty curve of a generated set as an SVG (LEVEL-DESIGN.md §15): the targets of the
# plan, an older plan's targets for comparison, and what each chosen level measured, with tier-2
# peaks, breathers, pictures and chapter ends marked and levels out of band in red.
#
#   python3 LevelForge/curve.py SET_DIR OUT.svg [OLD_DifficultyCurve.swift]
import json, re, sys

set_dir, out = sys.argv[1], sys.argv[2]
curve = open('RotateRings/Model/Generation/DifficultyCurve.swift').read()
targets = [float(x) for x in re.search(r'targets: \[Double\] = \[(.*)\]', curve).group(1).split(', ')]
peaks = {int(x) for x in re.search(r'peaks: Set<Int> = \[(.*)\]', curve).group(1).split(', ') if x}
breathers = {int(x) for x in re.search(r'breathers: Set<Int> = \[(.*)\]', curve).group(1).split(', ') if x}
old = None
if len(sys.argv) > 3:
    old = [float(x) for x in re.search(r'targets: \[Double\] = \[(.*)\]', open(sys.argv[3]).read()).group(1).split(', ')]
report = json.load(open(f'{set_dir}/levels-report.json'))
levels = {l['number']: l for l in report['levels'] if l['number'] >= 11}

# Square (qlmanage renders square thumbnails): difficulty on top, interest below.
W, H, L, R, T, B = 1400, 760, 50, 20, 30, 50
IT, IB = 820, 1350
YMAX = 70
def x(level): return L + (level - 11) / 189 * (W - L - R)
def y(value): return T + (1 - min(value, YMAX) / YMAX) * (H - T - B)

parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{W}" font-family="Helvetica" font-size="12">',
         f'<rect width="{W}" height="{W}" fill="#101834"/>']
for v in range(0, YMAX + 1, 10):
    parts.append(f'<line x1="{L}" x2="{W - R}" y1="{y(v)}" y2="{y(v)}" stroke="#2a3560"/>')
    parts.append(f'<text x="{L - 8}" y="{y(v) + 4}" fill="#9aa4c8" text-anchor="end">{v}</text>')
for level in range(20, 201, 10):
    parts.append(f'<text x="{x(level)}" y="{H - B + 18}" fill="#9aa4c8" text-anchor="middle">{level}</text>')
for chapter_end in (100, 150):
    parts.append(f'<line x1="{x(chapter_end + 0.5)}" x2="{x(chapter_end + 0.5)}" y1="{T}" y2="{H - B}" stroke="#4a5590" stroke-dasharray="4 4"/>')
def polyline(values, color, width, dash=''):
    points = ' '.join(f'{x(11 + i):.1f},{y(v):.1f}' for i, v in enumerate(values))
    return f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="{width}" {dash}/>'
if old:
    parts.append(polyline(old, '#6b7399', 1.5, 'stroke-dasharray="5 4"'))
parts.append(polyline(targets, '#5ab0ff', 2))
for level, entry in sorted(levels.items()):
    q = entry['chosen'].get('quality')
    if not q:
        continue
    color = '#ff6b6b' if entry.get('outOfBand') else '#f5f7ff'
    if level in breathers: color = '#7be0b5' if not entry.get('outOfBand') else '#ff6b6b'
    shape = 'rect' if level in (50, 100, 150, 200) else 'circle'
    cx, cy = x(level), y(q['difficulty'])
    if shape == 'rect':
        parts.append(f'<rect x="{cx - 5}" y="{cy - 5}" width="10" height="10" fill="#ffd166"/>')
    else:
        parts.append(f'<circle cx="{cx}" cy="{cy}" r="{4 if level in peaks else 3}" fill="{color}" stroke="{"#ffd166" if level in peaks else "none"}" stroke-width="1.5"/>')
legend = [('#5ab0ff', 'target (new plan)'), ('#6b7399', 'target (before)'), ('#f5f7ff', 'measured, in band'),
          ('#ff6b6b', 'out of band'), ('#7be0b5', 'breather'), ('#ffd166', 'tier-2 peak (ring), chapter end (square)')]
for i, (color, text) in enumerate(legend):
    parts.append(f'<rect x="{L + 10 + i * 205}" y="8" width="12" height="12" fill="{color}"/>')
    parts.append(f'<text x="{L + 28 + i * 205}" y="18" fill="#dfe4f5">{text}</text>')
# Interest of each chosen level, 0…1.
def iy(value): return IT + (1 - value) * (IB - IT)
parts.append(f'<text x="{L}" y="{IT - 12}" fill="#dfe4f5">interest of the chosen board (breathers green)</text>')
for v in (0, 0.25, 0.5, 0.75, 1):
    parts.append(f'<line x1="{L}" x2="{W - R}" y1="{iy(v)}" y2="{iy(v)}" stroke="#2a3560"/>')
    parts.append(f'<text x="{L - 8}" y="{iy(v) + 4}" fill="#9aa4c8" text-anchor="end">{v:g}</text>')
for level in range(20, 201, 10):
    parts.append(f'<text x="{x(level)}" y="{IB + 18}" fill="#9aa4c8" text-anchor="middle">{level}</text>')
for level, entry in sorted(levels.items()):
    q = entry['chosen'].get('quality')
    if q:
        parts.append(f'<circle cx="{x(level)}" cy="{iy(q["interest"])}" r="3" fill="{"#7be0b5" if level in breathers else "#f5f7ff"}"/>')
parts.append('</svg>')
open(out, 'w').write('\n'.join(parts))
print(f'wrote {out}')
