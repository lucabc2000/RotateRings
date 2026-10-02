//
//  GridWorld.swift
//  RotateRings
//
//  Whole-board compositions on a cell grid: sliding bars packed into a maze, optionally around caged
//  rings (a C-ring pinned by a T-shaped latch bar). Every stroke runs along a lane of the grid, so
//  bars one lane apart never touch and a bar always slides along a lane.
//
//  Construction runs backwards. Pieces are placed in the reverse of the order they will leave the
//  board, and a piece is only placed where it is free with everything placed before it still
//  present: a bar can slide out of its hub, a caged ring can turn. Taking the pieces off in reverse
//  placement order therefore always works, so every board is solvable by construction. What makes it
//  a puzzle is that each new piece is chosen to get in the way of the pieces that were free so far:
//  a bar across another bar's way out, a bar end poking into a ring's gap, a cage in a lane.
//

import Foundation

extension SplitMix64 {
    /// True with probability `p`.
    mutating func chance(_ p: Double) -> Bool {
        Double(next() % 10_000) / 10_000 < p
    }
}

enum GridWorld {
    /// Distance between neighbouring lanes when cages are involved: three cages and two lanes fit
    /// across the board. A hub is 24 wide, so a bar one lane over stays clear of it. Mazes without
    /// cages may use a wider pitch to fill the board.
    static let pitch = 28.0
    /// A caged ring fills a 3 × 3 block of cells and stays clear of the lanes around the block.
    static let cageRadius = 38.0
    /// Distance from the end of a bar to a hub placed near that end. With the hub this close the bar
    /// leaves after sliding a little over one cell, so whether the next lane blocks it is never a
    /// near miss.
    static let hubInset = 22.0
    /// Largest distance between the outermost lanes that fits the board.
    static let maxWidth = 300.0
    static let maxHeight = 570.0

    /// A grid cell; rows count downwards from the top.
    struct Cell: Hashable {
        var c: Int
        var r: Int

        static func + (a: Cell, b: Cell) -> Cell { Cell(c: a.c + b.c, r: a.r + b.r) }
        static func * (a: Cell, n: Int) -> Cell { Cell(c: a.c * n, r: a.r * n) }
        static prefix func - (a: Cell) -> Cell { Cell(c: -a.c, r: -a.r) }

        /// The direction turned 90° counterclockwise on the board.
        var counterclockwise: Cell { Cell(c: r, r: -c) }
        /// Board angle of the direction in degrees.
        var degrees: Double { normalizedDegrees(AngleMath.degrees(fromRadians: atan2(Double(-r), Double(c)))) }
        /// The direction as a board vector (y up).
        var vector: Point { Point(Double(c), Double(-r)) }
    }

    static let right = Cell(c: 1, r: 0), up = Cell(c: 0, r: -1), left = Cell(c: -1, r: 0), down = Cell(c: 0, r: 1)
    static let directions = [right, up, left, down]

    /// A caged ring: the ring's block is centred on `center`, its T-bar lies two cells towards `barSide`.
    struct Cage {
        var center: Cell
        var barSide: Cell
    }

    struct Plan {
        var name: String
        var template: String
        var cols: Int
        var rows: Int
        /// Sliding bars to place; fewer are accepted when the grid fills up (see `build`).
        var bars: Int
        /// Share of bars that get a bent arm.
        var elbowChance: Double
        var cages: [Cage] = []
        /// Lane spacing; cages need `GridWorld.pitch`.
        var pitch = GridWorld.pitch
        /// For hard boards: the most pieces that may be free at once while the board is built. Each
        /// new bar then has to lock one of the free pieces, which strings the pieces into long
        /// chains instead of leaving half of them free from the start.
        var freeLimit: Int? = nil
    }

    /// Cages in `across` columns and `down` rows with `lanes` lanes between them and `border` lanes
    /// around the outside. `count` of the slots are filled; each T-bar sits above or below its ring.
    static func cagePlan(name: String, template: String, across: Int, down: Int, count: Int, lanes: Int, border: Int, bars: Int,
                         elbowChance: Double, rng: inout SplitMix64) -> Plan {
        var slots: [Cage] = []
        for j in 0..<down {
            for i in 0..<across {
                let base = border + j * (4 + lanes)
                let onTop = rng.bool()
                slots.append(Cage(center: Cell(c: border + i * (3 + lanes) + 1, r: onTop ? base + 2 : base + 1), barSide: onTop ? Self.up : Self.down))
            }
        }
        slots.shuffle(using: &rng)
        return Plan(name: name, template: template, cols: across * (3 + lanes) - lanes + 2 * border, rows: down * (4 + lanes) - lanes + 2 * border,
                    bars: bars, elbowChance: elbowChance, cages: Array(slots.prefix(count)))
    }

    // MARK: Building

    private struct Builder {
        let plan: Plan
        var draft: LevelDraft
        /// Which piece covers a cell.
        var owner: [Cell: String] = [:]
        /// Cells inside a caged ring that a bar may enter through the gap: cell → direction out of the gap.
        var pockets: [Cell: Cell] = [:]
        /// Cells kept clear for cages that are not placed yet.
        var reserved: Set<Cell> = []
        /// Ways out per piece with everything placed so far present: directions a bar can slide out
        /// of its hub (0–2), or 1 for a caged ring that can turn. Pieces with none are left out.
        var exits: [String: Int] = [:]
        /// Cells just beyond a free bar's end, per way out: where a blocker has to go.
        var exitCells: [String: [Cell]] = [:]
        /// Bars whose way out leaves the grid: nothing placed later can lock them.
        var unsealable: Set<String> = []
        var counter = 0

        init(plan: Plan) {
            self.plan = plan
            draft = LevelDraft(name: plan.name, template: plan.template)
            for cage in plan.cages { reserved.formUnion(Self.cells(of: cage).all) }
        }

        func position(_ cell: Cell) -> Point {
            Point((Double(cell.c) - Double(plan.cols - 1) / 2) * plan.pitch,
                  (Double(plan.rows - 1) / 2 - Double(cell.r)) * plan.pitch)
        }

        func inside(_ cell: Cell) -> Bool {
            cell.c >= 0 && cell.c < plan.cols && cell.r >= 0 && cell.r < plan.rows
        }

        static func cells(of cage: Cage) -> (ring: [Cell], bar: [Cell], all: [Cell]) {
            var ring: [Cell] = []
            for dc in -1...1 {
                for dr in -1...1 { ring.append(cage.center + Cell(c: dc, r: dr)) }
            }
            let middle = cage.center + cage.barSide * 2
            let along = cage.barSide.counterclockwise
            let bar = [middle + -along, middle, middle + along]
            return (ring, bar, ring + bar)
        }

        func board(of draft: LevelDraft) -> Board? {
            try? draft.levelFile(number: 0).makeBoard()
        }

        /// Ways out for a piece: the directions one push takes a bar out of its hub, or 1 for a caged
        /// ring that can turn a step.
        func exitCount(_ id: String, in board: Board) -> Int {
            guard let piece = board.piece(id) else { return 0 }
            if piece.motion == .slide {
                return [1.0, -1.0].filter { board.slideStop(id, direction: $0)?.exits == true }.count
            }
            return [1.0, -1.0].contains { board.obstruction(for: id, movingBy: $0 * GameRules.rotationStep) == nil } ? 1 : 0
        }

        /// The exits left for every piece that had one, with `board` holding one more piece.
        func remainingExits(in board: Board) -> [String: Int] {
            var result: [String: Int] = [:]
            for id in exits.keys {
                let count = exitCount(id, in: board)
                if count > 0 { result[id] = count }
            }
            return result
        }

        /// How many cells of `cells` have a neighbour that is already taken: a measure of how snugly a
        /// piece sits against the rest.
        func contact(of cells: [Cell]) -> Double {
            let own = Set(cells)
            var touching = 0
            for cell in cells {
                if GridWorld.directions.contains(where: { owner[cell + $0] != nil && !own.contains(cell + $0) }) { touching += 1 }
            }
            return Double(touching) / Double(max(1, cells.count))
        }

        // MARK: Cages

        mutating func place(_ cage: Cage, rng: inout SplitMix64) -> Bool {
            counter += 1
            let ringID = "c\(counter)", barID = "t\(counter)"
            let cells = Self.cells(of: cage)
            guard cells.all.allSatisfy({ inside($0) && owner[$0] == nil }) else { return false }

            // The gap faces a side a bar can reach, or now and then a corner where nothing can. On a
            // hard board it always faces an open lane, so a bar can lock the ring.
            let sides = GridWorld.directions.filter { $0 != cage.barSide }
            let open = sides.filter { side in
                let lane = cage.center + side * 2
                return inside(lane) && owner[lane] == nil && !reserved.contains(lane)
            }
            let diagonal = plan.freeLimit == nil && rng.chance(0.2)
            let gapSide = rng.pick(plan.freeLimit != nil && !open.isEmpty ? open : sides)
            let gapDegrees = diagonal ? normalizedDegrees(cage.barSide.degrees + (rng.bool() ? 135 : -135)) : gapSide.degrees
            let barCenter = position(cage.center + cage.barSide * 2)
            var trial = draft
            trial.pieces.append(.ring(ringID, at: position(cage.center), radius: GridWorld.cageRadius, gapCenterDegrees: gapDegrees))
            trial.pieces.append(.latchBar(barID, at: barCenter, from: -plan.pitch, to: plan.pitch,
                                          angleDegrees: cage.barSide.counterclockwise.degrees))
            guard trial.addClip(from: barID, at: barCenter, to: ringID),
                  trial.gapIsValid(centerDegrees: gapDegrees, gapDegrees: ForgeRules.defaultGapDegrees, for: ringID),
                  let board = board(of: trial), exitCount(ringID, in: board) > 0 else { return false }

            draft = trial
            exits = remainingExits(in: board)
            exits[ringID] = 1
            for cell in cells.ring { owner[cell] = ringID }
            for cell in cells.bar { owner[cell] = barID }
            reserved.subtract(cells.all)
            if !diagonal {
                pockets[cage.center] = gapSide
                pockets[cage.center + gapSide] = gapSide
            }
            return true
        }

        // MARK: Bars

        struct BarCandidate {
            var piece: DraftPiece
            var cells: [Cell]
            /// Cells one step beyond each end of the arm (and of a bent tip, in the direction it leaves).
            var ahead: [Cell]
            var score: Double
            var ownExits: Int
            /// How many of its ways out a later piece can still block.
            var sealable: Int
            var remaining: [String: Int]
        }

        /// A random bar, or nil when it does not fit or could not slide out. With `through` the arm
        /// is laid across that cell; otherwise it starts on a random cell.
        func randomBar(id: String, through target: Cell?, rng: inout SplitMix64) -> BarCandidate? {
            let axis = rng.pick(GridWorld.directions)
            let longest = max(3, min(7, (axis.c != 0 ? plan.cols : plan.rows) - 1))
            let length = rng.int(in: 3...longest)
            let start: Cell
            if let target {
                start = target + axis * -rng.int(in: 0...(length - 1))
            } else {
                start = Cell(c: rng.int(in: 0...(plan.cols - 1)), r: rng.int(in: 0...(plan.rows - 1)))
            }
            let arm = (0..<length).map { start + axis * $0 }
            var legCells: [Cell] = []
            var legLength = 0.0
            if rng.chance(plan.elbowChance) {
                let side = rng.bool() ? 1 : -1
                let count = rng.int(in: 1...3)
                legCells = (1...count).map { arm[length - 1] + axis.counterclockwise * (side * $0) }
                legLength = Double(side * count) * plan.pitch
            }
            for cell in arm {
                guard inside(cell), !reserved.contains(cell) else { return nil }
                if owner[cell] != nil {
                    // Only a ring's pocket, entered along the gap.
                    guard let out = pockets[cell], out == axis || out == -axis else { return nil }
                }
            }
            for cell in legCells {
                guard inside(cell), !reserved.contains(cell), owner[cell] == nil else { return nil }
            }

            let armLength = Double(length - 1) * plan.pitch
            // The hub sits near either end, or in the middle of an arm with an even number of cells.
            // Each of those leaves a clear margin between "the next lane stops it" and "it slides out".
            var insets = [GridWorld.hubInset, armLength - GridWorld.hubInset]
            if length % 2 == 0 { insets.append(armLength / 2) }
            let inset = rng.pick(insets)
            let hub = position(start) + axis.vector * inset
            let piece: DraftPiece = legCells.isEmpty
                ? .slideBar(id, at: hub, from: -inset, to: armLength - inset, angleDegrees: axis.degrees)
                : .slideElbow(id, at: hub, from: -inset, to: armLength - inset, legLength: legLength, angleDegrees: axis.degrees)

            var trial = draft
            trial.pieces.append(piece)
            guard let board = board(of: trial), let placed = board.piece(id),
                  board.blockingReason(for: placed, at: placed.movement) == nil else { return nil }
            // The cells a blocker would need, per way out: one step beyond the leading end(s).
            let forward = (legCells + [arm[length - 1]]).map { $0 + axis }
            let backward = [start + -axis]
            var ahead: [Cell] = []
            var ownExits = 0
            var sealable = 0
            for (direction, cells) in [(1.0, forward), (-1.0, backward)] where board.slideStop(id, direction: direction)?.exits == true {
                ownExits += 1
                ahead += cells
                if cells.contains(where: { inside($0) && owner[$0] == nil }) { sealable += 1 }
            }
            guard ownExits > 0 else { return nil }
            let remaining = remainingExits(in: board)
            let closed = exits.values.reduce(0, +) - remaining.values.reduce(0, +)
            let locked = exits.count - remaining.count
            let cells = arm + legCells
            // Getting in the way of free pieces matters most. A way out that leaves the grid can never
            // be blocked by a later piece, so the bar would stay free for good; a single way out that
            // a later piece can still block is best. Then a snug fit, then size.
            // A way out across a slot kept for a cage is the best kind: the cage will lock the bar.
            let towardsCage = plan.freeLimit != nil && ahead.contains(where: reserved.contains) ? 3.0 : 0
            let score = 3 * Double(closed) + 5 * Double(locked) - 4 * Double(ownExits - sealable) - Double(ownExits - 1) + towardsCage
                + 2 * contact(of: cells) + 0.3 * Double(cells.count) + Double(rng.next() % 100) / 100
            return BarCandidate(piece: piece, cells: cells, ahead: ahead, score: score, ownExits: ownExits, sealable: sealable, remaining: remaining)
        }

        /// Places the best of a batch of random bars. False when none fits any more.
        mutating func placeBar(rng: inout SplitMix64) -> Bool {
            counter += 1
            let id = "s\(counter)"
            let open = (0..<plan.rows).flatMap { r in (0..<plan.cols).map { Cell(c: $0, r: r) } }
                .filter { owner[$0] == nil && !reserved.contains($0) }
            let blockable = exits.keys.sorted().flatMap { exitCells[$0] ?? [] }.filter { inside($0) && owner[$0] == nil && !reserved.contains($0) }
            let pocketCells = pockets.keys.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
            guard !open.isEmpty else { return false }
            var best: BarCandidate?
            var valid = 0
            // Free bars nothing can lock any more; a hard board keeps one slot under its limit for
            // bars that can still be locked.
            let stuck = exits.keys.filter(unsealable.contains).count
            for _ in 0..<(plan.freeLimit == nil ? 400 : 3000) where valid < 24 {
                // Aim at the way out of a free bar, at a ring's gap, or anywhere that is still open.
                let target: Cell
                let roll = rng.int(in: 0...9)
                if roll < (plan.freeLimit == nil ? 5 : 6), !blockable.isEmpty {
                    target = rng.pick(blockable)
                } else if roll < 8, !pocketCells.isEmpty {
                    target = rng.pick(pocketCells)
                } else {
                    target = rng.pick(open)
                }
                guard let candidate = randomBar(id: id, through: target, rng: &rng) else { continue }
                if let limit = plan.freeLimit {
                    // On a hard board the new bar may not add to the free pieces beyond the limit, and
                    // it has a single way out that a later piece can still block: such a bar is locked
                    // by whatever lands in front of it, which is what builds chains.
                    if candidate.remaining.count + 1 > max(limit, exits.count) { continue }
                    if candidate.ownExits > 1 { continue }
                    if candidate.sealable == 0, stuck >= limit - 1 { continue }
                }
                valid += 1
                if best == nil || candidate.score > best!.score { best = candidate }
            }
            guard let best else { return false }
            draft.pieces.append(best.piece)
            for cell in best.cells {
                owner[cell] = id
                pockets[cell] = nil
            }
            exits = best.remaining
            exits[id] = best.ownExits
            exitCells[id] = best.ahead
            if best.sealable == 0 { unsealable.insert(id) }
            return true
        }
    }

    /// Builds the board described by `plan`, centred. Nil when too few bars fit or too many pieces
    /// are free from the start.
    static func build(_ plan: Plan, rng: inout SplitMix64) -> LevelDraft? {
        precondition(Double(plan.cols - 1) * plan.pitch <= maxWidth && Double(plan.rows - 1) * plan.pitch <= maxHeight, "grid does not fit the board")
        var builder = Builder(plan: plan)
        var pending = plan.cages
        var barsLeft = plan.bars
        var barsPlaced = 0
        while barsLeft > 0 || !pending.isEmpty {
            if plan.freeLimit != nil, !pending.isEmpty {
                // Hard board: a cage goes in as soon as it locks a free bar, so its ring takes the
                // bar's place among the free pieces and the chain grows by one.
                var best: (index: Int, builder: Builder, locked: Int)?
                for (index, cage) in pending.enumerated() {
                    var trial = builder
                    var trialRNG = rng.derived(UInt64(index))
                    guard trial.place(cage, rng: &trialRNG) else { continue }
                    let locked = builder.exits.count + 1 - trial.exits.count
                    if best == nil || locked > best!.locked { best = (index, trial, locked) }
                }
                if let best, best.locked > 0 || barsLeft == 0 {
                    builder = best.builder
                    pending.remove(at: best.index)
                    _ = rng.next()
                    continue
                }
                if best == nil {
                    LevelTemplate.debug?("\(plan.template): a cage did not fit")
                    return nil
                }
            }
            // Cages and bars are interleaved, so a cage can block a bar and a bar can lock a cage.
            let cageTurn = plan.freeLimit == nil && !pending.isEmpty
                && (barsLeft == 0 || rng.chance(Double(pending.count) / Double(pending.count + barsLeft)))
            if cageTurn {
                guard builder.place(pending.removeLast(), rng: &rng) else {
                    LevelTemplate.debug?("\(plan.template): a cage did not fit")
                    return nil
                }
            } else if builder.placeBar(rng: &rng) {
                barsLeft -= 1
                barsPlaced += 1
            } else {
                barsLeft = 0
            }
        }
        guard barsPlaced * 4 >= plan.bars * 3 else {
            LevelTemplate.debug?("\(plan.template): only \(barsPlaced) of \(plan.bars) bars fit")
            return nil
        }
        // A board where most bars can leave straight away is busywork, not a puzzle. Caged rings do
        // not count: turning one to its clip is a move worth making even when nothing locks it.
        if let limit = plan.freeLimit, builder.exits.count > limit + 1 {
            LevelTemplate.debug?("\(plan.template): \(builder.exits.count) pieces free at the start, over the limit")
            return nil
        }
        let freeBars = builder.exits.keys.filter { $0.hasPrefix("s") }.count
        guard freeBars * 2 <= barsPlaced + 1 else {
            LevelTemplate.debug?("\(plan.template): \(freeBars) of \(barsPlaced) bars free at the start")
            return nil
        }

        // The grid is centred, not the strokes: a hub near the edge must not push the far side out.
        var draft = LevelDraft(name: plan.name, template: plan.template, pieces: builder.draft.pieces.map { $0.translated(by: ForgeRules.center) })
        draft.renumberIDs()
        return draft
    }
}
