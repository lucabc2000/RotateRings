//
//  RingNet.swift
//  RotateRings
//
//  Rings laid out as a figure instead of a plain rectangle: a mask says where the rings sit, on a
//  square grid or on a diagonal one (every ring gripping its neighbours at 45°). The wiring is the
//  lattice's (a dependency tree per component, leaves move first), but mirrored left to right, so
//  the board reads as one symmetric shape. Empty cells marked as holes can hold a sliding bar whose
//  end pokes into a neighbouring ring's gap and locks it until the bar is slid away.
//
//  Tails make a figure hard. A ring's tail reaches into the gap of a neighbour it does not grip, so
//  that neighbour, a leaf that would otherwise be free from the start, has to wait until the tailed
//  ring has left, which in turn waits for everything that ring grips. Leaves stop being free and
//  the trees depend on each other.
//

import Foundation

enum RingNet {
    enum Layout {
        /// Neighbours left, right, above and below.
        case square
        /// Neighbours on the four diagonals; the mask uses every other cell, like a checkerboard.
        case diagonal
    }

    struct Shape {
        var name: String
        var template: String
        var layout: Layout
        var radius: Double
        var stem: Double
        /// The mask, top row first: `#` is a ring, `o` an empty cell that may hold a bar, anything
        /// else stays empty. Rows that read the same backwards give a mirrored board.
        var rows: [String]
    }

    struct Options {
        /// Mirror the wiring and the gaps left to right (needs a symmetric mask).
        var mirrored = true
        /// Extra owner→leaf clips beyond the tree, per half when mirrored.
        var crossClips = 0
        /// Chance that a ring nobody grips becomes a closed ring.
        var anchorChance = 0.4
        /// Most bars threaded into holes, per half when mirrored.
        var bars = 0
        /// Chance that a threaded bar is long enough to be stopped by the ring across the hole.
        var blockedBarChance = 0.35
        /// Most tails locking a neighbouring leaf, per half when mirrored.
        var tails = 0
        var lockRange: ClosedRange<Int> = 1...3
    }

    private struct Cell: Hashable {
        var c: Int
        var r: Int
    }

    static func build(_ shape: Shape, options: Options, rng: inout SplitMix64) -> Motif? {
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
        func twin(_ cell: Cell) -> Cell { Cell(c: colCount - 1 - cell.c, r: cell.r) }
        func neighbors(_ cell: Cell) -> [Cell] {
            steps.map { Cell(c: cell.c + $0.c, r: cell.r + $0.r) }.filter { mark($0) == "#" }
        }

        let mirrored = options.mirrored && shape.rows.allSatisfy { $0 == String($0.reversed()) }
        func onAxis(_ cell: Cell) -> Bool { mirrored && cell.c == colCount - 1 - cell.c }
        func inHalf(_ cell: Cell) -> Bool { !mirrored || cell.c <= colCount - 1 - cell.c }

        var sites: [Cell] = []
        for r in 0..<rowCount {
            for c in 0..<colCount where mark(Cell(c: c, r: r)) == "#" { sites.append(Cell(c: c, r: r)) }
        }
        var half = sites.filter(inHalf)
        half.shuffle(using: &rng)
        // Trees start on the axis, and a ring on the axis is only ever gripped from the axis, so the
        // mirror image never gives it a second owner.
        half = half.filter(onAxis) + half.filter { !onAxis($0) }

        // Spanning forest by randomised depth-first search, as in the lattice.
        var parent: [Cell: Cell?] = [:]
        var depth: [Cell: Int] = [:]
        var edges: [(owner: Cell, target: Cell)] = []
        for start in half where parent[start] == nil {
            parent[start] = .some(nil)
            depth[start] = 0
            var stack = [start]
            while let current = stack.last {
                let open = neighbors(current).filter { inHalf($0) && parent[$0] == nil && (onAxis(current) || !onAxis($0)) }
                guard !open.isEmpty else {
                    stack.removeLast()
                    continue
                }
                let next = rng.pick(open)
                parent[next] = .some(current)
                depth[next] = (depth[current] ?? 0) + 1
                edges.append((current, next))
                stack.append(next)
            }
        }
        // A ring on the axis that the search reached too late has no neighbour left to grip. Hand it
        // one: a neighbouring tree root becomes its child, or it takes a neighbour over from an
        // owner that keeps another connection. Failing both, a neighbour grips it; the mirror image
        // adds a second owner from the other side, so it is planned like a cross-clipped leaf.
        var sharedOnAxis = Set<Cell>()
        for cell in half where onAxis(cell) && !edges.contains(where: { $0.owner == cell || $0.target == cell }) {
            let candidates = neighbors(cell).filter { inHalf($0) && !onAxis($0) }.shuffled(using: &rng)
            func connections(of other: Cell) -> Int { edges.filter { $0.owner == other || $0.target == other }.count }
            if let root = candidates.first(where: { (parent[$0] ?? nil) == nil && connections(of: $0) > 0 }) {
                parent[root] = .some(cell)
                edges.append((cell, root))
            } else if let child = candidates.first(where: { other in (parent[other] ?? nil).map { connections(of: $0) >= 2 } ?? false }),
                      let old = parent[child] ?? nil {
                edges.removeAll { $0.owner == old && $0.target == child }
                parent[child] = .some(cell)
                edges.append((cell, child))
            } else if let owner = candidates.first(where: { connections(of: $0) > 0 }) {
                parent[cell] = .some(owner)
                edges.append((owner, cell))
                sharedOnAxis.insert(cell)
            }
        }
        let wired = Set(edges.flatMap { [$0.owner, $0.target] })
        half = half.filter { wired.contains($0) }
        guard half.count >= 2 else { return nil }
        for cell in half {
            var steps = 0
            var current = parent[cell] ?? nil
            while let up = current {
                steps += 1
                current = parent[up] ?? nil
            }
            depth[cell] = steps
        }

        // Cross clips: a second owner for a leaf, from a shallower neighbour (see `Motifs.lattice`).
        let treeOwners = Set(edges.map(\.owner))
        var crossEdges: [(owner: Cell, target: Cell)] = []
        var attempts = 0
        while crossEdges.count < options.crossClips && attempts < 40 + 30 * options.crossClips {
            attempts += 1
            let target = rng.pick(half)
            guard !onAxis(target), !treeOwners.contains(target), !crossEdges.contains(where: { $0.target == target || $0.owner == target }) else { continue }
            let owners = neighbors(target).filter { owner in
                guard inHalf(owner), !onAxis(owner), wired.contains(owner), let first = parent[target] ?? nil, owner != first,
                      !crossEdges.contains(where: { $0.owner == owner || $0.target == owner }) else { return false }
                return (depth[owner] ?? 0) < (depth[target] ?? 0)
            }
            if let owner = owners.first { crossEdges.append((owner, target)) }
        }

        var allEdges = edges + crossEdges
        if mirrored {
            for edge in edges + crossEdges where !(onAxis(edge.owner) && onAxis(edge.target)) {
                allEdges.append((twin(edge.owner), twin(edge.target)))
            }
        }

        // Pieces for both halves.
        var draft = LevelDraft(name: shape.name, template: shape.template)
        let gripped = Set(allEdges.map(\.target))
        for cell in half {
            let closed = !gripped.contains(cell) && rng.chance(options.anchorChance)
            for copy in mirrored && !onAxis(cell) ? [cell, twin(cell)] : [cell] {
                draft.pieces.append(closed ? .closedRing(id(copy), at: position(copy), radius: shape.radius)
                                           : .ring(id(copy), at: position(copy), radius: shape.radius))
            }
        }
        for edge in allEdges {
            guard draft.addRingClip(from: id(edge.owner), to: id(edge.target)) else {
                LevelTemplate.debug?("\(shape.template): no clip from \(id(edge.owner)) to \(id(edge.target))")
                return nil
            }
        }

        // Bars threaded into holes. Only a leaf can take one: its gap has to face the hole, and a
        // ring that also owns clips needs its gap one step from its owner instead.
        let owners = Set(allEdges.map(\.owner))
        let crossTargets = Set(crossEdges.map(\.target)).union(sharedOnAxis)
        var bars: [DraftPiece] = []
        var fixedGaps = Set<Cell>()
        var usedHoles = Set<Cell>()
        for leaf in half.shuffled(using: &rng) where bars.count < options.bars {
            guard gripped.contains(leaf), !owners.contains(leaf), !crossTargets.contains(leaf) else { continue }
            for step in steps.shuffled(using: &rng) {
                let hole = Cell(c: leaf.c + step.c, r: leaf.r + step.r)
                // A hole on the axis is only for a ring on the axis: its mirror image is itself.
                guard mark(hole) == "o", !usedHoles.contains(hole), onAxis(hole) == onAxis(leaf) else { continue }
                let direction = Point(Double(step.c), Double(-step.r)).normalized()
                let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: direction.angle))
                guard draft.gapIsValid(centerDegrees: degrees, gapDegrees: ForgeRules.defaultGapDegrees, for: id(leaf)),
                      let index = draft.index(of: id(leaf)) else { continue }

                // The bar starts just inside the ring and ends at the middle of the hole, short enough
                // to slide out before it reaches the ring across the hole. A long bar is stopped by
                // that ring instead, which then has to go first; it must not be one of the leaf's own
                // ancestors, or neither could ever leave.
                let across = Cell(c: leaf.c + 2 * step.c, r: leaf.r + 2 * step.r)
                let pokeStart = shape.radius - 10
                let exitTravel = GameRules.holderLength / 2 + 1 + GridWorld.hubInset
                var end = mark(across) == "#" ? min(reach, 2 * reach - shape.radius - exitTravel - 16) : reach
                if mark(across) == "#", inHalf(across), rng.chance(options.blockedBarChance) {
                    var ancestor = parent[leaf] ?? nil
                    var isAncestor = false
                    while let current = ancestor {
                        if current == across { isAncestor = true }
                        ancestor = parent[current] ?? nil
                    }
                    if !isAncestor { end = 2 * reach - shape.radius - exitTravel - 2 }
                }
                guard end - pokeStart >= 2 * GridWorld.hubInset else { continue }
                draft.pieces[index].setGap(centerDegrees: degrees, degrees: ForgeRules.defaultGapDegrees)
                bars.append(.slideBar("bar\(bars.count)", at: position(leaf) + direction * (pokeStart + GridWorld.hubInset),
                                      from: -GridWorld.hubInset, to: end - pokeStart - GridWorld.hubInset, angleDegrees: degrees))
                fixedGaps.insert(leaf)
                usedHoles.insert(hole)
                usedHoles.insert(twin(hole))
                break
            }
        }

        // Tails: ring `other` gets a tail that ends on the circle of its neighbour `leaf`, inside the
        // leaf's gap. The leaf cannot turn until the tailed ring is gone. The tailed ring must not
        // have to wait for the leaf in turn (the leaf below it in its own tree, or locked through a
        // chain of other tails), or neither could ever leave.
        let halfSet = Set(half)
        var tailed = Set<Cell>()
        var locks: [Cell: [Cell]] = [:]
        func waitsFor(_ early: Cell, _ late: Cell) -> Bool {
            // Whether `early` has to leave before `late`: up the tree, across cross clips and tails.
            var seen: Set<Cell> = [early]
            var queue = [early]
            while let current = queue.popLast() {
                if current == late { return true }
                var next = locks[current] ?? []
                if let up = parent[current] ?? nil { next.append(up) }
                next += crossEdges.filter { $0.target == current }.map(\.owner)
                for cell in next where seen.insert(cell).inserted { queue.append(cell) }
            }
            return false
        }
        var tailCount = 0
        for leaf in options.tails > 0 ? half.shuffled(using: &rng) : [] where tailCount < options.tails {
            guard gripped.contains(leaf), !owners.contains(leaf), !crossTargets.contains(leaf),
                  !fixedGaps.contains(leaf), !tailed.contains(leaf) else { continue }
            for step in steps.shuffled(using: &rng) {
                let other = Cell(c: leaf.c + step.c, r: leaf.r + step.r)
                guard halfSet.contains(other), onAxis(other) == onAxis(leaf), !tailed.contains(other), !fixedGaps.contains(other),
                      !crossTargets.contains(other), !allEdges.contains(where: { $0.owner == other && $0.target == leaf }),
                      !waitsFor(leaf, other) else { continue }
                let towardOther = Point(Double(step.c), Double(-step.r)).normalized()
                let gapDegrees = normalizedDegrees(AngleMath.degrees(fromRadians: towardOther.angle))
                guard draft.gapIsValid(centerDegrees: gapDegrees, gapDegrees: ForgeRules.defaultGapDegrees, for: id(leaf)),
                      let leafIndex = draft.index(of: id(leaf)) else { continue }
                draft.pieces[leafIndex].setGap(centerDegrees: gapDegrees, degrees: ForgeRules.defaultGapDegrees)
                for (from, to) in mirrored && !onAxis(other) ? [(other, leaf), (twin(other), twin(leaf))] : [(other, leaf)] {
                    guard let index = draft.index(of: id(from)) else { continue }
                    let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: (position(to) - position(from)).angle))
                    draft.pieces[index].addTail(atDegrees: degrees, length: shape.stem)
                }
                fixedGaps.insert(leaf)
                tailed.insert(other)
                locks[other, default: []].append(leaf)
                tailCount += 1
                break
            }
        }

        // Gaps for the planned half.
        for cell in half where !fixedGaps.contains(cell) {
            guard let piece = draft[id(cell)], !piece.isClosedRing else { continue }
            if crossTargets.contains(cell) {
                guard draft.planSharedGap(for: piece.id, rng: &rng) != nil else {
                    LevelTemplate.debug?("\(shape.template): no shared gap for \(piece.id)")
                    return nil
                }
            } else if gripped.contains(cell) {
                // A ring that also owns clips keeps a loose clip once its children are gone; only a
                // single step keeps that clip, or a tail, clear of the neighbours.
                let singleStep = owners.contains(cell) || tailed.contains(cell)
                let steps = singleStep ? (rng.bool() ? 1 : -1) : rng.lockSteps(in: options.lockRange)
                guard let used = draft.planGap(for: piece.id, lockSteps: steps), !singleStep || abs(used) == 1 else {
                    LevelTemplate.debug?("\(shape.template): no gap for \(piece.id)")
                    return nil
                }
            } else if !draft.planFreeGap(for: piece.id, rng: &rng), let index = draft.index(of: piece.id) {
                // Clips all round leave no room for a gap. Nothing grips this ring, so it can be closed.
                draft.pieces[index].closeRing()
                if mirrored, !onAxis(cell), let other = draft.index(of: id(twin(cell))) {
                    draft.pieces[other].closeRing()
                }
            }
        }

        // The other half mirrors the gaps and the bars.
        if mirrored {
            for cell in half where !onAxis(cell) {
                guard let source = draft[id(cell)], let center = source.gapCenterDegrees, let width = source.gapDegrees,
                      let index = draft.index(of: id(twin(cell))) else { continue }
                draft.pieces[index].setGap(centerDegrees: normalizedDegrees(180 - center), degrees: width)
            }
            for bar in bars where abs(bar.position.x) > 1 {
                var copy = bar.mirrored(flipX: true, flipY: false)
                copy.id = bar.id + "m"
                bars.append(copy)
            }
        }
        draft.pieces += bars

        let motif = Motif(name: shape.name, template: shape.template, pieces: draft.pieces)
        guard motif.width <= ForgeRules.boardWidth - 2 * ForgeRules.margin,
              motif.height <= ForgeRules.boardHeight - 2 * ForgeRules.margin else {
            LevelTemplate.debug?("\(shape.template): \(Int(motif.width))×\(Int(motif.height)) does not fit the board")
            return nil
        }
        return motif
    }
}
