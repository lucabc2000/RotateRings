import random, json, sys
random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 7)
# design catalogue: swift expression, family, group (what kind of hard), expected score
C = []
def add(expr, fam, grp, exp): C.append(dict(expr=expr, fam=fam, grp=grp, exp=exp, used=0))
for mask, h, base, bars in [("nine",2,27,1),("twelve",2,35,2),("grand",2,46,3),("column",3,58,3),("field",3,70,4),("tall",3,85,6)]:
    add(f'knot("hubs-{mask}", holders: {h})', "K", "chain", base)
    add(f'knot("hubs-{mask}", holders: {h}, tails: 0.4)', "KT", "obstacle", base + 2)
    add(f'knot("hubs-{mask}", holders: {h}, bars: {bars})', "KB", "cross", base - 6)
    add(f'knot("hubs-{mask}", holders: {h}, bars: {bars}, tails: 0.4)', "KX", "obstacle", base - 2)
# U-bars: one bar pinning two rings; from the twelve-ring board up
for mask, h, exp, bars, us in [("twelve",2,30,0,1),("grand",2,40,1,1),("column",3,52,1,1),("field",3,62,2,1),("field",3,60,0,2),("tall",3,74,2,2)]:
    add(f'knot("hubs-{mask}", holders: {h}{f", bars: {bars}" if bars else ""}, uBars: {us})', "U", "cross", exp)
add('knot("hubs-kite", holders: 2, tails: 0.3)', "D", "chain", 48)
add('knot("hubs-weave", holders: 3, tails: 0.4)', "D", "chain", 65)
for web, exp, extra in [("nine",26,""),("twelve",32,""),("grand",40,""),("column",49,""),("kite",44,""),("field",60,""),("weave",56,""),
                        ("lace",71,", bars: 4"),("gaps",71,", bars: 4"),("riddle",73,", bars: 4"),("tall",80,"")]:
    small = web in ("nine","twelve")
    add(f'hubWeb("hubs-{web}", clips: {"2...3" if small else "3...4"}, holders: {2 if small else 3}{extra}, tails: 0.85)', "WB" if extra else "W", "cross" if extra else "prep", exp)
for cols, rows, bars, fl, exp in [(8,10,11,2,15),(9,12,14,2,25),(10,14,17,2,36),(11,15,19,3,46),(11,16,21,3,52),(11,18,23,3,58),(11,20,26,3,64)]:
    add(f'maze(cols: {cols}, rows: {rows}, bars: {bars}, freeLimit: {fl})', "M", "order", exp)
add('cages(across: 2, down: 3, count: 3, lanes: 2, border: 1, bars: 8, freeLimit: 3)', "C", "order", 23)
add('cages(across: 3, down: 3, count: 4, border: 0, bars: 13, freeLimit: 3)', "C", "order", 45)
add('cages(across: 3, down: 4, count: 5, border: 0, bars: 15, freeLimit: 3)', "C", "order", 55)
add('cages(across: 3, down: 4, count: 6, border: 0, bars: 16, freeLimit: 3)', "C", "order", 62)
add('sun(lock: lock)', "P", "picture", 22); add('sunAndMoons(lock: lock)', "P", "picture", 29)
add('bullseye(lock: lock)', "P", "picture", 22); add('tangle(rings: 9...12, pokes: 1, latches: 1, planet: true, lock: lock)', "P", "picture", 20)
add('tangle(rings: 9...12, pokes: 2, latches: 2, planet: true, chain: 0.7, lock: lock)', "P", "picture", 28)
add('tangle(rings: 8...10, pokes: 1, lock: lock)', "T", "picture", 22)
add('tangle(rings: 11...14, pokes: 1, latches: 1, lock: lock)', "T", "picture", 31)
add('tangle(rings: 13...16, pokes: 2, latches: 2, chain: 0.7, lock: lock)', "T", "picture", 38)
add('tangle(rings: 15...18, pokes: 2, latches: 1, hubs: 3, lock: lock)', "T", "picture", 42)
add('tangle(rings: 17...21, pokes: 3, latches: 2, chain: 0.75, lock: lock)', "T", "picture", 48)
for net, exp, extra in [("figure-block",20,""),("weave-diamond",23,""),("weave-butterfly",30,""),("weave-kite",32,", crossClips: 1"),
                        ("weave-crystal",36,", crossClips: 1, tails: 3"),("weave-lantern",39,", bars: 1, tails: 3"),("weave-tapestry",43,", crossClips: 2, tails: 4")]:
    add(f'net("{net}", lock: lock{extra})', "F", "picture", exp)
if len(sys.argv) > 2:  # measured scores from a previous run: {expr: score}
    for k, v in json.load(open(sys.argv[2])).items():
        for c in C:
            if c['expr'] == k: c['exp'] = v

# waves: phrases of different lengths, never the same one twice running
phrases = [[-3, 3, 9, -10], [0, 6, -4, 12, -8, -1], [-11, 1, 5, 3, 14, -6], [3, -5, 8, 10, -12], [-2, 4, -9, 7],
           [5, -2, 2, 11, -3, -10, 6], [-6, 8, -1, 4, 15, -9], [2, 9, -7, -2, 6, 12, -13], [-4, 0, 7, -11, 10]]
offsets, last = [], None
while len(offsets) < 90:
    p = random.choice([q for q in phrases if q is not last]); last = p
    offsets += [o + random.choice([-2, -1, 0, 1, 2]) for o in p]
offsets = offsets[:90]
offsets[0] = -2; offsets[-1] = 13; offsets[-2] = -4   # gentle start; the last level is a peak after a breath
plan = []
for i, level in enumerate(range(11, 101)):
    base = 25 + 47 * (i / 89) ** 0.9
    target = max(14, min(95, base + offsets[i]))
    recent = [p['fam'] for p in plan[-2:]]
    def cost(c):
        k = abs(c['exp'] - target) + 4 * c['used']
        if recent and c['fam'] == recent[-1]: k += 100
        if c['fam'] in recent: k += 6
        if plan and c['grp'] == plan[-1]['grp']: k += 5
        if c['fam'] == "U":
            if level < 20: k += 1000                  # no U-bars before level 20
            elif c['used'] < 1: k -= 7                # make sure every U-bar board gets its turn
        return k + random.random()
    c = min(C, key=cost); c['used'] += 1
    plan.append(dict(level=level, target=round(target), offset=offsets[i], **{k: c[k] for k in ('expr', 'fam', 'grp', 'exp')}))
# bombs: about one level in four from 25 on, on knot boards only, never two levels running;
# harmless before level 60 (`GameViewModel.firstFatalBombLevel`), fatal from then on
next_bomb = 26
for p in plan:
    if p['level'] >= next_bomb and p['fam'] in ("K", "KT", "KB", "KX", "U", "D"):
        count = 2 if p['level'] >= 70 and random.random() < 0.5 else 1
        p['expr'] = p['expr'][:-1] + f", bombs: {count})"
        p['bombs'] = count
        next_bomb = p['level'] + random.choice([3, 3, 4, 4, 5])
json.dump(plan, open(sys.argv[3] if len(sys.argv) > 3 else 'plan.json', 'w'), indent=0)
for p in plan: print(p['level'], p['target'], f"{p['offset']:+d}", p['fam'] + ("*" if p.get('bombs') else ""), p['exp'], p['expr'][:70])
