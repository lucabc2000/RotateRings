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
        /// Which cells are left empty for the bars. Every cell of the pattern stays empty (the ones
        /// without a bar as plain holes), so the holes read as a shape rather than missing rings;
        /// `random` is the old scatter of exactly `bars` cells.
        var holes = HolePattern.random
        /// U-bars: pairs of neighbouring cells left empty, with one bar whose two arms poke into the
        /// gaps of the two rings beside them. Both rings are stuck until it is out, and it only
        /// slides away from them.
        var uBars = 0
        /// Bombs riding on rings. A bomb goes off when it touches another piece, so the ring can
        /// only turn as far as the bomb has room; the solver never sets one off.
        var bombs = 0
        /// Locks: closed rings that hold `lockClips` of their neighbours and are held by nothing, as
        /// the hubs of a web (`HubWeb`). A lock never turns; it leaves only when every ring it grips
        /// has its gap on its clip at the same moment. Each further lock sits two cells from an
        /// earlier one, so the two share the ring between them, which can serve only one at a time.
        var locks = 0
        var lockClips: ClosedRange<Int> = 2...3
        /// Mirror the board left to right: the outline's left half is reflected onto the right, and
        /// holes, U-bars, the ranking, links, closed rings, gaps, bars, bombs and tails come in mirror
        /// pairs. Rings on the axis get only what is symmetric on its own (a gap, tail or bomb
        /// straight up or down, a bar along the axis). A link between a ring and its own mirror image
        /// is the one thing that cannot be mirrored: its clip sits on the axis, owned by one of
        /// them. Not with locks.
        var mirror = false
        /// With `mirror`: mirror images get the same colour where they do not touch.
        var mirrorColors = false
        var board = BoardSize.standard
        var name = "Knot"
        var template = "knot"
    }

    enum HolePattern: String, CaseIterable {
        /// `bars` cells anywhere.
        case random
        /// The mask's own empty cells (`o`), as on Sieve; no others.
        case mask
        /// A staggered lattice, every other row, two cells along from the row before (Sieve).
        case sieve
        /// The cells nearest the middle.
        case center
        /// Every fourth diagonal.
        case diagonal
        /// The middle column and the middle row, every other cell.
        case cross
        /// Every other cell in the three middle rows.
        case checker
        /// Every other cell round the edge.
        case frame
        /// `bars` cells anywhere, each with its mirror image.
        case mirror
    }

    /// Most of a board's cells a pattern may leave empty.
    static let maxHoleShare = 0.25

    private struct Cell: Hashable {
        var c: Int
        var r: Int
        func moved(_ step: Cell) -> Cell { Cell(c: c + step.c, r: r + step.r) }
    }

    private static func widths(of ring: Cell, holders: Bool, draft: LevelDraft, id: (Cell) -> String) -> [Double] {
        holders ? [draft.sharedGapRequirement(for: id(ring), together: false), ForgeRules.defaultGapDegrees]
            : [ForgeRules.defaultGapDegrees]
    }

    static func build(_ shape: RingNet.Shape, options: Options, rng: inout SplitMix64) -> Motif? {
        var grid = shape.rows.map { Array($0) }
        let rowCount = grid.count
        guard let colCount = grid.map(\.count).max(), colCount > 0 else { return nil }
        let mirror = options.mirror
        if mirror {
            // On the diagonal lattice a cell's mirror image is a cell only when the width is odd.
            guard options.locks == 0, shape.layout == .square || colCount % 2 == 1 else { return nil }
            grid = grid.map { row in
                let padded = row + Array(repeating: Character("."), count: colCount - row.count)
                return (0..<colCount).map { padded[min($0, colCount - 1 - $0)] }
            }
        }
        /// The mirror image of a cell (itself without `mirror`), and a cell with its image.
        func twin(_ cell: Cell) -> Cell { mirror ? Cell(c: colCount - 1 - cell.c, r: cell.r) : cell }
        func copies(_ cell: Cell) -> [Cell] { twin(cell) == cell ? [cell] : [cell, twin(cell)] }
        /// The mirror image of a lattice direction (0…7, 45° steps from +x).
        func twin(direction k: Int) -> Int { (12 - k) % 8 }
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
        func uSiteFits(_ cell: Cell, _ second: Cell, _ direction: Cell, besides taken: [Cell]) -> Bool {
            sites.contains(second) && !holes.contains(cell) && !holes.contains(second)
                && sites.contains(Cell(c: cell.c - direction.c, r: cell.r - direction.r))
                && sites.contains(Cell(c: second.c - direction.c, r: second.r - direction.r))
                && !allSteps.contains(where: { step in
                    (holes + taken).contains(cell.moved(step)) || (holes + taken).contains(second.moved(step))
                })
        }
        for cell in sites.shuffled(using: &rng) where uSites.count < options.uBars {
            for direction in allSteps.shuffled(using: &rng) {
                let across = Cell(c: direction.r, r: direction.c)
                let second = cell.moved(across)
                guard uSiteFits(cell, second, direction, besides: []) else { continue }
                if mirror {
                    // The mirror image of the site: the same site (a U across the axis, pointing
                    // up or down), or a second one clear of the first.
                    let image = (first: twin(cell), second: twin(second), direction: Cell(c: -direction.c, r: direction.r))
                    if Set([image.first, image.second]) == Set([cell, second]) {
                        guard image.direction == direction else { continue }
                    } else {
                        guard uSites.count + 2 <= options.uBars, !Set([image.first, image.second]).contains(where: [cell, second].contains),
                              uSiteFits(image.first, image.second, image.direction, besides: [cell, second]) else { continue }
                        uSites.append(image)
                        holes += [image.first, image.second]
                    }
                }
                uSites.append((cell, second, direction))
                holes += [cell, second]
                break
            }
        }
        let uCells = Set(holes)
        func holeFits(_ cell: Cell, besides taken: [Cell]) -> Bool {
            !allSteps.contains(where: { (holes + taken).contains(cell.moved($0)) }) && !(holes + taken).contains(cell)
                && allSteps.filter({ sites.contains(cell.moved($0)) }).count >= 2
        }
        if options.holes == .mask {
            for r in 0..<rowCount {
                for c in 0..<grid[r].count where grid[r][c] == "o" { holes.append(Cell(c: c, r: r)) }
            }
        } else if options.holes != .random && options.holes != .mirror && (options.bars > 0 || options.holes != .sieve) {
            // The pattern's cells, from the middle outwards, each kept where it leaves rings around it.
            let midC = Double(colCount - 1) / 2, midR = Double(rowCount - 1) / 2
            func fromMiddle(_ cell: Cell) -> Double { abs(Double(cell.c) - midC) + abs(Double(cell.r) - midR) }
            let parity = rng.int(in: 0...1), offset = rng.int(in: 0...3)
            let across = rng.bool()
            let middleColumn = colCount % 2 == 1 ? colCount / 2 : colCount / 2 - parity
            let middleRow = rowCount % 2 == 1 ? rowCount / 2 : rowCount / 2 - (1 - parity)
            let pattern = sites.filter { cell in
                switch options.holes {
                case .sieve: return cell.r % 2 == parity && (cell.c + cell.r + 4) % 4 == offset
                case .center: return fromMiddle(cell) <= 1
                case .diagonal: return ((across ? cell.c + cell.r : cell.c - cell.r) % 4 + 4) % 4 == offset
                case .cross: return cell.c == middleColumn || cell.r == middleRow
                case .checker: return abs(Double(cell.r) - midR) <= 1 && (cell.c + cell.r) % 2 == parity
                case .frame: return (cell.c == 0 || cell.r == 0 || cell.c == colCount - 1 || cell.r == rowCount - 1) && (cell.c + cell.r) % 2 == parity
                case .random, .mirror, .mask: return false
                }
            }.sorted { (fromMiddle($0), $0.r, $0.c) < (fromMiddle($1), $1.r, $1.c) }
            let limit = holes.count + max(options.bars, Int(Double(sites.count) * maxHoleShare))
            for cell in pattern where holes.count < limit && holeFits(cell, besides: []) {
                if mirror, twin(cell) != cell {
                    guard holes.count + 2 <= limit, holeFits(twin(cell), besides: [cell]) else { continue }
                    holes.append(twin(cell))
                }
                holes.append(cell)
            }
        }
        // The old scatter, and mirror pairs anywhere.
        let scatter = options.holes == .random || options.holes == .mirror || (options.holes == .sieve && options.bars == 0)
        for cell in sites.shuffled(using: &rng) where scatter && holes.count < options.bars + 2 * uSites.count {
            if !holeFits(cell, besides: []) { continue }
            if options.holes == .mirror, !mirror {
                let image = Cell(c: colCount - 1 - cell.c, r: cell.r)
                if image != cell {
                    guard sites.contains(image), holeFits(image, besides: [cell]) else { continue }
                    holes.append(image)
                }
            }
            if mirror {
                // A hole on the axis needs a bar along it, which the diagonal lattice has not.
                if twin(cell) == cell {
                    if shape.layout == .diagonal { continue }
                } else {
                    guard holes.count + 2 <= options.bars + 2 * uSites.count, holeFits(twin(cell), besides: [cell]) else { continue }
                    holes.append(twin(cell))
                }
            }
            holes.append(cell)
        }
        sites.removeAll(where: holes.contains)
        guard sites.count >= 3 else { return nil }

        // Locks: the first anywhere with enough neighbours, each next one two cells from a lock with
        // a ring between them, and never next to another lock.
        var locks: [Cell] = []
        var lockTargets: [Cell: [Cell]] = [:]
        if options.locks > 0 {
            func neighbours(_ cell: Cell) -> [Cell] { allSteps.map { cell.moved($0) }.filter { sites.contains($0) } }
            func free(_ cell: Cell) -> Bool {
                sites.contains(cell) && !locks.contains(cell) && !locks.contains { lock in neighbours(lock).contains(cell) }
            }
            for _ in 0..<options.locks {
                var choices: [(lock: Cell, shared: Cell?)] = []
                if locks.isEmpty {
                    choices = sites.filter { neighbours($0).count >= options.lockClips.upperBound }.map { ($0, nil) }
                } else {
                    for lock in locks {
                        for step in allSteps {
                            let shared = lock.moved(step), cell = shared.moved(step)
                            if sites.contains(shared), free(cell), neighbours(cell).count >= options.lockClips.lowerBound,
                               !lockTargets.values.contains(where: { $0.count > 0 && $0.contains(cell) }) {
                                choices.append((cell, shared))
                            }
                        }
                    }
                }
                guard let choice = choices.isEmpty ? nil : rng.pick(choices) else { break }
                let count = rng.int(in: options.lockClips)
                var grips = choice.shared.map { [$0] } ?? []
                for cell in neighbours(choice.lock).shuffled(using: &rng) where grips.count < count && !grips.contains(cell) && !locks.contains(cell) {
                    grips.append(cell)
                }
                guard grips.count >= options.lockClips.lowerBound else { break }
                locks.append(choice.lock)
                lockTargets[choice.lock] = grips
            }
            guard locks.count == options.locks else {
                LevelTemplate.debug?("\(options.template): room for \(locks.count) of \(options.locks) locks")
                return nil
            }
        }

        // One ranking of all rings: a clip always runs from the higher ring to the lower.
        var score: [Cell: Double] = [:]
        var rank: [Cell: Int] = [:]
        if mirror {
            // Mirror images score alike, so every link and its image run the same way.
            let onAxis = sites.filter { twin($0) == $0 }
            let origin = rng.pick(onAxis.isEmpty ? sites : onAxis)
            func distance(_ cell: Cell) -> Double {
                Double(min(abs(cell.c - origin.c), abs(twin(cell).c - origin.c)) + abs(cell.r - origin.r)) / Double(colCount + rowCount)
            }
            for cell in sites where cell.c <= twin(cell).c {
                let value = options.chain * distance(cell) + (1 - options.chain) * Double(rng.int(in: 0...1000)) / 1000
                for copy in copies(cell) { score[copy] = value }
            }
            let order = sites.sorted { a, b in
                (score[a]!, a.r, min(a.c, twin(a).c), a.c) < (score[b]!, b.r, min(b.c, twin(b).c), b.c)
            }
            for (index, cell) in order.enumerated() { rank[cell] = index }
        } else {
            let origin = rng.pick(sites)
            for cell in sites {
                let distance = Double(abs(cell.c - origin.c) + abs(cell.r - origin.r)) / Double(colCount + rowCount)
                score[cell] = options.chain * distance + (1 - options.chain) * Double(rng.int(in: 0...1000)) / 1000
            }
            for (index, cell) in sites.sorted(by: { (score[$0]!, $0.r, $0.c) < (score[$1]!, $1.r, $1.c) }).enumerated() { rank[cell] = index }
        }
        // Locks rank above every ring, so nothing grips them.
        for (index, lock) in locks.enumerated() { rank[lock] = sites.count + index }

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
        // A lock's clips are placed first and are its only links.
        for lock in locks {
            for target in lockTargets[lock] ?? [] {
                targets[lock, default: []].append(target)
                holders[target, default: []].append(lock)
            }
        }
        pairs.removeAll { locks.contains($0.0) || locks.contains($0.1) }
        var skipped: [(Cell, Cell)] = []
        if mirror {
            /// Joins a pair and its mirror image, or neither.
            func joinBoth(_ a: Cell, _ b: Cell) {
                let image = (twin(a), twin(b))
                guard Set([image.0, image.1]) != Set([a, b]) else { _ = join(a, b); return }
                guard join(a, b) else { return }
                if !join(image.0, image.1) {
                    let (owner, target) = rank[a]! > rank[b]! ? (a, b) : (b, a)
                    targets[owner]!.removeLast()
                    holders[target]!.removeLast()
                }
            }
            var seen = Set<Set<Cell>>()
            for pair in pairs.shuffled(using: &rng) where !seen.contains([pair.0, pair.1]) {
                seen.formUnion([[pair.0, pair.1], [twin(pair.0), twin(pair.1)]])
                if rng.chance(options.linkChance) { joinBoth(pair.0, pair.1) } else { skipped.append(pair) }
            }
            for pair in skipped where links(pair.0) == 0 || links(pair.1) == 0 { joinBoth(pair.0, pair.1) }
        } else {
            for pair in pairs.shuffled(using: &rng) {
                if rng.chance(options.linkChance) { _ = join(pair.0, pair.1) } else { skipped.append(pair) }
            }
            // No ring may be left on its own: it would leave on load.
            for pair in skipped where links(pair.0) == 0 || links(pair.1) == 0 { _ = join(pair.0, pair.1) }
        }
        let rings = sites.filter { links($0) > 0 }
        guard rings.count >= 3 else { return nil }

        var draft = LevelDraft(name: options.name, template: options.template)
        var closed = Set<Cell>()
        if mirror {
            for ring in rings where ring.c <= twin(ring).c && copies(ring).allSatisfy({ holders[$0] == nil && rings.contains($0) }) {
                if rng.chance(options.anchorChance) { closed.formUnion(copies(ring)) }
            }
        }
        for ring in rings {
            if mirror {
                draft.pieces.append(closed.contains(ring) ? .closedRing(id(ring), at: position(ring), radius: shape.radius)
                                                         : .ring(id(ring), at: position(ring), radius: shape.radius))
            } else if locks.contains(ring) {
                closed.insert(ring)
                draft.pieces.append(.closedRing(id(ring), at: position(ring), radius: shape.radius))
            } else if holders[ring] == nil, rng.chance(options.anchorChance) {
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
            Knot.widths(of: ring, holders: holders[ring] != nil, draft: draft, id: id)
        }

        /// Whether the board as drafted so far loads, with nothing in a collision or off the board.
        func stands(_ pieces: [DraftPiece]) -> Bool {
            let motif = Motif(name: options.name, template: options.template, pieces: pieces)
            return (try? LevelDraft(name: options.name, template: options.template, pieces: motif.placed(at: options.board.center, board: options.board),
                                    board: options.board).validate()) != nil
        }

        // Bars first: the ring a bar pokes has its gap facing the bar. U-bars take two rings each.
        var bars: [DraftPiece] = []
        var pokedRings = Set<Cell>()
        let pokeStart = shape.radius - 10
        for site in uSites {
            let ringA = Cell(c: site.first.c - site.direction.c, r: site.first.r - site.direction.r)
            let ringB = Cell(c: site.second.c - site.direction.c, r: site.second.r - site.direction.r)
            // A mirrored board drops only both of a pair of U-bars, so it gives up on either.
            guard rings.contains(ringA), rings.contains(ringB), !closed.contains(ringA), !closed.contains(ringB),
                  gapAt[ringA] == nil, gapAt[ringB] == nil,
                  let indexA = draft.index(of: id(ringA)), let indexB = draft.index(of: id(ringB)) else { if mirror { return nil }; continue }
            let direction = (position(site.first) - position(ringA)).normalized()
            let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: direction.angle))
            guard let widthA = widths(ringA).first(where: { draft.gapIsValid(centerDegrees: degrees, gapDegrees: $0, for: id(ringA)) }),
                  let widthB = widths(ringB).first(where: { draft.gapIsValid(centerDegrees: degrees, gapDegrees: $0, for: id(ringB)) })
            else { if mirror { return nil }; continue }
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
        /// The bar from `hole` into the ring a `step` back from it, with that ring's gap facing it;
        /// nil when the ring cannot take it.
        func holeBar(_ hole: Cell, _ step: Cell) -> (ring: Cell, index: Int, degrees: Double, width: Double, end: Double)? {
            let ring = Cell(c: hole.c - step.c, r: hole.r - step.r)
            guard rings.contains(ring), !closed.contains(ring), gapAt[ring] == nil, let index = draft.index(of: id(ring)) else { return nil }
            let direction = (position(hole) - position(ring)).normalized()
            let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: direction.angle))
            guard let width = widths(ring).first(where: { draft.gapIsValid(centerDegrees: degrees, gapDegrees: $0, for: id(ring)) }) else { return nil }
            let blocked = rings.contains(hole.moved(step))
            let exitTravel = GameRules.holderLength / 2 + 1 + GridWorld.hubInset
            let end = blocked ? 2 * reach - shape.radius - exitTravel - 2 : reach
            guard end - pokeStart >= 2 * GridWorld.hubInset else { return nil }
            return (ring, index, degrees, width, end)
        }
        func addBar(_ bar: (ring: Cell, index: Int, degrees: Double, width: Double, end: Double)) {
            let direction = Point(cos(AngleMath.radians(fromDegrees: bar.degrees)), sin(AngleMath.radians(fromDegrees: bar.degrees)))
            draft.pieces[bar.index].setGap(centerDegrees: bar.degrees, degrees: bar.width)
            gapAt[bar.ring] = Int((bar.degrees / ForgeRules.gridDegrees).rounded()) % 8
            pokedRings.insert(bar.ring)
            bars.append(.slideBar("bar\(bars.count)", at: position(bar.ring) + direction * (pokeStart + GridWorld.hubInset),
                                  from: -GridWorld.hubInset, to: bar.end - pokeStart - GridWorld.hubInset, angleDegrees: bar.degrees))
        }
        var slideBars: Int { bars.filter { $0.kind == .slideBar }.count }
        for hole in holes where !uCells.contains(hole) && (!mirror || hole.c <= twin(hole).c) && slideBars < options.bars {
            // Prefer a ring with another ring across the hole, which stops the bar.
            let choices = allSteps.shuffled(using: &rng).sorted { a, _ in rings.contains(hole.moved(a)) }
            for step in choices {
                guard let bar = holeBar(hole, step) else { continue }
                if mirror {
                    // The image of the bar from the image of the hole; on the axis, only along it.
                    let image = Cell(c: -step.c, r: step.r)
                    if twin(hole) == hole {
                        guard image == step else { continue }
                    } else {
                        addBar(bar)
                        guard let mirrored = holeBar(twin(hole), image) else {
                            // Undo: the ring keeps no gap and the bar goes.
                            gapAt[bar.ring] = nil
                            pokedRings.remove(bar.ring)
                            bars.removeLast()
                            continue
                        }
                        addBar(mirrored)
                        break
                    }
                }
                addBar(bar)
                break
            }
        }

        for ring in rings where !closed.contains(ring) && gapAt[ring] == nil {
            guard let index = draft.index(of: id(ring)) else { return nil }
            let widths = widths(ring)
            var placed = false
            /// With `mirror`, the width the image takes for the image of gap `k`.
            func imageWidth(_ k: Int) -> Double? {
                let image = twin(ring)
                if image == ring { return twin(direction: k) == k ? 0 : nil }
                return Knot.widths(of: image, holders: holders[image] != nil, draft: draft, id: id).first {
                    draft.gapIsValid(centerDegrees: Double(twin(direction: k)) * ForgeRules.gridDegrees, gapDegrees: $0, for: id(image))
                }
            }
            for width in widths {
                let choices = (0..<8).filter {
                    draft.gapIsValid(centerDegrees: Double($0) * ForgeRules.gridDegrees, gapDegrees: width, for: id(ring))
                        && (!mirror || imageWidth($0) != nil)
                }
                guard !choices.isEmpty else { continue }
                let choice = rng.pick(choices)
                draft.pieces[index].setGap(centerDegrees: Double(choice) * ForgeRules.gridDegrees, degrees: width)
                gapAt[ring] = choice
                if mirror, twin(ring) != ring, let imageIndex = draft.index(of: id(twin(ring))), let imageWidth = imageWidth(choice) {
                    draft.pieces[imageIndex].setGap(centerDegrees: Double(twin(direction: choice)) * ForgeRules.gridDegrees, degrees: imageWidth)
                    gapAt[twin(ring)] = twin(direction: choice)
                }
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
            func bombAngles(_ ring: Cell) -> [Double] {
                guard let index = draft.index(of: id(ring)) else { return [] }
                let piece = draft.pieces[index]
                let gap = piece.gapCenterDegrees
                let gapHalf = (piece.gapDegrees ?? 0) / 2
                let busy = draft.contactAngles(on: id(ring)) + draft.stemRootAngles(of: id(ring))
                return (0..<8).map { Double($0) * ForgeRules.gridDegrees }.filter { angle in
                    (gap.map { degreeDifference($0, angle) > gapHalf + 30 } ?? true) && busy.allSatisfy { degreeDifference($0, angle) >= 40 }
                }
            }
            for ring in free.shuffled(using: &rng) where placed < options.bombs && (!mirror || (ring.c <= twin(ring).c && free.contains(twin(ring)))) {
                guard let index = draft.index(of: id(ring)), let radius = draft.pieces[index].radius else { continue }
                var choices = bombAngles(ring)
                if mirror {
                    // The image's bomb at the mirrored angle; on the axis straight up or down.
                    let imageAngles = bombAngles(twin(ring))
                    choices = choices.filter { angle in imageAngles.contains { degreeDifference($0, normalizedDegrees(180 - angle)) < 0.5 } }
                }
                guard !choices.isEmpty else { continue }
                let degrees = rng.pick(choices)
                let angle = AngleMath.radians(fromDegrees: degrees)
                draft.pieces[index].bomb = Point(cos(angle), sin(angle)) * radius
                let imageIndex = mirror ? draft.index(of: id(twin(ring))) : nil
                if let imageIndex, imageIndex != index {
                    let image = AngleMath.radians(fromDegrees: 180 - degrees)
                    draft.pieces[imageIndex].bomb = Point(cos(image), sin(image)) * radius
                }
                if stands(draft.pieces) {
                    placed += copies(ring).count
                } else {
                    draft.pieces[index].bomb = nil
                    if let imageIndex { draft.pieces[imageIndex].bomb = nil }
                }
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
            func tailDirections(_ ring: Cell) -> [Int] {
                guard let gap = gapAt[ring] else { return [] }
                let taken = Set(((holders[ring] ?? []) + (targets[ring] ?? [])).map { linkAngle(ring, $0) })
                return (0..<8).filter { position in
                    let fromGap = min((position - gap + 8) % 8, (gap - position + 8) % 8)
                    return fromGap >= 2 && !taken.contains(position) && !taken.contains((position + 1) % 8) && !taken.contains((position + 7) % 8)
                }
            }
            for ring in rings.shuffled(using: &rng) where !closed.contains(ring) && (!mirror || ring.c <= twin(ring).c) && rng.chance(options.tailShare) {
                guard let index = draft.index(of: id(ring)), gapAt[ring] != nil else { continue }
                var free = tailDirections(ring)
                if mirror {
                    let imageFree = tailDirections(twin(ring))
                    free = free.filter { imageFree.contains(twin(direction: $0)) }
                }
                guard !free.isEmpty else { continue }
                let before = draft.pieces
                let k = rng.pick(free)
                draft.pieces[index].addTail(atDegrees: Double(k) * ForgeRules.gridDegrees, length: shape.stem - 4)
                if mirror, twin(ring) != ring, let imageIndex = draft.index(of: id(twin(ring))) {
                    draft.pieces[imageIndex].addTail(atDegrees: Double(twin(direction: k)) * ForgeRules.gridDegrees, length: shape.stem - 4)
                }
                if !stands(draft.pieces) { draft.pieces = before }
            }
        }

        var motif = Motif(name: options.name, template: options.template, pieces: draft.pieces)
        motif.mirrorColors = mirror && options.mirrorColors
        guard motif.width <= options.board.width - 2 * ForgeRules.margin,
              motif.height <= options.board.height - 2 * ForgeRules.margin else {
            LevelTemplate.debug?("\(options.template): \(Int(motif.width))×\(Int(motif.height)) does not fit the board")
            return nil
        }
        return motif
    }
}
