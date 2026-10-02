//
//  LatticeMotifs.swift
//  RotateRings
//
//  Larger motifs for the curve levels: a grid of rings wired as a dependency tree, plus the
//  showcase shapes (flower, triple concentric). Lattices are where later levels get their piece
//  counts, their coupling and their dead ends.
//
//  Wiring rule: in a tree, every parent grips its children, so leaves move first and the root leaves
//  last. Extra cross clips make a ring gripped by two owners; freeing the wrong one first leaves a
//  loose clip in the way, which is the kind of trap that makes a level hard.
//

import Foundation

extension Motifs {

    /// Ring radius for a lattice with `cols` columns so that it fits between the board margins.
    static func latticeRadius(cols: Int) -> Double {
        // Two columns at 40 leave room for a ring chain beside the lattice. Four columns at 30 are
        // the smallest rings that still allow a one-step lock (see ForgeRules.supportsOneStepLock).
        switch cols {
        case ...2: return 40
        case 3: return 40
        default: return 30
        }
    }

    /// A rows × cols grid of rings. `fill` below 1 knocks random cells out. `crossClips` adds that
    /// many extra owner→target clips beyond the spanning tree. `anchorChance` turns tree roots that
    /// nobody grips into closed rings.
    static func lattice(rows: Int, cols: Int, fill: Double = 1, crossClips: Int = 0, anchorChance: Double = 0.3, lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let radius = latticeRadius(cols: cols)
        let spacing = 2 * radius + ForgeRules.preferredStem

        // Occupied cells.
        var occupied: [[Bool]] = Array(repeating: Array(repeating: true, count: cols), count: rows)
        let total = rows * cols
        let removeCount = min(total - 2, Int((Double(total) * (1 - fill)).rounded()))
        var removable = (0..<total).shuffled(using: &rng)
        for _ in 0..<removeCount {
            let cell = removable.removeFirst()
            occupied[cell / cols][cell % cols] = false
        }

        func id(_ r: Int, _ c: Int) -> String { "g\(r)_\(c)" }
        func neighbors(_ r: Int, _ c: Int) -> [(Int, Int)] {
            [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)].filter { $0.0 >= 0 && $0.0 < rows && $0.1 >= 0 && $0.1 < cols && occupied[$0.0][$0.1] }
        }

        // Spanning forest by randomised depth-first search: long paths, few leaves, so the solver's
        // state space stays small.
        var parent: [String: String?] = [:]
        var depth: [String: Int] = [:]
        var edges: [(owner: String, target: String)] = []
        var cells = (0..<rows).flatMap { r in (0..<cols).map { c in (r, c) } }.filter { occupied[$0.0][$0.1] }
        cells.shuffle(using: &rng)
        for start in cells where parent[id(start.0, start.1)] == nil {
            parent[id(start.0, start.1)] = .some(nil)
            depth[id(start.0, start.1)] = 0
            var stack = [start]
            while let current = stack.last {
                let unvisited = neighbors(current.0, current.1).filter { parent[id($0.0, $0.1)] == nil }
                guard !unvisited.isEmpty else {
                    stack.removeLast()
                    continue
                }
                let next = rng.pick(unvisited)
                parent[id(next.0, next.1)] = .some(id(current.0, current.1))
                depth[id(next.0, next.1)] = (depth[id(current.0, current.1)] ?? 0) + 1
                edges.append((id(current.0, current.1), id(next.0, next.1)))
                stack.append(next)
            }
        }
        // Isolated cells would be removed on load; drop them.
        let connected = Set(edges.flatMap { [$0.owner, $0.target] })
        for (r, c) in cells where !connected.contains(id(r, c)) { occupied[r][c] = false }
        cells = cells.filter { occupied[$0.0][$0.1] }
        guard cells.count >= 2 else { return nil }

        // Cross clips: a second owner for a leaf, from a neighbour that is shallower in the tree so the
        // owner graph stays acyclic. Only leaves: a ring that keeps a second owner's loose clip must
        // be able to leave as soon as its last clip is freed. At most one per target and per owner.
        let treeOwners = Set(edges.map(\.owner))
        var crossEdges: [(owner: String, target: String)] = []
        var attempts = 0
        while crossEdges.count < crossClips && attempts < 40 {
            attempts += 1
            let (r, c) = rng.pick(cells)
            let target = id(r, c)
            guard !treeOwners.contains(target), !crossEdges.contains(where: { $0.target == target }) else { continue }
            let candidates = neighbors(r, c).map { id($0.0, $0.1) }.filter { owner in
                owner != parent[target] ?? nil && (depth[owner] ?? 0) < (depth[target] ?? 0)
                    && !edges.contains { $0.owner == owner && $0.target == target }
                    && !crossEdges.contains { $0.owner == owner }
            }
            if let owner = candidates.first { crossEdges.append((owner, target)) }
        }

        // Build pieces.
        var draft = LevelDraft(name: "Lattice \(rows)×\(cols)", template: "lattice\(rows)x\(cols)")
        let gripped = Set((edges + crossEdges).map(\.target))
        for (r, c) in cells {
            let position = Point((Double(c) - Double(cols - 1) / 2) * spacing, (Double(rows - 1) / 2 - Double(r)) * spacing)
            let ringID = id(r, c)
            if !gripped.contains(ringID), Double(rng.next() % 1000) / 1000 < anchorChance {
                draft.pieces.append(.closedRing(ringID, at: position, radius: radius))
            } else {
                draft.pieces.append(.ring(ringID, at: position, radius: radius))
            }
        }
        for edge in edges + crossEdges {
            guard draft.addRingClip(from: edge.owner, to: edge.target) else { return nil }
        }
        let owners = Set((edges + crossEdges).map(\.owner))
        let crossTargets = Set(crossEdges.map(\.target))
        for piece in draft.pieces where !piece.isClosedRing {
            if crossTargets.contains(piece.id) {
                guard draft.planSharedGap(for: piece.id, rng: &rng) != nil else { return nil }
            } else if gripped.contains(piece.id) {
                // A ring that also owns clips keeps a loose clip after its children leave. That clip
                // sweeps a circle touching every neighbouring ring, so only a single step is safe.
                let steps = owners.contains(piece.id) ? (rng.bool() ? 1 : -1) : rng.lockSteps(in: lockRange)
                guard let used = draft.planGap(for: piece.id, lockSteps: steps) else { return nil }
                if owners.contains(piece.id) && abs(used) != 1 { return nil }
            } else {
                guard draft.planFreeGap(for: piece.id, rng: &rng) else { return nil }
            }
        }
        return Motif(name: draft.name, template: draft.template, pieces: draft.pieces)
    }

    /// A closed anchor with eight small satellites all round: the showcase star. The anchor is wide
    /// enough that neighbouring satellites stay more than touching distance apart, so each can leave.
    static func flower(lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let anchorRadius = 48.0, satelliteRadius = 26.0
        let distance = anchorRadius + ForgeRules.preferredStem + satelliteRadius
        var draft = LevelDraft(name: "Flower", template: "flower")
        draft.pieces.append(.closedRing("o", at: .zero, radius: anchorRadius))
        for i in 0..<8 {
            let angle = Double(i) * 45
            let direction = Point(cos(AngleMath.radians(fromDegrees: angle)), sin(AngleMath.radians(fromDegrees: angle)))
            draft.pieces.append(.ring("s\(i)", at: direction * distance, radius: satelliteRadius))
            guard draft.addClip(from: "o", at: direction * anchorRadius, to: "s\(i)") else { return nil }
        }
        for i in 0..<8 {
            guard draft.planGap(for: "s\(i)", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        }
        return Motif(name: draft.name, template: draft.template, pieces: draft.pieces)
    }

    /// Three concentric rings: a closed outer ring grips a middle C-ring, which grips an inner
    /// C-ring. Optional satellites hang off the outer ring at the grid angles.
    static func concentricTriple(satellites: Int, lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let outer = 80.0, middle = 55.0, inner = 30.0
        var draft = LevelDraft(name: satellites == 0 ? "Rings within rings" : "Orbit", template: "concentricTriple")
        draft.pieces = [
            .closedRing("o", at: .zero, radius: outer),
            .ring("m", at: .zero, radius: middle),
            .ring("i", at: .zero, radius: inner),
        ]
        let angleOM = Double(rng.int(in: 0...7)) * 45
        let angleMI = normalizedDegrees(angleOM + Double(rng.pick([90.0, 180, 270])))
        func direction(_ degrees: Double) -> Point {
            Point(cos(AngleMath.radians(fromDegrees: degrees)), sin(AngleMath.radians(fromDegrees: degrees)))
        }
        guard draft.addClip(from: "o", at: direction(angleOM) * outer, to: "m"),
              draft.addClip(from: "m", at: direction(angleMI) * middle, to: "i") else { return nil }
        let satelliteRadius = 35.0
        var satelliteAngles: [Double] = []
        if satellites > 0 {
            // Satellites only fit above and below (the board is narrow); use 90° and 270°.
            satelliteAngles = satellites >= 2 ? [90, 270] : [rng.pick([90.0, 270.0])]
            for (index, angle) in satelliteAngles.enumerated() {
                draft.pieces.append(.ring("s\(index)", at: direction(angle) * (outer + ForgeRules.preferredStem + satelliteRadius), radius: satelliteRadius))
                guard draft.addClip(from: "o", at: direction(angle) * outer, to: "s\(index)") else { return nil }
            }
        }
        guard draft.planGap(for: "i", lockSteps: rng.lockSteps(in: lockRange)) != nil,
              draft.planGap(for: "m", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        for index in satelliteAngles.indices {
            guard draft.planGap(for: "s\(index)", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        }
        return Motif(name: draft.name, template: draft.template, pieces: draft.pieces)
    }
}
