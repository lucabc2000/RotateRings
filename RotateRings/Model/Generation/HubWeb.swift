//
//  HubWeb.swift
//  RotateRings
//
//  Boards that take preparing, not just finding. On a grid, every other ring is a closed hub whose
//  clips hold the C-rings next to it, and most C-rings are held by two or three hubs at once.
//
//  A hub is pinned by its clips and cannot let go of anything itself. It leaves only when every
//  ring it holds has its gap turned onto the hub's clip at the same moment. A ring leaves when the
//  last hub holding it has gone. So no single drag removes anything: the player picks a hub and
//  lines up two to four rings for it, and a ring shared by two hubs can only serve one at a time.
//  Turning it on to the next hub re-grips the first if that one is still there.
//
//  Tails and bars add an order. A ring with a tail cannot swing the tail through a closed hub, so
//  it can only turn part of the way round: to reach one hub's clip it may need another hub cleared
//  out of the way first, and it matters which way round it is turned. A bar in a hole pokes into a
//  ring's gap, so that ring cannot be turned for any hub until the bar is slid out, and the bar's
//  way out runs into the piece across the hole, which has to go first.
//
//  Hubs never turn and rings carry no clips, so the only thing that sweeps is a tail, and that is
//  planned. What can go wrong is a circular wait (through bars, or tails boxing each other in), which
//  `play` rules out before the solver is asked.
//

import Foundation

enum HubWeb {
    struct Options {
        /// Clips per hub, as far as it has neighbours.
        var clips: ClosedRange<Int> = 2...4
        /// Most hubs holding one ring.
        var holdersPerRing = 3
        /// Bars to put in holes (`o` cells of the mask).
        var bars = 0
        /// Share of rings that get a tail (see the tail planning in `build`).
        var tailShare = 0.0
        var name = "Web"
        var template = "web"
    }

    private struct Cell: Hashable {
        var c: Int
        var r: Int
        func moved(_ step: Cell, _ times: Int = 1) -> Cell { Cell(c: c + step.c * times, r: r + step.r * times) }
    }

    /// Builds a web on `shape`'s mask (see `RingNet.Shape`; `o` cells are holes for bars).
    static func build(_ shape: RingNet.Shape, options: Options, rng: inout SplitMix64) -> Motif? {
        let grid = shape.rows.map { Array($0) }
        let rowCount = grid.count
        guard let colCount = grid.map(\.count).max(), colCount > 0 else { return nil }
        func mark(_ cell: Cell) -> Character {
            guard cell.r >= 0, cell.r < rowCount, cell.c >= 0, cell.c < grid[cell.r].count else { return "." }
            return grid[cell.r][cell.c]
        }
        let reach = 2 * shape.radius + shape.stem
        let pitch = shape.layout == .square ? reach : reach / 2.0.squareRoot()
        let steps: [Cell] = shape.layout == .square
            ? [Cell(c: 1, r: 0), Cell(c: -1, r: 0), Cell(c: 0, r: 1), Cell(c: 0, r: -1)]
            : [Cell(c: 1, r: 1), Cell(c: 1, r: -1), Cell(c: -1, r: 1), Cell(c: -1, r: -1)]
        func position(_ cell: Cell) -> Point {
            Point((Double(cell.c) - Double(colCount - 1) / 2) * pitch, (Double(rowCount - 1) / 2 - Double(cell.r)) * pitch)
        }
        func id(_ cell: Cell) -> String { "g\(cell.r)_\(cell.c)" }
        /// The grid splits into two interleaved sets with every neighbour in the other set.
        func side(_ cell: Cell) -> Int {
            shape.layout == .square ? (cell.c + cell.r) & 1 : cell.c & 1
        }

        var sites: [Cell] = []
        var holes: [Cell] = []
        for r in 0..<rowCount {
            for c in 0..<colCount {
                switch mark(Cell(c: c, r: r)) {
                case "#": sites.append(Cell(c: c, r: r))
                case "o": holes.append(Cell(c: c, r: r))
                default: break
                }
            }
        }
        // Holes sit where a hub would, so the cells around them are rings a bar can poke.
        let hubSide = holes.first.map(side) ?? rng.int(in: 0...1)
        var hubs = sites.filter { side($0) == hubSide }
        var rings = Set(sites.filter { side($0) != hubSide })

        // Which hub holds which rings.
        var held: [Cell: [Cell]] = [:]
        var holders: [Cell: [Cell]] = [:]
        for hub in hubs.shuffled(using: &rng) {
            let around = steps.map { hub.moved($0) }.filter { rings.contains($0) && (holders[$0]?.count ?? 0) < options.holdersPerRing }
            let count = min(around.count, rng.int(in: options.clips))
            for ring in around.shuffled(using: &rng).prefix(count) {
                held[hub, default: []].append(ring)
                holders[ring, default: []].append(hub)
            }
        }
        // Every ring needs a holder, or it would leave on load; every hub needs a ring.
        for ring in rings.sorted(by: { ($0.r, $0.c) < ($1.r, $1.c) }) where holders[ring] == nil {
            if let hub = steps.map({ ring.moved($0) }).filter({ hubs.contains($0) }).shuffled(using: &rng).first {
                held[hub, default: []].append(ring)
                holders[ring] = [hub]
            } else {
                rings.remove(ring)
            }
        }
        hubs = hubs.filter { held[$0] != nil }
        guard hubs.count >= 2, rings.count >= 2 else { return nil }

        var draft = LevelDraft(name: options.name, template: options.template)
        for hub in hubs { draft.pieces.append(.closedRing(id(hub), at: position(hub), radius: shape.radius)) }
        for ring in rings.sorted(by: { ($0.r, $0.c) < ($1.r, $1.c) }) {
            draft.pieces.append(.ring(id(ring), at: position(ring), radius: shape.radius))
        }
        for hub in hubs {
            for ring in held[hub] ?? [] {
                guard draft.addRingClip(from: id(hub), to: id(ring)) else { return nil }
            }
        }

        // Bars: from a ring into a hole, long enough to be stopped by the piece across the hole.
        struct Bar {
            var piece: DraftPiece
            var ring: Cell
            var blocker: Cell?
        }
        var bars: [Bar] = []
        var fixedGaps = Set<Cell>()
        for hole in holes.shuffled(using: &rng) where bars.count < options.bars {
            for step in steps.shuffled(using: &rng) {
                let ring = hole.moved(step, -1)
                guard rings.contains(ring), !fixedGaps.contains(ring) else { continue }
                let direction = Point(Double(step.c), Double(-step.r)).normalized()
                let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: direction.angle))
                guard draft.gapIsValid(centerDegrees: degrees, gapDegrees: ForgeRules.defaultGapDegrees, for: id(ring)),
                      let index = draft.index(of: id(ring)) else { continue }
                let across = hole.moved(step)
                let blocked = hubs.contains(across) || rings.contains(across)
                let pokeStart = shape.radius - 10
                let exitTravel = GameRules.holderLength / 2 + 1 + GridWorld.hubInset
                // Stopped by the piece across with a little to spare, or ending mid-hole when the
                // far side is empty.
                let end = blocked ? 2 * reach - shape.radius - exitTravel - 2 : reach
                guard end - pokeStart >= 2 * GridWorld.hubInset else { continue }
                draft.pieces[index].setGap(centerDegrees: degrees, degrees: ForgeRules.defaultGapDegrees)
                fixedGaps.insert(ring)
                let piece = DraftPiece.slideBar("bar\(bars.count)", at: position(ring) + direction * (pokeStart + GridWorld.hubInset),
                                                from: -GridWorld.hubInset, to: end - pokeStart - GridWorld.hubInset, angleDegrees: degrees)
                bars.append(Bar(piece: piece, ring: ring, blocker: blocked ? across : nil))
                break
            }
        }

        // Directions as steps of 45°. Hubs lie in the grid's own directions; the directions in
        // between are where a tail can rest.
        func directionIndex(_ step: Cell) -> Int {
            let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: Point(Double(step.c), Double(-step.r)).angle))
            return Int((degrees / ForgeRules.gridDegrees).rounded()) % 8
        }
        let stepAt = Dictionary(uniqueKeysWithValues: steps.map { (directionIndex($0), $0) })

        /// A long tail ends just short of the next hub's circle and is stopped by any hub beside its
        /// ring. A stub is short enough to pass a hub's circle and is stopped only by the clips
        /// gripping its own ring, so it also works where a ring has hubs on every side.
        struct Tail {
            var position: Int
            var long: Bool
        }
        /// Where every ring's gap points at the start and, for rings that have one, where the tail does.
        struct Plan {
            var gap: [Cell: Int] = [:]
            var tail: [Cell: Tail] = [:]
            /// Rings with the narrower gap that fits one step from a clip.
            var narrow = Set<Cell>()
        }

        /// Plays the web in the abstract. A bar slides out once the piece across its hole is gone.
        /// A hub goes once every ring it still holds can be turned onto its clip: the ring must not
        /// be poked by a bar, and a ring with a tail has to get there without its tail sweeping
        /// through a hub that is still on the board (it can go round either way). A ring goes with
        /// its last hub. Clearing a hub only ever opens more ways round, so taking every hub that
        /// can go, round after round, finds a solution whenever there is one. Returns the number of
        /// rounds and how many hubs could go in the first, or nil when it gets stuck.
        func play(_ plan: Plan, _ bars: [Bar]) -> (rounds: Int, first: Int)? {
            var hubsLeft = Set(hubs), ringsLeft = rings, barsLeft = Array(bars.indices)
            /// A tail cannot be at, or pass, a direction with a hub in it (for a stub: a hub that
            /// grips the ring), or one where a bar from the ring across a hole rests against the ring.
            func blocked(_ ring: Cell, _ position: Int, long: Bool) -> Bool {
                guard let step = stepAt[(position % 8 + 8) % 8] else { return false }
                let hub = ring.moved(step)
                if hubsLeft.contains(hub), long || (held[hub] ?? []).contains(ring) { return true }
                return barsLeft.contains { bars[$0].blocker == ring && bars[$0].ring == ring.moved(step, 2) }
            }
            func canReach(_ ring: Cell, _ hub: Cell) -> Bool {
                guard let tail = plan.tail[ring], let gap = plan.gap[ring] else { return true }
                let turn = (directionIndex(Cell(c: hub.c - ring.c, r: hub.r - ring.r)) - gap + 8) % 8
                return turn == 0 || (1...turn).allSatisfy { !blocked(ring, tail.position + $0, long: tail.long) }
                    || (1...(8 - turn)).allSatisfy { !blocked(ring, tail.position - $0, long: tail.long) }
            }
            guard plan.tail.allSatisfy({ !blocked($0.key, $0.value.position, long: $0.value.long) }) else { return nil }
            var rounds = 0
            var first: Int?
            while true {
                let free = barsLeft.filter { index in bars[index].blocker.map { !hubsLeft.contains($0) && !ringsLeft.contains($0) } ?? true }
                barsLeft.removeAll(where: free.contains)
                let poked = Set(barsLeft.map { bars[$0].ring })
                let ready = hubsLeft.filter { hub in
                    (held[hub] ?? []).allSatisfy { !ringsLeft.contains($0) || (!poked.contains($0) && canReach($0, hub)) }
                }
                if ready.isEmpty && free.isEmpty { break }
                if !ready.isEmpty {
                    rounds += 1
                    if first == nil { first = ready.count }
                }
                hubsLeft.subtract(ready)
                ringsLeft = ringsLeft.filter { ring in (holders[ring] ?? []).contains(where: hubsLeft.contains) }
            }
            guard hubsLeft.isEmpty, ringsLeft.isEmpty, barsLeft.isEmpty else { return nil }
            return (rounds, first ?? 0)
        }

        // The order has to work out: drop bars until it does.
        while !bars.isEmpty && play(Plan(), bars) == nil {
            let dropped = bars.removeLast()
            fixedGaps.remove(dropped.ring)
        }

        // Gap directions a ring may start with. The usual gap needs a quarter turn to the nearest
        // clip, so each hub is a real turn away. A narrower gap also fits one step from a clip, which
        // rings with a tail need where hubs crowd them. A poked ring's gap is already set, facing
        // its bar.
        let narrowGap = ForgeRules.narrowGapDegrees(radius: shape.radius)
        var gapChoices: [Cell: [Int]] = [:]
        var narrowChoices: [Cell: [Int]] = [:]
        for ring in rings {
            if fixedGaps.contains(ring), let center = draft[id(ring)]?.gapCenterDegrees {
                gapChoices[ring] = [Int((center / ForgeRules.gridDegrees).rounded()) % 8]
                continue
            }
            func choices(_ width: Double) -> [Int] {
                (0..<8).filter { draft.gapIsValid(centerDegrees: Double($0) * ForgeRules.gridDegrees, gapDegrees: width, for: id(ring)) }
            }
            let wide = choices(ForgeRules.defaultGapDegrees)
            guard !wide.isEmpty else {
                LevelTemplate.debug?("\(shape.template): no gap for \(id(ring))")
                return nil
            }
            gapChoices[ring] = wide
            if ForgeRules.supportsOneStepLock(radius: shape.radius) { narrowChoices[ring] = choices(narrowGap).filter { !wide.contains($0) } }
        }

        // Tails. A tail sticks out of a ring at least a quarter turn from its gap. It cannot swing
        // through a hub, so the ring can only turn within the stretch between the hubs either side
        // of its tail until one of them is cleared. That decides which hubs it can serve at all, and
        // which have to go before it can get round to another. The search starts without tails and
        // keeps changing one ring at a time, holding on to a change when the abstract game still
        // plays through and is no shallower: more rounds first (a longer chain of "this hub before
        // that one"), then fewer hubs open at the start, then more tails.
        let ordered = rings.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
        let tailLimit = Int((Double(rings.count) * options.tailShare).rounded())
        // A resting tail may not stick out past the outermost rings unless the board has room.
        let longTail = shape.stem - 4
        let stub = shape.stem - GameRules.strokeThickness - 1
        let extent = sites.reduce(Point(0, 0)) { Point(max($0.x, abs(position($1).x)), max($0.y, abs(position($1).y))) }
        let room = Point(max(extent.x + shape.radius, ForgeRules.boardWidth / 2 - ForgeRules.margin - GameRules.strokeThickness),
                         max(extent.y + shape.radius, ForgeRules.boardHeight / 2 - ForgeRules.margin - GameRules.strokeThickness))
        func staysInside(_ ring: Cell, _ tail: Tail) -> Bool {
            let angle = AngleMath.radians(fromDegrees: Double(tail.position) * ForgeRules.gridDegrees)
            let tip = position(ring) + Point(cos(angle), sin(angle)) * (shape.radius + (tail.long ? longTail : stub))
            return abs(tip.x) <= room.x && abs(tip.y) <= room.y
        }
        func score(_ plan: Plan) -> Double? {
            guard plan.tail.count <= tailLimit, plan.tail.allSatisfy({ staysInside($0.key, $0.value) }),
                  let result = play(plan, bars) else { return nil }
            return Double(result.rounds) * 10 - Double(result.first) * 3 + Double(plan.tail.count) + Double(plan.tail.values.filter(\.long).count) * 0.5
        }
        var best: (plan: Plan, score: Double)?
        for _ in 0..<(tailLimit > 0 ? 4 : 1) {
            var plan = Plan()
            for ring in ordered { plan.gap[ring] = rng.pick(gapChoices[ring] ?? []) }
            guard var current = score(plan) else { continue }
            for _ in 0..<(tailLimit > 0 ? 80 * ordered.count : 0) {
                let ring = rng.pick(ordered)
                var changed = plan
                let wide = gapChoices[ring] ?? [], narrow = narrowChoices[ring] ?? []
                changed.tail[ring] = nil
                changed.narrow.remove(ring)
                if rng.chance(0.85) {
                    // Beside a narrow gap a tail may sit one step from it.
                    let gap = rng.pick(wide + narrow)
                    let offset = rng.int(in: 1...7)
                    let needsNarrow = narrow.contains(gap) || offset == 1 || offset == 7
                    if needsNarrow && narrowChoices[ring] == nil { continue }
                    if needsNarrow { changed.narrow.insert(ring) }
                    changed.gap[ring] = gap
                    changed.tail[ring] = Tail(position: (gap + offset) % 8, long: rng.bool())
                } else {
                    changed.gap[ring] = rng.pick(wide)
                }
                if let result = score(changed), result >= current {
                    plan = changed
                    current = result
                }
            }
            if best == nil || current > best!.score { best = (plan, current) }
            LevelTemplate.debug?("\(options.template): plan scores \(current) with \(plan.tail.count) tails on \(rings.count) rings")
        }
        guard let plan = best?.plan else {
            LevelTemplate.debug?("\(shape.template): no plan plays through")
            return nil
        }
        for ring in ordered {
            guard let index = draft.index(of: id(ring)), let gap = plan.gap[ring] else { continue }
            draft.pieces[index].setGap(centerDegrees: Double(gap) * ForgeRules.gridDegrees,
                                       degrees: plan.narrow.contains(ring) ? narrowGap : ForgeRules.defaultGapDegrees)
            if let tail = plan.tail[ring] {
                draft.pieces[index].addTail(atDegrees: Double(tail.position) * ForgeRules.gridDegrees, length: tail.long ? longTail : stub)
            }
        }
        draft.pieces += bars.map(\.piece)

        let motif = Motif(name: options.name, template: options.template, pieces: draft.pieces)
        guard motif.width <= ForgeRules.boardWidth - 2 * ForgeRules.margin,
              motif.height <= ForgeRules.boardHeight - 2 * ForgeRules.margin else {
            LevelTemplate.debug?("\(options.template): \(Int(motif.width))×\(Int(motif.height)) does not fit the board")
            return nil
        }
        return motif
    }
}
