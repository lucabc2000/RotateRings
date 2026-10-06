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
level 50) and the one with the most `setupMoves` wins, then the lowest `freedom`. Seeds are deterministic (`candidateSeed`), but solver metrics
depend on an 8-second time cap, so a rerun can pick a different candidate when two are close.

## 4. Workflow

Build the tool (fast, no Xcode UI needed):

```
swiftc -O -o /tmp/forge LevelForge/main.swift $(find RotateRings/Model -name '*.swift')
```

Commands (paths are resolved from the repo root):

```
/tmp/forge compose tangle-6-8 planet-9-12-locked --count 4 --out DIR [--time-cap 2] [--verbose] [--keep-stuck]
/tmp/forge probe --levels 16-20 --count 4            # why each seed of a level does or does not work
/tmp/forge generate --levels 16-50 --jobs 6          # regenerate; keeps the other levels' files
/tmp/forge generate --levels 18,35 --keep-seeds      # rebuild from the recorded seeds after a rule change
/tmp/forge diagnose DIR/x.json                       # play greedily; explain what blocks what is left
/tmp/forge solve RotateRings/Levels/level33.json     # metrics for one file
/tmp/forge report                                    # the level table
```

`compose` lists every template id when called without one. Template ids are what the report's
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
to find them (8 s per unsolvable candidate), so generators check them up front.

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

