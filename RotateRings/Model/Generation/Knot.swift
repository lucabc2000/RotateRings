//
//  Knot.swift
//  RotateRings
//
//  Boards where most rings both hold and are held, the way the competitor's harder levels are
//  wired (LEVEL-DESIGN.md §9). On a grid, neighbouring rings are joined by clips that all point
//  "downhill" in one random ranking, so the wiring has no circular waits. A ring carries up to two
//  clips of its own and is gripped by up to two or three others.
//
//  What that does to play: a ring whose own clip still grips cannot turn, so at the start only the
//  rings at the bottom of the ranking move. A ring held by two can let only one holder go at a
//  time, and that holder has to turn away (or leave) before the ring goes on to the next, or it is
//  gripped again. A holder can turn only once everything it grips has its gap on its clips at the
//  same moment. Let-go clips stay on their ring and swing with it, so they get in the way.
//
//  Whether a board plays through depends on what those clips, tails and bars hit, which only the
//  solver can tell; boards that do not are thrown away by the generator.
//

import Foundation

enum Knot {
    struct Options {
        /// Chance that two neighbouring rings are joined.
        var linkChance = 0.85
        /// Most clips gripping one ring.
        var maxHolders = 2
        /// Most clips one ring carries.
        var maxClips = 2
        /// Most links of both kinds on one ring; the fourth side is left for the gap.
        var maxLinks = 3
        /// Chance that a ring nothing grips is closed.
        var anchorChance = 0.25
        /// How strongly the ranking follows the distance from one corner of the board (0 is a
        /// random ranking). A ranking that runs across the board gives long chains: few rings can
        /// turn at the start and each one frees the next.
        var chain = 0.7
        /// Share of rings that get a tail.
        var tailShare = 0.0
        /// Cells left empty for a bar. The bar pokes into a neighbouring ring's gap, so that ring
        /// cannot turn until the bar is slid out, and where a ring sits across the cell the bar is
        /// long enough to be stopped by it: that ring has to go first.
        var bars = 0
        /// U-bars: pairs of neighbouring cells left empty, with one bar whose two arms poke into the
        /// gaps of the two rings beside them. Both rings are stuck until it is out, and it only
        /// slides away from them.
        var uBars = 0
        /// Bombs riding on rings. A bomb goes off when it touches another piece, so the ring can
        /// only turn as far as the bomb has room; the solver never sets one off.
        var bombs = 0
        var name = "Knot"
        var template = "knot"
    }

    private struct Cell: Hashable {
        var c: Int
        var r: Int
        func moved(_ step: Cell) -> Cell { Cell(c: c + step.c, r: r + step.r) }
    }

    static func build(_ shape: RingNet.Shape, options: Options, rng: inout SplitMix64) -> Motif? {
        let grid = shape.rows.map { Array($0) }
        let rowCount = grid.count
        guard let colCount = grid.map(\.count).max(), colCount > 0 else { return nil }
        let reach = 2 * shape.radius + shape.stem
        let pitch = shape.layout == .square ? reach : reach / 2.0.squareRoot()
        let steps: [Cell] = shape.layout == .square
            ? [Cell(c: 1, r: 0), Cell(c: 0, r: 1)]
            : [Cell(c: 1, r: 1), Cell(c: -1, r: 1)]
        func position(_ cell: Cell) -> Point {
            Point((Double(cell.c) - Double(colCount - 1) / 2) * pitch, (Double(rowCount - 1) / 2 - Double(cell.r)) * pitch)
        }
        func id(_ cell: Cell) -> String { "k\(cell.r)_\(cell.c)" }

        var sites: [Cell] = []
        for r in 0..<rowCount {
            for c in 0..<grid[r].count where grid[r][c] == "#" { sites.append(Cell(c: c, r: r)) }
        }
        // Cells given up for bars: not next to each other, so every one has rings around it.
        let around = [Cell(c: 1, r: 0), Cell(c: -1, r: 0), Cell(c: 0, r: 1), Cell(c: 0, r: -1)]
        let allSteps = shape.layout == .square ? around : [Cell(c: 1, r: 1), Cell(c: -1, r: 1), Cell(c: 1, r: -1), Cell(c: -1, r: -1)]
        var holes: [Cell] = []
        /// Pairs of cells for a U-bar and the direction from the rings into the cells.
        var uSites: [(first: Cell, second: Cell, direction: Cell)] = []
        for cell in sites.shuffled(using: &rng) where uSites.count < options.uBars {
            for direction in allSteps.shuffled(using: &rng) {
                let across = Cell(c: direction.r, r: direction.c)
                let second = cell.moved(across)
                guard sites.contains(second), !holes.contains(cell), !holes.contains(second),
                      sites.contains(Cell(c: cell.c - direction.c, r: cell.r - direction.r)),
                      sites.contains(Cell(c: second.c - direction.c, r: second.r - direction.r)),
                      !allSteps.contains(where: { holes.contains(cell.moved($0)) || holes.contains(second.moved($0)) }) else { continue }
                uSites.append((cell, second, direction))
                holes += [cell, second]
                break
            }
        }
        let uCells = Set(holes)
        for cell in sites.shuffled(using: &rng) where holes.count < options.bars + 2 * uSites.count {
            if allSteps.contains(where: { holes.contains(cell.moved($0)) }) || holes.contains(cell) { continue }
            if allSteps.filter({ sites.contains(cell.moved($0)) }).count < 2 { continue }
            holes.append(cell)
        }
        sites.removeAll(where: holes.contains)
        guard sites.count >= 3 else { return nil }

        // One ranking of all rings: a clip always runs from the higher ring to the lower.
        let origin = rng.pick(sites)
        var score: [Cell: Double] = [:]
        for cell in sites {
            let distance = Double(abs(cell.c - origin.c) + abs(cell.r - origin.r)) / Double(colCount + rowCount)
            score[cell] = options.chain * distance + (1 - options.chain) * Double(rng.int(in: 0...1000)) / 1000
        }
        var rank: [Cell: Int] = [:]
        for (index, cell) in sites.sorted(by: { (score[$0]!, $0.r, $0.c) < (score[$1]!, $1.r, $1.c) }).enumerated() { rank[cell] = index }

        var pairs: [(Cell, Cell)] = []
        for cell in sites {
            for step in steps where rank[cell.moved(step)] != nil { pairs.append((cell, cell.moved(step))) }
        }
        var holders: [Cell: [Cell]] = [:]
        var targets: [Cell: [Cell]] = [:]
        func links(_ cell: Cell) -> Int { (holders[cell]?.count ?? 0) + (targets[cell]?.count ?? 0) }
        func join(_ a: Cell, _ b: Cell) -> Bool {
            let (owner, target) = rank[a]! > rank[b]! ? (a, b) : (b, a)
            guard links(owner) < options.maxLinks, links(target) < options.maxLinks,
                  (targets[owner]?.count ?? 0) < options.maxClips, (holders[target]?.count ?? 0) < options.maxHolders else { return false }
            targets[owner, default: []].append(target)
            holders[target, default: []].append(owner)
            return true
        }
        var skipped: [(Cell, Cell)] = []
        for pair in pairs.shuffled(using: &rng) {
            if rng.chance(options.linkChance) { _ = join(pair.0, pair.1) } else { skipped.append(pair) }
        }
        // No ring may be left on its own: it would leave on load.
        for pair in skipped where links(pair.0) == 0 || links(pair.1) == 0 { _ = join(pair.0, pair.1) }
        let rings = sites.filter { links($0) > 0 }
        guard rings.count >= 3 else { return nil }

        var draft = LevelDraft(name: options.name, template: options.template)
        var closed = Set<Cell>()
        for ring in rings {
            if holders[ring] == nil, rng.chance(options.anchorChance) {
                closed.insert(ring)
                draft.pieces.append(.closedRing(id(ring), at: position(ring), radius: shape.radius))
            } else {
                draft.pieces.append(.ring(id(ring), at: position(ring), radius: shape.radius))
            }
        }
        for ring in rings {
            for target in targets[ring] ?? [] {
                guard draft.addRingClip(from: id(ring), to: id(target)) else { return nil }
            }
        }

        // Gaps.
        var gapAt: [Cell: Int] = [:]
        // A gripped ring's gap is wide enough for a let-go clip to swing out of it, but never spans
        // two clips: holders are let go one at a time.
        func widths(_ ring: Cell) -> [Double] {
            holders[ring] == nil ? [ForgeRules.defaultGapDegrees]
                : [draft.sharedGapRequirement(for: id(ring), together: false), ForgeRules.defaultGapDegrees]
        }

        /// Whether the board as drafted so far loads, with nothing in a collision or off the board.
        func stands(_ pieces: [DraftPiece]) -> Bool {
            let motif = Motif(name: options.name, template: options.template, pieces: pieces)
            return (try? LevelDraft(name: options.name, template: options.template, pieces: motif.placed(at: ForgeRules.center)).validate()) != nil
        }

        // Bars first: the ring a bar pokes has its gap facing the bar. U-bars take two rings each.
        var bars: [DraftPiece] = []
        var pokedRings = Set<Cell>()
        let pokeStart = shape.radius - 10
        for site in uSites {
            let ringA = Cell(c: site.first.c - site.direction.c, r: site.first.r - site.direction.r)
            let ringB = Cell(c: site.second.c - site.direction.c, r: site.second.r - site.direction.r)
            guard rings.contains(ringA), rings.contains(ringB), !closed.contains(ringA), !closed.contains(ringB),
                  gapAt[ringA] == nil, gapAt[ringB] == nil,
                  let indexA = draft.index(of: id(ringA)), let indexB = draft.index(of: id(ringB)) else { continue }
            let direction = (position(site.first) - position(ringA)).normalized()
            let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: direction.angle))
            guard let widthA = widths(ringA).first(where: { draft.gapIsValid(centerDegrees: degrees, gapDegrees: $0, for: id(ringA)) }),
                  let widthB = widths(ringB).first(where: { draft.gapIsValid(centerDegrees: degrees, gapDegrees: $0, for: id(ringB)) }) else { continue }
            draft.pieces[indexA].setGap(centerDegrees: degrees, degrees: widthA)
            draft.pieces[indexB].setGap(centerDegrees: degrees, degrees: widthB)
            gapAt[ringA] = Int((degrees / ForgeRules.gridDegrees).rounded()) % 8
            gapAt[ringB] = gapAt[ringA]
            pokedRings.formUnion([ringA, ringB])
            // Hubs in the two cells; the arms reach back into the rings' gaps and the crossbar stops
            // a stroke short of whatever sits across the cells.
            let center = (position(site.first) + position(site.second)) * 0.5
            bars.append(.uBar("u\(bars.count)", at: center, width: position(site.first).distance(to: position(site.second)),
                              from: -(pitch - pokeStart), to: pitch - shape.radius - GameRules.strokeThickness - 2, angleDegrees: degrees))
        }
        for hole in holes where !uCells.contains(hole) {
            // Prefer a ring with another ring across the hole, which stops the bar.
            let choices = allSteps.shuffled(using: &rng).sorted { a, _ in rings.contains(hole.moved(a)) }
            for step in choices {
                let ring = Cell(c: hole.c - step.c, r: hole.r - step.r)
                guard rings.contains(ring), !closed.contains(ring), gapAt[ring] == nil, let index = draft.index(of: id(ring)) else { continue }
                let direction = (position(hole) - position(ring)).normalized()
                let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: direction.angle))
                guard let width = widths(ring).first(where: { draft.gapIsValid(centerDegrees: degrees, gapDegrees: $0, for: id(ring)) }) else { continue }
                let blocked = rings.contains(hole.moved(step))
                let exitTravel = GameRules.holderLength / 2 + 1 + GridWorld.hubInset
                let end = blocked ? 2 * reach - shape.radius - exitTravel - 2 : reach
                guard end - pokeStart >= 2 * GridWorld.hubInset else { continue }
                draft.pieces[index].setGap(centerDegrees: degrees, degrees: width)
                gapAt[ring] = Int((degrees / ForgeRules.gridDegrees).rounded()) % 8
                pokedRings.insert(ring)
                bars.append(.slideBar("bar\(bars.count)", at: position(ring) + direction * (pokeStart + GridWorld.hubInset),
                                      from: -GridWorld.hubInset, to: end - pokeStart - GridWorld.hubInset, angleDegrees: degrees))
                break
            }
        }

        for ring in rings where !closed.contains(ring) && gapAt[ring] == nil {
            guard let index = draft.index(of: id(ring)) else { return nil }
            let widths = widths(ring)
            var placed = false
            for width in widths {
                let choices = (0..<8).filter {
                    draft.gapIsValid(centerDegrees: Double($0) * ForgeRules.gridDegrees, gapDegrees: width, for: id(ring))
                }
                guard !choices.isEmpty else { continue }
                let choice = rng.pick(choices)
                draft.pieces[index].setGap(centerDegrees: Double(choice) * ForgeRules.gridDegrees, degrees: width)
                gapAt[ring] = choice
                placed = true
                break
            }
            guard placed else {
                LevelTemplate.debug?("\(options.template): no gap for \(id(ring))")
                return nil
            }
        }

        draft.pieces += bars

        // Bombs, on the arc of a ring that can turn from the start: one that carries no clip of its
        // own and is not poked by a bar, so the player can actually use the bomb (turn it into a
        // neighbour and take two pieces off). Well away from the gap and from every clip touching
        // the ring; where the bomb would touch something at the start it is left off. The solver
        // then decides whether the ring can still do what it must without setting it off.
        if options.bombs > 0 {
            var placed = 0
            let free = rings.filter { !closed.contains($0) && (targets[$0] ?? []).isEmpty && !pokedRings.contains($0) }
            for ring in free.shuffled(using: &rng) where placed < options.bombs {
                guard let index = draft.index(of: id(ring)) else { continue }
                let piece = draft.pieces[index]
                let gap = piece.gapCenterDegrees
                let gapHalf = (piece.gapDegrees ?? 0) / 2
                let busy = draft.contactAngles(on: id(ring)) + draft.stemRootAngles(of: id(ring))
                let choices = (0..<8).map { Double($0) * ForgeRules.gridDegrees }.filter { angle in
                    (gap.map { degreeDifference($0, angle) > gapHalf + 30 } ?? true) && busy.allSatisfy { degreeDifference($0, angle) >= 40 }
                }
                guard !choices.isEmpty, let radius = piece.radius else { continue }
                let angle = AngleMath.radians(fromDegrees: rng.pick(choices))
                draft.pieces[index].bomb = Point(cos(angle), sin(angle)) * radius
                if stands(draft.pieces) { placed += 1 } else { draft.pieces[index].bomb = nil }
            }
            guard placed > 0 else {
                LevelTemplate.debug?("\(options.template): no ring for a bomb")
                return nil
            }
        }

        // Tails, a quarter turn or more from the gap and clear of every link. They narrow how far a
        // ring can turn; the solver has the last word. A tail that starts in something's way or
        // sticks out of the board is dropped.
        if options.tailShare > 0 {
            let linkAngle: (Cell, Cell) -> Int = { from, to in
                let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: (position(to) - position(from)).angle))
                return Int((degrees / ForgeRules.gridDegrees).rounded()) % 8
            }
            for ring in rings.shuffled(using: &rng) where !closed.contains(ring) && rng.chance(options.tailShare) {
                guard let index = draft.index(of: id(ring)), let gap = gapAt[ring] else { continue }
                let taken = Set(((holders[ring] ?? []) + (targets[ring] ?? [])).map { linkAngle(ring, $0) })
                let free = (0..<8).filter { position in
                    let fromGap = min((position - gap + 8) % 8, (gap - position + 8) % 8)
                    return fromGap >= 2 && !taken.contains(position) && !taken.contains((position + 1) % 8) && !taken.contains((position + 7) % 8)
                }
                guard !free.isEmpty else { continue }
                let before = draft.pieces[index]
                draft.pieces[index].addTail(atDegrees: Double(rng.pick(free)) * ForgeRules.gridDegrees, length: shape.stem - 4)
                if !stands(draft.pieces) { draft.pieces[index] = before }
            }
        }

        let motif = Motif(name: options.name, template: options.template, pieces: draft.pieces)
        guard motif.width <= ForgeRules.boardWidth - 2 * ForgeRules.margin,
              motif.height <= ForgeRules.boardHeight - 2 * ForgeRules.margin else {
            LevelTemplate.debug?("\(options.template): \(Int(motif.width))×\(Int(motif.height)) does not fit the board")
            return nil
        }
        return motif
    }
}
