# Designing and generating levels

How the levels of Rotate Rings are made, what makes one fun, and how to make more. Written for
whoever (person or AI) next touches `RotateRings/Model/Generation` or the `LevelForge` tool. Read
this before changing a generator or regenerating levels.

## 1. The game in one paragraph

A level is a tangle of pieces that hold each other. A **clip** is a small square on a stem; it
grips the arc of a **ring**. A piece that owns a gripping clip is pinned: it cannot move at all. A
ring can always turn (unless something sits in its gap); turn its gap onto a clip and that clip is
released. A piece with no connection left leaves the board, unless it is a turning piece that is
still touching another body. **Sliding bars** sit in a hub and leave once their arm has slid out of
it. The level is done when the board is empty. Every rule lives in `Board.swift`; the solver and the
generators never re-implement them, they call the board.

Piece kinds (`PieceKind.swift`): C-ring, closed ring (never releases anything, so it only ever
holds), ring with a tail, latch bar (a turning bar pinned by its own clip), sliding bar, L-bar
(a sliding bar with a leg that cannot pass its hub, so it leaves one way only).

## 2. What makes a level fun

Learned by comparing our levels with a popular competitor's (47 of its levels, October 2026):

1. **Moves that prepare, not just remove.** This is what makes a level hard; see §7, which
   exists because the first attempt at "hard" got it wrong. If every drag takes a piece off, the
   level plays easy however cleverly it is locked. Measure it: `setupMoves` in the report (moves
   of the solution that remove nothing). Hub webs have 5–13; every other genre has about none.
   `freedom` (share of pieces with a productive move) is a weaker, secondary signal: low freedom
   makes a level slower to read, not harder to solve.
2. **Free-form over grids.** Rings of several sizes hung on each other at arbitrary angles, chains
   that snake across the board, a huge ring with small ones inside and outside. Grids look
   generated; clusters look placed by hand. The `tangle` and `planet` templates do this.
3. **Variety from level to level.** Never two of the same genre in a row. The genres: tangle,
   planet, figure (symmetric square-grid shape), weave (diagonal grid), maze (bars only), cages
   (rings pinned by T-bars with bars in the lanes), workshop (a few cages in a bar maze), sun.
4. **Locks, not just trees.** A bar poking into a ring's gap, a latch bar hanging from one ring and
   reaching into another, a tail in a neighbour's gap, a ring held by two clips. These turn "turn
   the leaves first" into "find the one piece that can move".
5. **Rhythm.** Hard levels alternate with easy ones (`Compositions.hardLevels`). Every fifth
   level is a showpiece (bigger or prettier, not necessarily harder). The sun levels are easy on
   purpose. Levels 51–100 (`Compositions.lateTemplates`) run a ten-level cycle that is mostly hub
   webs, with a maze, a tangle and a workshop mixed in and a breather at each 5.
6. **Scale.** Boards should use the screen. Rings down to radius 22 and up to 110 are all fine.
7. **No near misses.** A release window of 1° is a bug, not difficulty (see §5).

Not done yet, in the order they would add the most: bombs (a ring that must be freed within N
moves), acorns (a collectible inside rings, worth doing only if tied to boosters), more picture
levels (cat face, robot, spider web; the sun is the one we have). Pieces overlapping each other,
which the competitor allows, is not possible in this engine: overlap is a collision. §8 lists
more ideas from the competitor's later levels, with what each would take here.

## 3. How a level gets made

```
TutorialPlan.goal(for:)      what level N needs (1–15: a teaching goal; 16+: Compositions.templates)
Compositions.templates(level:)  the genre and size for each curve level, and hardLevels
LevelTemplate                 a recipe: seed → LevelDraft (pieces in board coordinates)
LevelGenerator.attempt        build → validate → solve → score → Candidate
LevelGenerator.generate       tries seeds, keeps the best, writes level, report and runner-ups
```

Builders (all under `Model/Generation`):

| File | Makes | Notes |
|---|---|---|
| `Tangle.swift` | tangle, planet | grows a cluster from one seed or several hubs; free angles, mixed sizes, poke and latch bars; playout-checked |
| `RingNet.swift` | figure, weave | masked grid, mirrored wiring, holes for bars, tails for hard levels |
| `HubWeb.swift` | hub web | closed hubs holding shared rings on a grid, tails that cannot pass a hub, bars in holes; the genre that takes thought (§7) |
| `GridWorld.swift` | maze, cages, workshop | cell grid; built in reverse removal order so it is solvable by construction; `freeLimit` for hard |
| `Motifs.swift`, `LatticeMotifs.swift` | tutorial motifs, sun, flower | small hand-built puzzles, stacked by `LevelTemplate.stack` |
| `LevelDraft.swift` | — | wiring, gap planning, colours, validation |
| `ForgeGeometry.swift` | — | `ForgeRules` (board 360×640, margins, stems, gaps) and `DraftPiece` |

Selection: for a normal level the candidate closest to the difficulty curve wins
(`DifficultyCurve`, `DifficultyScore`). For a hard level, eight candidates are built (twelve past
level 50) and the one with the most `setupMoves` wins, then the lowest `freedom`. Generation is
deterministic: the same seeds and settings give byte-identical files on any machine and with any
`--jobs` (§14).

## 4. Workflow

Build the tool (fast, no Xcode UI needed):

```
swiftc -O -o /tmp/forge LevelForge/main.swift $(find RotateRings/Model -name '*.swift')
```

Commands (paths are resolved from the repo root):

```
/tmp/forge compose tangle-6-8 planet-9-12-locked --count 4 --out DIR [--state-cap N] [--verbose] [--keep-stuck]
/tmp/forge probe --levels 16-20 --count 4            # why each seed of a level does or does not work
/tmp/forge generate --levels 16-50 --jobs 6          # regenerate; keeps the other levels' files
/tmp/forge generate --levels 101-110 --out DIR       # the same into DIR; the shipped files are not touched
/tmp/forge generate --levels 18,35 --keep-seeds      # rebuild from the shipped report's seeds after a rule change
/tmp/forge diagnose DIR/x.json                       # play greedily; explain what blocks what is left
/tmp/forge solve RotateRings/Levels/level33.json     # metrics for one file
/tmp/forge report                                    # the level table
```

Run the tool with `SWIFT_DETERMINISTIC_HASHING=1` in the environment. Nothing should depend on it
(§14), but it is a cheap safety net. `compose` lists every template id when called without one. Template ids are what the report's
`template` column shows.

Looking at levels: there is no renderer in the tool. Write a throwaway SVG from the JSON: the
board is 360×640, y points up, angles are degrees counterclockwise, every shape is in the piece's
local space (rotate by `rotation`, then add `position`), and an arc with sweep 360 is a closed
ring. Clips are a stem from `stemStart` to `stemEnd` with a 16-unit square at the end. Sliding
pieces have a 36×24 hub at `position`. A contact sheet of 6–12 levels at once is the fastest way to
judge a batch.

Before shipping regenerated levels: run the tests (`LevelTests` replays every recorded solution),
look at every changed level, and play the hard ones on a phone.

## 5. Rules that bite

These are the constraints behind most generator failures. The solver finds them, but it is slow
to find them (a full state cap, about four seconds, per unsolvable candidate), so generators check
them up front.

- **Touching keeps turning pieces on the board.** A turning piece with no connection stays as long
  as any body is within 16 units of it. So rings must sit at least 18 apart (stems are 18–26), and
  a latch bar's far end in a ring's gap is only safe when the ring's radius is 28 or more: the arc
  ends come within r·sin(40°) of the bar. Sliding bars are exempt; they leave regardless.
- **A ring that grips and is gripped turns exactly one step** (45°) once its children are gone,
  with its loose clips sweeping along. That needs radius ≥ 30 (`ForgeRules.supportsOneStepLock`),
  nothing in the sweep (`Tangle.sweep`, `mayHangChild`), and the gap one step from its own clip
  in the direction the sweep was cleared for. Rings smaller than 30 can be leaves or roots only.
- **A ring held by two clips a quarter turn apart** is freed by turning its gap over both at once.
  The gap must leave `sharedReleaseWindowDegrees` (16°) of play beyond the span of the two clips;
  `LevelDraft.sharedGapRequirement` does this. Before it did, those rings had 1–4° of play.
- **Gap centres are a multiple of 45° from the clip contact**, so a drag that stops on the grid
  releases. Contacts themselves can be at any angle (tangles rely on this).
- **A bar in a gap must block within 45°.** The bar's end sits 10–15 units inside the circle; the
  arc ends then stop after about 20–25°, which is less than one step. Deeper is no better.
- **A lock only makes a level harder if it takes a free piece away.** A bar poking into a leaf's
  gap locks the leaf, but the bar itself is free, so the count of free pieces is unchanged; the
  same goes for a latch bar, whose held ring is free. What lowers `freedom` is a lock whose key is
  not free either: a tail from a ring that still grips others (`RingNet`), a bar whose way out is
  blocked by another ring (`Tangle.addPokeBar(blocked:)`, `GridWorld.freeLimit`), or simply fewer
  leaves (long chains). Measured: free pokes and latches left tangles at 30–40 % free however many
  were added.
- **A sleeve works one way round** (`Board.isExcludedPair`, `clipSitsOnRing`,
  `GameRules.clipSquarenessDegrees` = 7°, raised from 4° because lining up was fiddly). After a clip has slipped off, its piece can be turned a
  little; the square then still crosses the ring's circle, but askew. The ring cannot be threaded
  back through a tilted sleeve and nothing grips there (owner reports, 2026-10-07: pieces "fully
  stuck inside each other", and "you can still slide it through the clip from a weird angle").
  The clip's own piece, on the other hand, can always slide its sleeve along the ring and off the
  ring's end, so letting go still works however the gap sits.
- **Deadlocks by construction**: a tail or bar must not lock a ring that the locking piece itself
  waits for (`RingNet.waitsFor`, latch bars only on leaves). A ring with two owners can only be
  freed if one owner disappears when released.
- **Bounds**: strokes stay 24 units inside the board edge. `Motif.placed` centres a motif's
  bounds; `GridWorld` centres the grid instead because hubs stick out.
- **The solver handles at most 64 connections** (clips plus hubs). Keep levels under ~30 pieces.

## 6. Adding a level or a genre

- New level of an existing genre: add a `case` in `Compositions.templates(level:)`, bump
  `LevelGenerator.levelCount` and the `DifficultyCurve` ranges if the level is beyond 50, then
  `generate --levels N`. Check it with `compose` first.
- New genre: a function returning `LevelTemplate` (see `Compositions.tangle`). Build in local
  coordinates as a `Motif` and let `LevelTemplate.single` centre it, or build a `LevelDraft` in
  board coordinates. Validate with `draft.validate()`, then `LevelSolver.greedyPlayout()` to
  reject drafts that cannot be played in the order they were built; it is a thousand times cheaper
  than letting the real solver discover an unsolvable board.
- Hard variant: add locks (tails, pokes, latches, `freeLimit`), put the level in `hardLevels`, and
  check `freedom` with `compose`; aim below 20 %.
- Keep easy levels reproducible: do not consume random numbers in code paths that are only
  meant for hard variants (see the `options.tails > 0` guard in `RingNet`).

## 7. What "hard" turned out to mean

The first fifty extra levels (51–100, first version) were built to minimise `freedom`: mostly
locked tangles, tight mazes and cage boards, the tightest at 7–9 % of pieces free. The owner
played 97–100 and found them "way too easy". Asked why, the answers were: it is always obvious
what to move, one drag and the piece is gone, and it is over too quickly. Asked what makes the
competitor's levels hard: rings held by several clips, things in the way, boards too dense to
read at a glance, and bombs. (Their hooking rule is the same as ours: a ring whose clip grips
another ring cannot turn.)

What that means in this engine:

- **A tree is easy no matter how it is locked.** When every ring has one holder, the leaf turns
  to its clip and leaves: one drag, one piece. Locks only decide which leaf is next. Low
  `freedom` just means fewer candidates to try, and trying costs nothing.
- **Shared rings force preparation.** A ring held by two or more pieces cannot leave by turning
  to one clip. A piece pinned by clips on several rings only lets go when all of those rings have
  their gaps on its clips at once. Lining them up is several drags that remove nothing, and a
  ring shared by two holders can serve only one at a time: turning it on re-grips the first.
- **`HubWeb` is built on exactly that**: closed hubs on every other cell of a grid, each holding
  two to four neighbouring rings, rings held by up to three hubs, bars in holes that lock a ring
  until the piece across the hole is gone. A 24-ring web takes 30–40 moves, 5–13 of them
  preparation, and nothing comes off at the start with a single drag when every ring has two
  holders.
- **A caveat found while measuring**: once a ring is down to its last hub it escapes with one
  drag, like a leaf, so most preparation happens early in a web and the end unravels quickly.
  More clips per hub and more hubs per ring (the lattice allows three: the gap needs the fourth
  side) push that later. In a web without bars or tails any hub can be done at any time, so
  there is no order to work out.
- **Tails give a web its order.** The owner played the plain webs and still found them too easy,
  and asked for rings with parts sticking out "way more often". A tail on a web ring cannot swing
  through what stands beside the ring, so the ring only turns within the stretch between two
  obstacles (measured on generated boards: 3 to 5 of its 8 positions at the start, sometimes 1).
  It can serve some of its hubs and not others until a hub in the tail's way has gone, and it
  matters which way round it is turned. `HubWeb` has two lengths: a long tail (`stem − 4`) is
  stopped by any hub next to its ring; a stub (`stem − 11`) passes a hub's circle and is stopped
  only by the clips on its own ring, which is what fits where a ring has hubs on all sides. A
  ring with three holders has room for a tail only next to its gap, so tailed rings may get the
  narrow gap (one step from a clip).
- **How the tails are chosen** (`HubWeb.build`, `play`): the web is played in the abstract (a hub
  goes when each of its rings can turn its gap to it without the tail crossing a blocked
  direction; clearing a hub only opens more, so greedy rounds decide solvability). A hill climb
  changes one ring's gap and tail at a time and keeps changes that still play through and score
  no lower: rounds first, then fewer hubs open at the start, then more tails. With tails on 85 %
  of rings a 12-hub web typically needs 9–11 rounds, i.e. the hubs come off nearly one by one in
  an order the player has to find; without tails it is one round. The real solver then confirms
  the board. Random assignment does not work: almost every random set of tails deadlocks.
- **What the numbers do not show**: `minMoves`, `setupMoves` and `freedom` barely change when
  tails are added (the same hubs need the same rings). The order is the difficulty, and the only
  measure of it is the planner's round count (debug output of `compose --verbose`).
- **Cross clips do not do this.** A second owner a quarter turn from the first is released
  together with it in one move (the gap is sized for that, §5). Putting the second owner opposite
  the first was tried on the ring figures: almost no leaf has a usable opposite neighbour, and
  moves did not go up.
- **The solver cannot search a web** (eight positions per ring). `LevelSolver.ownerPlayout`
  solves it the way a player does (take what comes off; else pick a pinned piece and turn every
  ring it grips onto its clip) and is tried before the best-first fallback. Its solution is not
  the shortest, so `minMoves` for webs is an upper bound.
- **Hard levels are now ranked by `setupMoves` first**, then `freedom`
  (`LevelGenerator.rank`).

Still missing from the owner's list: bombs (a move limit is the only thing that would make a
wasted drag cost something) and real visual density (our pieces never overlap).

## 8. Notes from the competitor's levels 49–75

A second batch of 27 screenshots (October 2026). What stands out beyond §2, and what it would
take in this codebase. Two of these are built (multi-hub tangles and the bullseye, marked below);
the rest is not.

**How their campaign is paced**

- **A picture level every ten levels, exactly**: 20 crab, 30 cat, 40 robot, 50 bullseye, 60 bull's
  head, 70 butterfly, plus the odd extra (66 is a car). They are the levels people remember and
  screenshot. We have the sun at 20 and 40 and nothing else.
- **Picture levels are zoomed out.** Strokes are visibly thinner and there are more, smaller
  pieces: the whole board is drawn at a smaller scale. A level file carries its own board size and
  the scene fits the board to the screen, so a picture level here can simply use a bigger board
  (say 540×960) with the same stroke width. The generators assume 360×640 (`ForgeRules`); a
  hand-built motif does not have to.
- **A breather follows every heavy level.** 61 (a loose ring tangle) and 68 (a plain 4×4 grid of
  rings) come right after their densest boards. Difficulty is a sawtooth, not a ramp. Ours does
  this via `hardLevels`; keep it when adding levels.
- **Density keeps growing, piece size shrinks.** By level 50–75 a normal board has 25–35 pieces
  and ring radii around 25–30 of our units. Our late levels top out at 19–30 pieces. Tangles
  already switch to smaller radii from 16 rings up (`Compositions.tangle`); going denser means
  radii 22–30 throughout and leaves as the only small rings (see the one-step rule in §5).
- **Symmetry is reserved for set pieces** (57, 64, 73). Everyday levels are asymmetric. That
  matches our split: figures and weaves are mirrored, tangles and grids are not. Do not mirror
  tangles.

**Structures we do not build yet**

- **Several closed hubs in one tangle** (53, 55, 61, 69, 72): three to five closed rings, each
  holding three or four C-rings, the clusters sitting between each other. **Built**: `hubs` in
  `Tangle.Options` places that many seeds well apart, hangs three rings on each, then grows as
  usual; every seed with three or more rings closes. A closed ring can only ever be a root here
  (nothing can grip it), so this is a forest of independent trees. It looks right but plays
  easy: every hub's rings are free from the start, so about half the pieces can move (freedom
  45–60 %, against 16–26 % for a single-seed chain with locks). Use it for easy levels (26, 41,
  46) and keep single-seed tangles for hard ones. Not built: linking the trees with a ring held
  by two hubs, which needs the two contacts a multiple of 45° apart and the shared gap rule, and
  is what would make these hard.
- **A puzzle inside a giant ring** (67: a hub, six rings and four bars inside one big C-ring).
  Our planet puts three rings inside and stops. Growing a proper sub-tangle inside means letting
  `grow` treat the inside of the giant ring as its board and adding bars there.
- **Nested rings as a showpiece** (50 is four concentric rings, a bullseye; 66 and 74 use
  ring-in-ring pairs). **Built** as level 30: `Motifs.bullseye` nests four rings (only the
  outermost can be closed; the inner ones need gaps to be released, one step from their clip like
  any ring that grips and is gripped), and `Compositions.bullseye` stacks it with a small tangle
  confined to the rest of the board (`Tangle.Options.halfHeight`), the same two-part layout as
  their level 50.
- **U-bars** (58, 62, 71, 75): a bar with two parallel legs and a hub on each, often cradling a
  ring or wrapped around other bars. In this engine that is a sliding piece with three segments,
  sliding along its legs; the second hub would be drawing only, since one hub already fixes the
  axis. `PieceKind.classify` calls anything with two or more segments an L-bar, which is fine.
  The scene draws one hub per piece (`PieceNode`), so the second needs a small rendering change.
- **Bars that hug rings** (51, 52, 56, 75): L- and U-bars running along a ring's outline or
  between two rings, so the board reads as one interlocked mass instead of rings plus separate
  bars. Our workshop levels come closest. In a tangle it means placing bars in the gaps between
  rings after growth, with the same `hasRoom` checks, and choosing ones that block a turn.
- **Long clips** (41, 57: rings far apart joined by stems three or four times our longest). Our
  stems are 15–30 (`ForgeRules.stemRange`) because a loose clip sweeps when its owner turns. A
  ring that never turns has no such limit: a root, or a closed ring. A "web" genre would be closed
  or root rings with long clips to distant leaves, symmetric like theirs.
- **Curved bars** (70, the butterfly's wing outlines look like arcs sliding in hubs). Not possible
  here: a sliding piece moves along a straight axis.
- **Tails that swing through gaps** (72, and the stubs on rings in 49, 52 and 55). A ring has a
  short bar sticking out of it; the bar turns with the ring. Where a neighbour is close, the bar
  cannot pass unless that neighbour's gap faces it, so the player first turns the neighbour to
  open the gate, swings the bar through, and sometimes turns the neighbour on again for its own
  release. It ties together two rings that share no clip: the order of moves depends on which
  way a neighbour faces, not only on what holds what. The owner pointed this out as something
  that makes their levels fun, so it is high on the list.

  We have the piece (the ring with a tail, taught in levels 9 and 10) and the rules already
  handle it, since it is plain collision. What we generate is only the static half: a tail parked
  in a neighbour's gap as a lock (`RingNet` tails, `Motifs.tailGate`), on a ring that itself
  turns a single step. The swing-through case needs, in a tangle:
  - a tailed ring whose release is several steps away, so the tail travels;
  - a neighbour on that path, close enough that the tail reaches into its circle (tip 6–12 units
    inside; deeper and an 80° gap no longer spans both crossing points);
  - that neighbour's gap starting somewhere else, so the gate is shut at the start, and the
    neighbour free to turn when the gate is needed (not locked behind the tailed ring, or neither
    can move);
  - the tail kept out of every other body's way over the whole turn, like a clip's sweep
    (`Tangle.sweep`) but for the full angle.

  `greedyPlayout` will reject most of these, because opening a gate releases nothing and so is
  not a move it tries. Check them with the real solver instead.

  One thing to design around: in our rules a ring that can turn freely can usually also leave
  (a leaf just turns its gap to its clip). If the neighbour can leave before the tailed ring
  needs to pass, the player removes it and never opens a gate; the tail then only adds an
  ordering ("this ring waits for that one"), which is still useful and lowers `freedom`. A real
  open-pass-close gate needs a neighbour that can turn but cannot leave yet: one held by two
  clips, or one whose own release is blocked partway. Build the ordering version first.

**Their extra mechanics, seen again**

- **Bombs** sit on a hub or a big ring, one or two per level, in roughly a third of the levels
  from 21 on. They mark the piece that must not be left for last.
- **Acorns** are in almost every level, two to four of them, inside ordinary rings. They read as
  a reward for clearing that ring, nothing more.
- **Boosters are refilled by watching an ad** (the green play badge on an empty booster). Worth
  knowing when deciding what our ten boosters per campaign are for.

**What to build next, in order**: tails that swing through a neighbour's gap (webs now use tails
as obstacles, but nothing yet opens a gate for one), one zoomed-out picture level for the level-50 slot, hubs linked by
shared rings (so multi-hub tangles can be hard), U-bars, then bars that hug rings.
Bombs remain the one change to how the game plays rather than how it looks.

## 9. The full scan of the competitor (74 screenshots, levels 2–75) and what it changed

The owner played the tailed webs, still found "lots of levels way too easy", and asked for a real
scan and a full redo. Every screenshot in `~/Desktop/levels` (levels 2–49) and
`~/Desktop/screens2` (49–75) was read at full size. What sections 7 and 8 missed:

**1. Their rings hold and are held.** From about level 25 on, most C-rings carry one or two clips
of their own *and* are gripped by two or three others (levels 26, 34, 35, 49, 53, 61, 64, 68, 73
are almost nothing else). A ring whose own clip still grips cannot turn (the owner confirmed
this), so at the start only a handful of rings move and the player has to trace which. Our
figures and tangles were trees (one holder per ring); our hub webs had closed hubs and rings
without clips, so every ring could always turn. Neither had depth.

**2. A ring held by two lets go of one at a time.** After it releases holder A, A has to turn
away or leave before the ring moves on to holder B, or A's clip grips it again. Our
`planSharedGap` deliberately widened the gap so two holders a quarter turn apart are released in
one move, which removed exactly this. `Knot` uses `sharedGapRequirement(together: false)`.

**3. Released clips stay on their ring and swing with it.** The one mid-play screenshot (their
level 49 with four pieces left) shows a hub with three loose clips and rings with loose stubs
turned 45° from where they started. Our engine does the same, and the owner wants it kept that
way: clips stay on, stay visible and stay solid, and rings keep rotating freely (no snapping).
A version where let-go clips retracted was built without asking and rejected ("the clip
shouldn't disappear, I never approved of that"); snapping to 45° steps was rejected too.
**Known cost:** the solver only looks at 45° steps while a ring rests wherever the finger leaves
it, so a loose clip parked between steps can wedge into a neighbour's gap. The owner got stuck
that way on level 100 once (a position the solver called a six-move finish). The last piece
moved can always be turned back, so it is never a true dead end, but it can feel like one. Do not
change engine rules to fix this without asking first.

**4. Everything is on one board.** About half of their levels 51–75 thread bars through rings:
a bar lying in a ring's gap (the ring cannot turn until the bar is out), a U-bar with an end in
two rings, a bar held by a ring's clip, L-bars whose way out crosses a ring. We kept rings and
bars in separate genres (webs, mazes, workshops).

**5. Size, not rules, carries the early curve.** Their level 8 has twelve rings, level 14 about
twenty pieces of four kinds, level 26 twenty-four rings. Ours reached twelve pieces around
level 20.

**6. Things we still cannot say.** Closed rings in their levels are gripped by other rings'
clips (21, 49, 50, 59, 65), often with a bomb on them, and in the mid-play screenshot two such
rings are gone while the pieces gripping them remain. Under our rule a clip on a closed ring
never lets go, so their rule for closed rings differs from ours in a way screenshots do not
show. Ask the owner before building anything on it. Also not built: clips that hold bars and
rings inside rings (74). U-bars and bombs were added later (§11).

### What was built: `Knot.swift`

Rings on a grid (the `webShapes` masks), joined to neighbours by clips that all run downhill in
one ranking, so the wiring has no circular waits. Up to two clips per ring, two or three holders
per ring, three links at most so the fourth side has room for the gap. The ranking follows the
distance from a random cell (`chain`), which gives chains that run across the board instead of
many small clusters. A quarter of the rings nothing grips are closed.

- `bars`: that many cells are left empty and get a bar that pokes into a neighbouring ring's gap
  and, where a ring sits across the cell, is long enough to be stopped by it.
- `tailShare`: tails a quarter turn or more from the gap; each is validated on the board and
  dropped if it starts in something's way or leaves the board.

Nothing here is solvable by construction: whether a board plays through depends on what the
tails and bars hit. About half the attempts are solvable (the solver's verdict on the
rest is "not within the cap", not "impossible"). `ownerPlayout` now also frees an owner that is
still gripped by something else, which is what makes it useful on knots.

Numbers: a 24-piece knot takes 20–26 moves with 15–35 % of pieces free at a time (webs:
40–50 %). Preparation moves are few (0–6): a knot is hard because little can move and the chain
has to be found, a web because several rings have to be lined up. The plan alternates them.

### The plan for 11–100 (`Compositions.templates`)

Levels 1–10 still teach one piece each. From 11 on, by `level % 6`: knot with tails, knot, knot
with bars, tailed hub web, knot with bars and tails, and one change of scene (maze, sun or
bullseye, workshop, sun and moons, planet, diagonal knot). Boards grow in six steps: 9 cells
(11–18), 12 (19–28), 15 (29–40), 18 (41–55), 24 (56–75), 28 (76–100). Every level except the
change of scene is ranked as hard.

**Not verified by play.** None of this was played by the author; the owner's verdict on the
previous three attempts was "too easy" each time, and each time the metrics had said otherwise.
Treat `freedom` and `setupMoves` as hints. If these are still too easy, the next things to try,
in order: more holders per ring with opposite (not adjacent) holders, bars held by clips, U-bars
through two gaps, and free-form (off-grid) knots built like `Tangle`, which are much harder to
read than a grid.

## 10. Pacing: the difficulty curve for 11–100

The owner asked for rising waves instead of a staircase: the overall trend goes up, but
neighbouring levels vary, a hard level is usually followed by relief, there are surprise spikes
and confidence levels, no fixed rhythm, nothing special about every fifth or tenth level, and a
light level late in the game is still more involved than a light one early. The kind of
difficulty should change from level to level too.

**Before.** Scored with the formula below, the previous set was a staircase: six flat steps
(about 27, 35, 45, 55, 68, 80) with a dip on every sixth level. Within a step, level after level
sat at the same height.

**The score** (`DifficultyScore`): 35 % pieces, 25 % moves, 25 % how few pieces are free, 15 %
preparation moves, each clamped. It is the solver's estimate. It has disagreed with the owner's
play before (§7, §9), so it places levels relative to each other; it does not promise how hard
one feels.

**The targets** (`DifficultyCurve.targets`, one number per level): a baseline from 25 to 72,
with phrases of four to seven levels over it that build to a peak and let go. Nine phrase shapes,
drawn at random with small jitter and never the same twice running, so the period keeps
changing. Level 11 starts just under the baseline and level 100 is a peak after a lighter 99.

**The designs** (`Compositions.templates`, one per level): each level gets the design whose
measured score is closest to its target, with penalties for reusing a design, for the same kind
of board as either of the two levels before, and for the same kind of difficulty as the level
before: finding the chain (knots), things in the way (knots with tails), cross-type dependency
(knots or webs with bars), lining rings up (hub webs), ordering bars (mazes, workshops), and
reading a picture (figures, weaves, tangles, sun and moons). The generator then keeps, per
level, the candidate closest to the target. No level is ranked "hard" any more.

Both tables come from `LevelForge/plan-curve.py` (seed 7; pass a JSON of measured scores per
design as the second argument to re-plan from real numbers). Paste its output into the two Swift
tables, then `generate --levels 11-100`.

**Result, checked on the generated set:** mean distance from target 1.8 points, worst 8. Averages
per ten levels: 28, 33, 38, 47, 51, 54, 60, 65, 70. Longest run of rising levels 4; never more
than two hard levels (6+ above baseline) or two light ones in a row; 22 hard and 18 light
levels in 90; 7 of the 18 levels on a multiple of five are hard, which is chance; no board kind
twice running. The largest step up (21 points, 83 to 84) is the return from a deliberate dip to
just above the baseline, not a spike. Level 10 is still the tutorial level that teaches the tail.

## 11. U-bars and bombs

Added at the owner's request for variety ("lots of levels feel similar"). Both are the
competitor's pieces, with the rules agreed with the owner first.

**U-bar** (`PieceKind.uBar`, `DraftPiece.uBar`). A sliding piece with two parallel arms joined
by a crossbar, each arm through its own hub. The engine now treats every segment parallel to a
sliding piece's axis as an arm with a hub at `(0, y)` (`Piece.arms`, `hubOffsets`); a straight
bar or L-bar still has the one arm on the axis, so nothing else changed. The piece is held while
any arm is in its hub, the crossbar can pass no hub, and it leaves once the last arm is out. In
`Knot`, `uBars` takes pairs of neighbouring cells: the arms reach back into the gaps of the two
rings beside the cells (both rings are stuck until the bar is out), and the crossbar stops a
stroke short of whatever sits across, so those pieces have to go first. First seen at level 20.

**Bomb** (`Piece.bomb`, `GameRules.bombRadius`, radius 12 after the owner asked for a bigger one). A round bomb riding on a piece, usually on a
ring's arc. The owner's rule: it goes off the moment it touches another piece, and the explosion
takes the piece it rides on and the piece it touched; whatever those two were holding flies
off and play goes on. That is the whole rule: a version where an explosion ended the level from
level 60 was built on a misreading and removed at the owner's protest ("that is not how the game
works"). For the solver a move that would set off a bomb is
simply blocked (`Board.BlockReason.bomb`), so every level is solvable without an explosion, and
the ring under a bomb can only turn as far as the bomb has room: past a clip touching that ring
it cannot go. Bombs sit on rings that carry no clip of their own and are not poked by a bar, so the ring can turn from the start and the player can actually use the bomb (the owner found bombs on stuck rings useless). About one knot level in four from 26 on, never on two levels
running (`plan-curve.py`); two bombs on some levels from 70.

Yield: boards with bombs are solvable about one attempt in four, U-bar boards about two in
three, so these levels take longer to generate.

Rendering: `PieceNode` draws one hub per arm and the bomb with a lit fuse; the explosion is
`PowerUpEffects.addExplosion`. The level-file format gained `bomb` on a piece.

## 12. Levels 101–150, first version (replaced, see §13)

**Replaced.** The owner played this set through and found level 150 not clearly harder than 100,
and everything "feels similar like all other levels": new grid outlines and more tails do not read
as new. Kept here for what was learned. The third set of fifty, planned by `LevelForge/plan-chapter.py` (seed 30) so that the table for
11–100 and `plan-curve.py` stay exactly as they were. Same rules as §10 and §11: one design per
level, the candidate closest to the target wins, nothing ranked hard.

**The curve.** The waves of §10 continue on a baseline from 67 to 76, peaks capped at 82. That is
lower than the 72 that level 100 reached on paper, on purpose: the score clamps pieces at 28 and
moves at 40, so the heaviest designs measure in the high 70s, and a curve above that only made the
planner put light boards on peaks (a first draft pitched at 70–80 missed its targets by 9 points
on average). What carries on rising is the share of levels with tails and the outlines, not the
number. Level 101 is a warm-up for players coming back after an update; 150 is a peak after a
lighter 149.

**The designs.** Designs already used in 50–100 are scored with what they measured there (read
from `levels-report.json`). New ones were measured with `compose` on four seeds each and recorded
in `LevelForge/chapter-trial-scores.json`:

- knots on the masks with cut corners and holes, which give new outlines: Cut web (`diamond`),
  Stronghold (`final`), Sieve, Riddle and Gaps (Gaps with tails on 60 % of rings);
- webs on Cut web, Sieve, Ports and Stronghold, none used before 101.

Dropped after measuring: knots on Ports and Lace (score 46–48, too light here), knots with three
clips per ring (`clips: 3`, none of four seeds solvable), and bombs on the new outlines (the
builder rarely finds a ring that turns freely from the start, so almost no drafts).

Also dropped, after the first generated set sagged at the end (tens averaging 66, 69, 71, 68,
67): the column knot (18 pieces, measured 44–65 here, which put a 44 on level 149) and the smaller
tight maze. The planner now reads measured scores from 50–150, so rerunning it re-plans from what
the last run produced.

**The planner's rules**, on top of §10's: each reuse of a design and of an outline costs a little
(the first draft had the tall board thirteen times; a stiff penalty then priced the heaviest
designs out of the peaks); every five to eight levels, on a dip, the board changes scene
entirely (maze, cage board, tangle or ring figure); no three knots or three webs running, and webs
cost a little extra, since in a web 40–50 % of the pieces can move and that reads easy (§7);
tails get a small bonus, at the owner's request; bombs about one level in four, often two, only
on the knot boards bombs have worked on before (field, tall, column, grand, twelve).

**Result** (generated, solver-checked, every board looked at): mean distance from target 3.3,
worst 15 (sieve knots with bars come out lighter than planned). Averages per ten levels: 66, 68,
71, 71, 72. 24 knots, 20 webs, 6 changes of scene (three tight mazes, three workshops); tails on 38
levels, bombs on 10 (two bombs on 3 of them). Ten outlines; the tall board 8 times. The webs on
the masks with holes look alike: the holes barely show among 28 rings, so the outline variety is
mostly in the knots.

**Not verified by play**, like every set before it (§9). Worth trying first: 105 and 113 (the
heaviest knots, 80), 124 and 131 (the heaviest webs), 119 and 146 (the sieve knots that measured
light), and 150.

## 13. Levels 101–200: boards without a grid

After §12 the owner chose four new kinds of board, all built by one new builder
(`FreeKnot.swift`, template `Compositions.freeKnot`), and asked for 101–150 to be redone with
them and 151–200 added. He played six samples first and liked them "for the mix up".

**Free-form knots** (template ids `free-…`, names "Wild knot"). Rings of mixed sizes grow out from
a seed; each new ring sits a stem's length from one ring, or from two at once (solved for two
stems along two lattice directions), which gives rings with two holders. Then they are wired like
`Knot`: one ranking, clips downhill. Directions are not free: every contact on a ring must be a
multiple of 45° from the others (§5), so placements run along eight directions turned by a random
angle per board. Distances, sizes and the outline are free.

What it took to make them solvable (each of these was the main failure at some point):

- **Unlinked rings keep 34 apart** (`farClearance`), linked ones 18–22 (`stems`). A ring's own
  clip or tail swings round it when it turns; at the 18 that `Tangle` uses, it caught on the
  unlinked neighbour a few degrees into the turn.
- **Each ring keeps three neighbouring lattice directions free** of links (`keepsGapRoom`), or no
  gap fits beside its clips. The grid gets this for free (four sides, at most three links).
- **Gap width** (`gapWidth`): a held ring that stays behind after a holder lets go (it has another
  holder or clips of its own) needs a gap the holder's clip can swing out of. Only holders that are
  themselves held count (a root just leaves), and only the easier of the two turns.
  `sharedGapRequirement` covers both turns and asked for 140–150° on small rings, which never fit.
- **Rings under radius 30 take one holder at most**; rings placed between two neighbours are 30+.
- Boards with more than 60 connections are refused (the solver keeps them in one 64-bit word).

**Gates** (`gate: true`, "Gates"): tails 30 long, which reach into the circle of a linked
neighbour. The ring can only swing its tail past while that neighbour's gap faces it. Whether a
gate is actually needed depends on the solution; the solver does not report it.

**Giant ring** (`giant: R`): a closed ring at the centre that holds rings inside and outside;
the knot grows inside it (with bars) and around it. Closed, so it only ever holds and leaves last.

**Denser, zoomed-out boards** (`dense: true`, "Thicket"): the same builder on a 432×768 board
(`BoardSize.large`) with 26–32 smaller rings. The level file carries its board size and the scene
scales any board to the screen, so these draw at about 83 %. `LevelDraft`, `LevelTemplate.single`
and `Motif.placed` now take a board; every other generator still uses the standard one.

Measured (`compose`, eight seeds each, in `chapter-trial-scores.json`): on the standard board the
free kinds score 26–38 (their rings do not pack as tightly as a grid's, 16–22 fit), so they serve
as changes of scene; on the large board 50–63, alongside the heavy grid designs. Yields are low on
the large board (one to three seeds in eight solve); the generator's 96 attempts per level cover it.

**The plan** (`plan-chapter.py`, now for any fifty: `101 12` and `151 83`, both from the score
snapshot in `chapter-measured-snapshot.json`, because replanning 101–150 changes the table the
report's scores would otherwise be paired with). New rules: the free kinds count as one broad kind
(no three running) and get a bonus, so about a quarter of the levels use them; the standard-board
ones count as a change of scene; what the previous fifty used counts a quarter against the next.
Planned: 101–150 has 11 boards without a grid, 151–200 has 11; tails on about 42 of every 50;
bombs on 12–13.

**The ceiling.** 151–200 does not rise on the score: the heaviest designs measure in the high 70s
and the score clamps pieces at 28 and moves at 40. Tens average about 66–70 in both halves. What
changes is the kind of board. If the owner finds 151–200 no harder than 101–150, the next step is
not more of these but a different measure of difficulty, or new mechanics.

**Solver and board can disagree.** In the first run, level 110 (a grid knot) had a solution the
real board would not replay: the solver let a ring leave once its last clip was gone, but on the
board it was still touching a neighbour and stayed, and the next move ran into it. Rare (one level
in 200), but it would have shipped an unsolvable level. `LevelGenerator.attempt` now replays every
candidate's solution on the board (`Failure.replayFails`) before accepting it. The underlying
disagreement in the solver is not fixed.

**Not verified by play** beyond the six samples.

## 14. Choosing levels for fun (October 2026)

The owner's brief: the score of §10 measures size and tangle, not how hard a level feels or
whether it is fun, and 151–200 sit flat at 66–71 on it. Without designing levels by hand, measure
"is there a clever moment?" and "is this tedious?", choose candidates by that, and trim pieces that
add nothing. Done in steps, each checked before the next.

### Step 0: determinism

Measurements that are compared across candidates must not depend on the machine, so every limit
now counts work instead of seconds.

- **The exact search stops at a state cap only** (`SolverConfig.stateCap` = 30,000; the time cap
  is gone and `--time-cap` is refused). Measured on sixteen shipped boards from 30 to 200, four
  seconds reached 12–42k states (median about 28k) and none finished; every board ever solved
  exactly needed at most 15k. So generation takes about as long as before, and no exact level
  becomes an estimate. `ownerPlayout` (600 moves) and `bestFirstSolution` (4,000 expansions)
  already had fixed budgets.
- **The job count no longer changes which level wins.** `generate` used to stop after a whole
  batch of `--jobs` seeds, so six jobs could see more candidates than two. Results are now taken
  in seed order and the search stops at the exact seed that made it enough; the rest of the batch
  is thrown away.
- **No timestamps in files.** The report has no `generatedAt` and metrics no longer write
  `elapsed` (the tool still prints it). Older files still decode.
- **Hash order.** Swift seeds `Set` and `Dictionary` hashing per process. Every loop over one in
  `Model/Generation` and `Model/Solver` was checked: each builds another dictionary, sorts first,
  or computes something order-free (counts, BFS distances, `allSatisfy`). None needed changing.
  Every builder makes its own `SplitMix64` from the candidate seed; there is no shared generator.
- `generate --out DIR` writes levels, report and candidates to DIR and leaves the shipped files
  alone (it still reads the shipped report for `--keep-seeds` and the pins).
- `LevelTests` takes `LEVEL_TESTS=1-10,101-110` (as `TEST_RUNNER_LEVEL_TESTS` through xcodebuild)
  for a quick run over some levels.

### Step 1: bot players

`BotLevel` (`Model/Solver/BotPlayer.swift`), settings in `QualityConfig`. A bot with lookahead k
looks k + 1 drags ahead: when some sequence of that many drags takes a piece off, it plays the
first drag of the shortest one, breadth first in the solver's move order; otherwise it drags at
random. It plays on a real `Board` with `Board.move` (the replay's call) and searches with
`LevelSolver.successors`; each independent part of the board is searched on its own. A lookahead
may expand 400 positions (`lookaheadBudget`); positions worked out in one game are reused by the
next. A game is lost after 3 × `minMoves` + 20 drags. `forge bots --levels …` prints, per bot,
the share of 20 games won, the median length of a won game, the mean number of blind drags (no
piece to take off within the lookahead), and the share won within 1.5× and 1.2× the recorded
solution.

Measured on the shipped levels 11–200 (all four bots, 20 games each):

- **Only hub webs need foresight.** The 2-deep bot makes on average 20.6 blind drags per game on
  the 39 hub webs and about one on knots and thickets (0.98, 0.95); on mazes, cages, weaves,
  tangles, giant rings and the two wild knots it never drags blind. On every level that is not a
  web, a piece can come off within two drags from almost every position. That fits the owner's
  verdict that 101–200 are not harder than 100.
- **Even the bot without foresight wins most games.** It takes what comes off and drags at random
  otherwise, and loses any games at all on only 50 of 190 levels. With the 3 × + 20 limit, the
  bots that look two or more drags ahead win at least 80 % of the games on every level, so the
  tier as first defined would be 0 or 1 everywhere.
- **The 4-deep bot adds nothing** over the 3-deep one on any level and takes 43 % of the time.
- **Cost.** About 0.5 s per level for all four bots, except webs: up to 516 s (level 125), almost
  all of it in the 3- and 4-deep bots on blind positions. All 190 levels took 47 minutes on one
  core.
- **The board refused drags the solver offered** (302 over all levels, in 46 levels with sliding
  bars). The solver keeps a sliding bar's offset rounded to half a unit; a bar pushed until it
  stops ends at, say, 31.24, the solver rebuilds it at 31.0, just clear of its blocker, and offers
  another push the real board refuses. This is very likely what made level 110's first solution
  fail to replay (§13). The bot treats a refused drag as unavailable and chooses again. Fixed in
  the solver next.

### Bar precision

The solver stored a sliding bar's offset in half units. The board samples a push every 2 units
from wherever the bar starts, so a bar the solver rebuilds even slightly off its real spot can
step over a thin edge the real bar catches (level 27: bar l3 at 17.571 on the board, 17.578 in the
solver; pushed out of its hub, the board's samples hit b3, the solver's miss it). The state now
keeps every bar's exact offset, and two states are the same position when their offsets agree on
a 1/4096 grid (`LevelSolver.slideScale`): the grid only decides what counts as visited, while a
board rebuilt from a state is exactly the board its moves came from. The bot's caches key on the
exact offsets, as does the solver's sweep cache. (The owner asked for a 1/64 grid; that alone
still left 156 refused drags, a 1/4096 grid left none but some drags landed one grid step off;
exact offsets leave nothing, which is what the owner asked for as the option.)

Checked on all 113 shipped levels with bars, solving each and walking 400 real boards breadth first
(about 1.5 million solver drags offered):

| solver keeps | refused drags | levels with any | landed elsewhere | solve time |
|---|---|---|---|---|
| half units (before) | 3,933 | 83 | 6,094 | 595 s |
| 1/64 grid | 156 | 7 | 4,347 | 585 s |
| 1/4096 grid | 0 | 0 | 5,384 (one step off) | 576 s |
| exact offsets, 1/4096 identity | 0 | 0 | 0 | 620 s |

No level's move count changes and every recorded solution still replays. Levels 15 and 25 are no
longer solved exactly: bars that used to share a half-unit cell are now told apart, so their
graphs pass the state cap (both keep their move count; regenerating them would mark them ≈).
`SolverTests.solverMovesAreAcceptedByTheBoard` walks eight bar levels this way and requires every
drag to be accepted and to land exactly where the solver said.


### Step 2: quality measurements

`LevelQuality` (`Model/Generation/LevelQuality.swift`), every weight and threshold in
`QualityConfig`. Measured for the chosen level and its runner-ups only, in parallel, and written as
`quality` next to the legacy `difficulty` in each report candidate (the report also records the
`qualityConfig` and formula). `generate --no-quality` skips it, `--trap-rate` adds traps.
`forge report [--dir DIR] [--levels …]` prints the columns.

- **Bots.** Three now (looking 1, 2 and 3 drags ahead); the 4-deep one never beat the 3-deep one.
  For each, over 20 games: win rate, mean blind drags, and the median over games of blind drags
  per piece taken off (`blindRate`), so a big board does not score higher just for being big.
- **tier**: the shallowest bot whose median game makes at most 0.05 blind drags per piece
  (`plannedBlindRate`): that bot plans the level instead of trying things. 3 when none does.
- **insightGap**: how far the blind rate drops at that bot from the next shallower one, capped at 1
  (`insightGapScale` = 1). Tier 0 has none, and neither has a level no bot plans: at first that
  case took the drop into the deepest bot, which gave the trial-and-error webs 150 and 180 the
  highest interest of all (0.98, 0.99). Such levels are flagged **unplanned** instead, so they
  stay visible until the owner has played them; the planners must not use them as peaks yet.
- **forcedShare**: share of solution steps where exactly one piece can release a connection or
  come off, the test `freedom` uses (`LevelSolver.openness`).
- **setupDepth**: the longest run of solution moves that take nothing off.
- **trapRate** (only with `--trap-rate`, weight 0): at up to 8 positions along the solution, the
  share of moves after which best-first search with 300 expansions finds no way to finish.
- **strategySolved**: whether `ownerPlayout` clears every component on its own, without the
  best-first fallback.
- **difficulty** = 100 · (0.4 · tier/3 + 0.4 · minMoves/60 + 0.2 · setupDepth/8), no cap.
  **interest** = 0.6 · insightGap + 0.4 · (1 − forcedShare) (+ 0 · trapRate).

Measured on the shipped 101–200, rebuilt from their seeds (`generate --levels 101-200 --keep-seeds
--out …`, 71 minutes with six jobs, about 30 s a level of which most is solving four candidates;
the rebuilt boards and metrics are identical to the shipped ones):

| | legacy | difficulty | interest | tier 0/1/2/3 | strategySolved |
|---|---|---|---|---|---|
| 101–150 | 69.3 | 38.6 | 0.47 | 9 / 28 / 9 / 4 | 38 of 50 |
| 151–200 | 66.9 | 38.6 | 0.46 | 9 / 24 / 12 / 5 | 33 of 50 |

| kind | levels | difficulty | interest | tier 0/1/2/3 | forcedShare |
|---|---|---|---|---|---|
| hub web | 24 | 59.8 | 0.67 | 0 / 2 / 13 / 9 | 0.07 |
| grid knot | 45 | 36.8 | 0.42 | 4 / 35 / 6 / 0 | 0.28 |
| giant ring | 3 | 31.4 | 0.48 | 0 / 3 / 0 / 0 | 0.20 |
| thicket | 19 | 28.4 | 0.38 | 5 / 12 / 2 / 0 | 0.27 |
| maze | 4 | 16.7 | 0.33 | 4 / 0 / 0 / 0 | 0.17 |
| cage | 5 | 14.2 | 0.25 | 5 / 0 / 0 / 0 | 0.37 |

- **The new difficulty is set by the kind of board.** Webs need the 3-deep bot, knots and
  thickets the 2-deep one, mazes and cages none: every bot clears them without a blind drag. The
  legacy score rates cages at 66, the new one at 14.
- **151–200 is not harder than 101–150** on average (38.6 both). Inside 151–200 it rises
  (+17 over the 50 levels, r = 0.30, legacy +5), only because more webs sit late (10 of 176–200
  are tier 2).
- **Webs split into planned and trial-and-error.** On 15 of the 24 the 3-deep bot never drags
  blind; on 9 (123, 125, 135, 150, 164, 170, 180, 192, 200) it still makes 0.2–1.5 blind drags per
  piece, no better than the 2-deep bot on 135 and 170.
- **strategySolved does not separate webs**: the owner-release strategy clears all 24 of them.
  It is false mostly on knots and thickets (29 of the 100 levels).
- **Lowest interest**: cages 145, 130, 178, knots 162, 154, thicket 118 — forced at almost
  every step, or nothing to see in advance.

### Step 3: choosing by interest

`LevelGenerator.chooseByInterest`, settings in `QualityConfig` (`band` 6, `finalists` 4). Only for
curve levels without a pin; tutorial levels and pins are chosen as before, and there are no hard
levels left. The targets are still on the legacy scale, so the band is too:

1. The search stops once four candidates are within ±6 legacy points of the target (it used to
   stop at the first within ±5), or at the usual budget of 16 candidates.
2. The four closest to the target (the old ranking) are the finalists, and only they get the bot
   profile. The rest of the search costs what it did.
3. Among the finalists within the band the highest interest wins, rounded to 0.01 so that near
   ties go to a level the owner-release strategy cannot clear by itself (`strategySolved` false),
   then to fewer pieces, then the seed. The other three are the runner-ups.
4. With no finalist in the band the closest one is taken and the report marks the level
   `outOfBand`.

There is no interest threshold for stopping early: it would mean profiling more than four
candidates.

Generated afresh (no `--keep-seeds`) for 101–120 and 151–160 into a scratch folder, compared with
the shipped choices measured the same way:

- 15 of 30 levels pick a different board, always of the planned design. Mean interest rises from
  0.41 to 0.47; the mean distance to the target grows from 4.4 to 5.0 points.
- 8 of 30 are out of band (106, 107, 111, 119, 156, 157, 159, 160): 16 candidates of the planned
  design never came within 6 points (107 and 157, Wild knot, sit at 44 against 58). They were
  mostly out of band when shipped as well; it is a planning matter (Step 1).
- Time: 62 s a level on average (median 50 s, most 153 s) with six jobs, against about 30 s when
  only rebuilding: the search goes on until four candidates are in the band.
- The choice is the same with two jobs as with six.
- The cap on insightGap shows: on webs the bot that only takes what comes off flounders (3–6
  blind drags a piece), so a web the 2-deep bot already plans gets a gap of 1 and an interest
  near 1. At 115 that picks a tier-1 web (interest 0.98) over the shipped tier-2 one (0.71). To be
  judged against the owner's play-test before the weights change.

## 15. Variety: boards that look designed (October 2026)

The owner's second brief: levels 91–110 look alike (8 of 10 in 91–100 are the same 4-column field;
101–110 ping-pong between free-form and grid), free-form boards have no shape, grid holes look
like missing pieces, nothing is symmetric or small, milestones are ordinary. More visual variety
and designed-looking boards without designing levels by hand, every new board still through
validate → solve → replay → bots. Nothing copied from the competitor.

### Step 0: contact sheets

`forge render [--levels 11-200] [--dir DIR] [--out DIR] [--candidates]` (`LevelForge/Render.swift`)
writes one PNG per block of ten levels with CoreGraphics, from the model's own world geometry:
rings and bars in their colours, clips white, hubs grey, bombs black. Under each board: number,
name, piece count, design (template id), legacy score against the target, and when the report has
them the new difficulty, interest and tier (`u` for unplanned). `--candidates` draws a row per
level with its runner-ups. Sheets go to `LevelForge/sheets/` (git-ignored) unless `--out` says
otherwise: `before/` holds the shipped 11–200, `step3/` the Step 3 sample. LevelForge now has two
source files; build it with
`swiftc -O LevelForge/*.swift $(find RotateRings/Model -name '*.swift')`.

The "before" reference is the shipped 11–200 rebuilt from their seeds with quality measured
(`generate --levels 11-200 --keep-seeds --out …`, 2 h 8 min with six jobs). All 190 boards are
byte-identical to the shipped files; 16 bar levels record slightly different drag lengths (exact
bar offsets) with the same move counts, and level 18 scores 23 instead of 28 (found under the
state cap instead of the old time cap).

Measured over 11–200 by kind of board:

| kind | levels | legacy | difficulty | interest | tier 0/1/2/3 | unplanned |
|---|---|---|---|---|---|---|
| hub web | 39 | 67 | 58 | 0.54 | 0/4/19/16 | 16 |
| grid knot | 91 | 60 | 34 | 0.46 | 6/73/11/1 | 1 |
| giant ring | 3 | 59 | 31 | 0.48 | 0/3/0/0 | 0 |
| thicket | 17 | 65 | 29 | 0.37 | 5/10/2/0 | 0 |
| wild knot | 2 | 44 | 26 | 0.49 | 0/2/0/0 | 0 |
| maze | 14 | 53 | 14 | 0.28 | 14/0/0/0 | 0 |
| cages | 11 | 60 | 13 | 0.30 | 11/0/0/0 | 0 |
| weave figure | 7 | 37 | 10 | 0.35 | 7/0/0/0 | 0 |
| tangle | 4 | 36 | 10 | 0.27 | 4/0/0/0 | 0 |

By chapter the new difficulty is 23 (11–50), 34 (51–100), 39 (101–150), 39 (151–200).

What the bots say about foresight, as the base for Step 1b: only hub webs need it. A hub is a
closed ring pinned by its own clips; it leaves only when every ring it grips has its gap on the
hub's clip at the same moment, and a ring shared by two hubs serves one at a time. Raising a grid
knot's holders, clips per ring and share of closed rings does not get there: six seeds each of
four settings on the tall field stayed at tier 0–1, with one unplanned board. The shipped web
settings are a lottery: of six seeds, two were planned by the 2-deep bot, one by the 3-deep bot,
three by none.

### Step 1b: locks and foresight

**Locks** (`Knot.Options.locks`, `lockClips`; `knot(…, locks: N)`): closed rings that grip two or
three neighbours and are gripped by nothing, ranked above every ring, as the hubs of a web. A lock
never turns and leaves only when all the rings it grips have their gaps on its clips at once; each
further lock sits two cells from an earlier one, so the two share the ring between them.

Measured with the bots (8–12 seeds per setting, full pipeline):

| board | valid | tier 0/1/2/3u | difficulty | interest |
|---|---|---|---|---|
| 3×3 knot, 1 lock (`hubs-nine`) | 14/20 | 2/11/1/0 | 21 | 0.63 |
| 3×4 knot, 1 lock (`hubs-twelve`) | 7/20 | 1/4/2/0 | 25 | 0.51 |
| field knots, 1–3 locks | 12/24 | 7/5/0/0 | 21 | 0.41 |
| tall and gaps knots, 1–3 locks | 17/48 | 7/10/0/0 | 26 | 0.38 |
| field and tall knots, 2–4 locks of 3–4 clips, many tails | 16/72 | 2/13/1/0 | 36 | 0.46 |

- **On a small board a lock is the puzzle.** On the 3×3 knot the bot that only takes what comes off
  makes about one blind drag per piece and the 2-deep bot none: one thing to see (interest up to
  0.88). That is the lock introduction: `knot("hubs-twelve", holders: 2, locks: 1)` or the nine.
- **On a big knot a lock is a moment, not a tier.** There is nearly always something else to take
  off, so no bot gets stuck; a lock lifts a board from tier 0 to 1 at most. Stronger locks (3–4
  clips, more tails) mostly make boards unsolvable. Locks stay a modifier: none on breathers, one
  off-peak, two or three at peaks.
- **Foresight lives in webs, and the clips per hub set how much.** On the tall field, 3–4 clips
  and 3 holders (shipped) gave tier 2 on 5 of 8 boards and unplanned on 3; 2–3 clips gave 4 and 1;
  2–3 clips with 2 holders gave tier 1 on 7 of 8.

**Webs with an outline** (`webShapes`, five small rings across on the large board, stem 18 so
they fit): Gem, Cross, Arch, Hourglass, Heart, Frame. Look family `hubShape`, so they do not count
as grid fields. Twelve seeds each:

| outline | 3–4 clips: tier 0/1/2/3u, difficulty | 2–3 clips: tier 0/1/2/3u, difficulty |
|---|---|---|
| Gem | 0/1/8/3, 52 | 0/4/6/2, 46 |
| Heart | 0/0/10/2, 53 | 0/10/2/0, 36 |
| Arch | 0/2/7/3, 59 | 0/8/3/1, 45 |
| Hourglass | 0/1/6/5, 59 | 0/9/3/0, 40 |
| Frame | 0/1/6/5, 62 | 0/10/1/1, 42 |
| Cross | 0/1/2/9, 64 | 0/6/5/1, 46 |

With 3–4 clips Gem and Heart are the most reliably planned peaks; Cross is mostly unplanned. With
2–3 clips every outline is a mid-difficulty board the 2-deep bot plans (interest 0.61–0.89).

### Step 1: look families and re-planning on the new difficulty

**Look families** (`Look`, `Model/Generation/Looks.swift`, derived from the template id):
gridField (square-grid knots), gridBars (knots with U-bars), diagonal (knots and webs on the
diagonal grid), freeform (wild knots, gates, thickets, tangles), barMaze (mazes, cages, workshops),
figure (ring figures, weaves, bullseye), hub (webs on a rectangle), hubShape (webs with an outline),
giant (giant ring, planet, sun), and picture and small for later steps. A web on a rectangle
looks like a grid field and counts as one for spacing.

**One catalogue, measured.** `Compositions.catalogue` (`DesignCatalogue.swift`, generated by
`LevelForge/catalogue.py`) lists every design the planners may choose under the exact expression
they write into `Compositions.templates`: the 97 designs of the old table and old planners, the
outlined webs, webs with 2–3 clips on the tall field and field, the lock introductions, and knots
with 1–3 locks. `forge designs` builds 8 seeds of each through the whole pipeline with the bots and
writes `LevelForge/design-quality.json` (mean difficulty, interest, legacy score, boards per tier,
unplanned share, pieces, time); designs with fewer than three valid boards were measured again with
32 seeds (`--retry-below 3`). 151 designs, 1 still short of data (column knot with three locks,
which the planners skip). One run: 35 + 27 minutes with all cores.

What the catalogue measures, by family: barMaze 6–15, figure 5–13, giant 7–19, freeform 6–20,
gridBars 20–34, gridField 14–41, diagonal 10–52, hub 27–65, hubShape 36–64. Every board without
hubs stays under about 41; only webs reach higher. (Shipped thickets measured about 29 because they
were the heaviest of their candidates; a random thicket measures 10–20.)

**The planners** (`plan-curve.py` for 11–100, `plan-chapter.py` for 101–150 and 151–200, shared
rules in `planlib.py`) take the catalogue and each design's usual difficulty from that file, and
`--apply` writes the plan into `Compositions.templates` and `DifficultyCurve.targets`, which now say
they are on the new scale (`DifficultyCurve.onQualityScale`). Targets, waves as before (§10) at full
size: 11–100 rise from 12 to 30, 101–150 from 28 to 34 (peaks to 60), 151–200 from 32 to 40 (peaks
to 64). A level is a peak at +6 or more, a dip below 0. Rules, hard where they can be:

- never the same family within three levels (a rectangular web counts as a grid field); at least
  five families in a block of ten (a new family is welcome early, a fourth of one family is not);
  grid fields at most 40 % of a chapter;
- every five to eight levels a dip is a change of scene: a maze or cage, figure, giant ring or
  free-form board, the heaviest that does not overshoot, and not the family of the last two
  scenes; mazes and cages appear nowhere else;
- webs are favoured at peaks; a design unplanned on more than half its boards never sits at a peak;
- locks: none on dips, two or three only at peaks, from level 30, and the first lock level is an
  introduction, one lock on a 3×3 or 3×4 knot;
- bombs on knot boards about one level in four (fatal from 60), never two running; U-bars from 20,
  outlined webs from 40; the last level of 101–150 and 151–200 is heavy and planned.

**Generation** chooses on the new scale too: the search ranks candidates by a predicted difficulty
(the design's usual tier from `design-quality.json` with the candidate's own moves and setup depth),
stops at four within ±6 of the target, profiles the four closest, and checks the band on what they
measured. `generate --keep-same-designs` rebuilds from the shipped seeds where a level keeps its
design.

Planned with `plan-curve.py 7`, `plan-chapter.py 101 30` and `plan-chapter.py 151 31`, then
generated whole into a scratch folder with `--keep-same-designs` (96 minutes, six jobs; 9 levels
kept their design and were rebuilt from their seeds, 181 were generated afresh). Contact sheets in
`LevelForge/sheets/step1/`, the shipped levels in `before/`.

| | old 11–100 | new 11–100 | old 101–150 | new 101–150 | old 151–200 | new 151–200 |
|---|---|---|---|---|---|---|
| same family within three levels | 99 levels over all of 11–200 | 0 | | 0 | | 0 |
| grid fields (with rectangular webs) | 49 % | 27 % | 62 % | 30 % | 62 % | 32 % |
| families per block of ten | 4–6 | 5–8 | 3–5 | 5–7 | 3–6 | 5–6 |
| difficulty, mean | 29.2 | 22.4 | 38.6 | 31.3 | 38.6 | 32.9 |
| interest, mean | 0.43 | 0.54 | 0.45 | 0.63 | 0.43 | 0.69 |
| unplanned levels | 8 | 0 | 4 | 0 | 5 | 0 |

- **Out of band**: 43 of 190 levels end more than 6 points from their target. 19 are changes of
  scene, low on purpose. Of the other 24, 8 are peaks that came out low (100, 113, 135, 163, 169,
  181, 200 and 23); of the 24, 14 are knots and 9 webs (five of them the diagonal Woven web).
- **Why peaks come out low.** The webs the planner puts at peaks have an average difficulty near
  the target, but a web is either one the 2-deep bot plans (32–38) or one only the 3-deep bot plans
  (50 and up), never in between. The four finalists are picked by predicted difficulty, which cannot
  tell the two apart, so at many peaks all four were of the lighter kind: 24 of the 35 webs at peaks
  are tier 1.
- **Locks**: 21 levels, the introduction at level 30 (one lock on the 3×3 knot, interest 0.88).
- **Difficulty is lower than before on every chapter**, because the targets now follow what the
  boards measure rather than the legacy score; it still climbs chapter by chapter.
