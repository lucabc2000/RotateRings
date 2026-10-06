//
//  Tangle.swift
//  RotateRings
//
//  Free-form levels: a cluster of rings in many sizes that grows outwards from a seed, each ring
//  hung on another at whatever angle has room, with bars worked in. Nothing sits on a grid, which
//  is what makes these boards look placed by hand rather than generated.
//
//  Growth gives a tree: every ring grips the rings hung on it, so the leaves move first and the
//  seed leaves last. A ring that grips others and is gripped itself has to turn one step with its
//  loose clips once its children are gone, so only rings of at least `oneStepRadius` get children
//  while they hang on something. Bars lock leaves: a sliding bar whose inner end sits in a leaf's
//  gap, or a latch bar pinned by its clip on a ring that reaches into another ring's gap.
//
//  Angles are free, so every draft is played through once with greedy moves (`LevelSolver.
//  greedyPlayout`) before it is accepted; that catches the turns that run into a neighbour.
//

import Foundation

enum Tangle {
    struct Options {
        /// Rings to place, including the seed and any rings added for latch bars.
        var rings: ClosedRange<Int>
        /// Sliding bars poking into leaves' gaps.
        var pokeBars = 0
        /// Prefer poke bars whose way out is blocked by another ring (see `addPokeBar`).
        var blockedPokes = false
        /// Latch bars: each hangs a new ring on a bar that reaches into a leaf's gap.
        var latchBars = 0
        /// Chance that a ring is hung on the ring placed just before it, which makes chains.
        var chain = 0.55
        /// Start from a giant closed ring with rings hung inside and outside it.
        var planet = false
        /// Seeds to grow from. Each is a tree of its own, usually around a closed hub, and the
        /// trees grow into the space between each other.
        var hubs = 1
        /// Half the height the tangle may take; nil is the whole board. For sharing the board with
        /// another motif.
        var halfHeight: Double? = nil
        var lockRange: ClosedRange<Int> = 1...3
        /// Ring sizes to draw from; smaller ones for crowded boards.
        var radii: [Double] = [28, 32, 36, 40, 46, 54]
        var name = "Tangle"
        var template = "tangle"
    }

    /// Debugging aid for the generator tool: keep drafts that cannot be played through, to look at.
    nonisolated(unsafe) static var keepStuck = false

    /// Smallest ring that can still hang children while hanging on something itself.
    static let oneStepRadius = 30.0
    /// Clearance between bodies that are not meant to touch: more than `GameRules.touchDistance`.
    static let clearance = 18.0
    private static let halfWidth = ForgeRules.boardWidth / 2 - ForgeRules.margin
    private static let boardHalfHeight = ForgeRules.boardHeight / 2 - ForgeRules.margin

    /// A body to keep clear of: a ring's circle or a bar's segment.
    private enum Body {
        case circle(Point, Double)
        case segment(Point, Point)

        func distance(to other: Body) -> Double {
            switch (self, other) {
            case (.circle(let c1, let r1), .circle(let c2, let r2)):
                let d = c1.distance(to: c2)
                if d >= r1 + r2 { return d - r1 - r2 }
                let inner = min(r1, r2), outer = max(r1, r2)
                return d + inner <= outer ? outer - d - inner : 0
            case (.circle(let c, let r), .segment(let a, let b)), (.segment(let a, let b), .circle(let c, let r)):
                // Nearest the segment comes to the circle's stroke, sampled along the segment.
                return Geometry.samplePoints(on: Segment(from: a, to: b), spacing: GameRules.distanceSampleSpacing)
                    .map { abs($0.distance(to: c) - r) }.min() ?? .infinity
            case (.segment(let a, let b), .segment(let c, let d)):
                return Geometry.distance(Segment(from: a, to: b), Segment(from: c, to: d))
            }
        }

        /// Whether the body stays inside the board's margins, within `halfHeight` of the middle.
        func fits(halfHeight: Double) -> Bool {
            let pad = GameRules.strokeThickness / 2
            switch self {
            case .circle(let c, let r):
                return abs(c.x) + r + pad <= Tangle.halfWidth && abs(c.y) + r + pad <= halfHeight
            case .segment(let a, let b):
                return [a, b].allSatisfy { abs($0.x) + pad <= Tangle.halfWidth && abs($0.y) + pad <= halfHeight }
            }
        }
    }

    private struct Builder {
        var draft: LevelDraft
        var rng: SplitMix64
        var halfHeight = Tangle.boardHalfHeight
        var parent: [String: String] = [:]
        var childCount: [String: Int] = [:]
        /// Which way a gripped ring will turn (gap one step this side of its clip) once its children
        /// are gone: +1 or -1. Decided when it gets its first child, so the sweep can be kept clear.
        var turn: [String: Int] = [:]
        var radius: [String: Double] = [:]
        /// Bodies placed so far, by piece id.
        var bodies: [(id: String, body: Body)] = []
        /// Rings whose gap is already decided (poked by a bar).
        var fixedGaps = Set<String>()
        var lastRing = ""
        var counter = 0

        func direction(_ degrees: Double) -> Point {
            Point(cos(AngleMath.radians(fromDegrees: degrees)), sin(AngleMath.radians(fromDegrees: degrees)))
        }

        /// Whether `body` fits the board and keeps clear of everything but `except`. A clip's sweep
        /// only needs collision clearance, not touching clearance.
        func hasRoom(_ body: Body, except: Set<String> = [], minimum: Double = Tangle.clearance) -> Bool {
            guard body.fits(halfHeight: halfHeight) else { return false }
            return bodies.allSatisfy { other in
                except.contains(other.id) || other.body.distance(to: body) >= (other.id.hasPrefix("sweep:") ? min(minimum, GameRules.strokeThickness) : minimum)
            }
        }

        /// Whether a new clip may leave or land on `ring` at `degrees` without crowding its others.
        func hasFreeArc(on ring: String, at degrees: Double) -> Bool {
            guard let r = radius[ring] else { return false }
            let spacing = 2 * ForgeRules.clipHalfAngleDegrees(radius: r) + 24
            let taken = draft.contactAngles(on: ring) + draft.stemRootAngles(of: ring)
            return taken.allSatisfy { degreeDifference($0, degrees) >= spacing }
        }

        /// Whether a child may hang on `ring` at `degrees`. A gripped ring later turns one step
        /// towards its own clip, taking its loose clips along, so no child may sit where that
        /// sweep would carry a clip into the stem that holds the ring.
        func mayHangChild(on ring: String, at degrees: Double) -> Bool {
            guard hasFreeArc(on: ring, at: degrees), let r = radius[ring] else { return false }
            guard isGripped(ring), let contact = draft.contactAngles(on: ring).first, let sign = turn[ring] else { return true }
            let spacing = 2 * ForgeRules.clipHalfAngleDegrees(radius: r) + 24
            // Clips move by -sign × 45°, so the arc from the contact towards +sign is where a clip
            // would end up on the stem.
            let ahead = normalizedDegrees(Double(sign) * (degrees - contact))
            return ahead >= ForgeRules.gridDegrees + spacing
        }

        /// Spots a clip at `degrees` on `ring` passes through when the ring turns its step: along
        /// the stem and out to the square, every 15° of the turn. Other bodies keep collision
        /// clearance from these (see `hasRoom`).
        func sweep(of ring: String, at degrees: Double) -> [Body] {
            guard let r = radius[ring], let center = draft[ring]?.position, let sign = turn[ring] else { return [] }
            var spots: [Body] = []
            for k in 1...3 {
                let along = direction(degrees - Double(sign * k) * 15)
                spots.append(.circle(center + along * (r + 18), 8))
                spots.append(.circle(center + along * (r + 32), 8))
            }
            return spots
        }

        func isGripped(_ ring: String) -> Bool { parent[ring] != nil }

        mutating func addRing(_ id: String, at position: Point, radius r: Double, closed: Bool = false) {
            draft.pieces.append(closed ? .closedRing(id, at: position, radius: r) : .ring(id, at: position, radius: r))
            radius[id] = r
            bodies.append((id, .circle(position, r)))
            lastRing = id
        }

        // MARK: Growth

        /// Hangs one more ring on an existing one: on `forced` when given, otherwise on a ring of
        /// its choosing. False when nothing fitted this time.
        mutating func grow(options: Options, on forced: String? = nil) -> Bool {
            let rings = draft.pieces.filter { $0.radius != nil }.map(\.id)
            guard !rings.isEmpty else { return false }
            // Chains: continue from the last ring; otherwise from a ring with few children.
            let owner: String
            if let forced {
                owner = forced
            } else if rng.chance(options.chain), let last = rings.last, canOwn(last) {
                owner = last
            } else {
                // Rings with fewer children are more likely, but any ring may get one.
                let candidates = rings.filter(canOwn).flatMap { ring in Array(repeating: ring, count: max(1, 4 - (childCount[ring] ?? 0))) }
                guard !candidates.isEmpty else { return false }
                owner = rng.pick(candidates)
            }
            guard let ownerRadius = radius[owner], let ownerPosition = draft[owner]?.position else { return false }
            if isGripped(owner), turn[owner] == nil { turn[owner] = rng.bool() ? 1 : -1 }
            let family = Set(draft.pieces.compactMap { parent[$0.id] == owner ? $0.id : nil } + [owner, "sweep:" + owner])
            for _ in 0..<80 {
                let degrees = Double(rng.int(in: 0...71)) * 5
                guard mayHangChild(on: owner, at: degrees) else { continue }
                // Most rings are big enough to carry the chain on; the rest are small ends.
                let r = rng.chance(0.65) ? rng.pick(options.radii.filter { $0 >= Tangle.oneStepRadius }) : rng.pick(options.radii)
                let stem = Double(rng.int(in: 18...26))
                let position = ownerPosition + direction(degrees) * (ownerRadius + stem + r)
                // Clear of everything but the owner and the sweeps of the owner's other clips (the
                // new ring is gone by the time those sweep).
                guard hasRoom(.circle(position, r), except: [owner, "sweep:" + owner]) else { continue }
                // The owner's loose clip will sweep through here later; nothing but family may be there.
                let sweep = self.sweep(of: owner, at: degrees)
                guard sweep.allSatisfy({ hasRoom($0, except: family, minimum: 2) }) else { continue }
                counter += 1
                let id = "r\(counter)"
                addRing(id, at: position, radius: r)
                guard draft.addRingClip(from: owner, to: id) else {
                    draft.pieces.removeLast()
                    bodies.removeLast()
                    return false
                }
                parent[id] = owner
                childCount[owner, default: 0] += 1
                for body in sweep { bodies.append(("sweep:" + owner, body)) }
                return true
            }
            return false
        }

        /// A ring may get children when it is a root, or big enough to turn one step with loose clips.
        func canOwn(_ ring: String) -> Bool {
            guard let r = radius[ring] else { return false }
            return !isGripped(ring) || r >= Tangle.oneStepRadius
        }

        // MARK: Bars

        /// Leaves whose gap can still be chosen: gripped, no children, not yet locked.
        var openLeaves: [String] {
            draft.pieces.compactMap { piece in
                guard piece.radius != nil, isGripped(piece.id), childCount[piece.id] == nil, !fixedGaps.contains(piece.id) else { return nil }
                return piece.id
            }
        }

        /// Directions a leaf's gap may face: grid steps from its clip, never back at the clip.
        mutating func gapDirections(for leaf: String) -> [Double] {
            guard let contact = draft.contactAngles(on: leaf).first else { return [] }
            return (2...6).map { normalizedDegrees(contact + Double($0) * ForgeRules.gridDegrees) }.shuffled(using: &rng)
        }

        /// Rings that wait for `ring`: the ones it hangs on, up to the seed.
        func ancestors(of ring: String) -> Set<String> {
            var result = Set<String>()
            var current = parent[ring]
            while let up = current, result.insert(up).inserted { current = parent[up] }
            return result
        }

        /// A sliding bar with its inner end in a leaf's gap, pointing away from the leaf. With
        /// `blocked` the bar's way out runs into another ring, so the bar, and the leaf behind it,
        /// has to wait for that ring to go. That ring must not be one the leaf hangs on, or each
        /// would wait for the other. A free bar only swaps one free piece (the leaf) for another
        /// (the bar); a blocked one takes a free piece away, which is what makes a tangle hard.
        mutating func addPokeBar(blocked: Bool = false) -> Bool {
            for leaf in openLeaves.shuffled(using: &rng) {
                guard let r = radius[leaf], let center = draft[leaf]?.position else { continue }
                let waiting = ancestors(of: leaf)
                for degrees in gapDirections(for: leaf) {
                    let dir = direction(degrees)
                    let start = r - 10
                    let length = Double(rng.int(in: 50...90))
                    let inner = center + dir * start
                    let outer = center + dir * (start + length)
                    // The bar must be clear; the leaf's own arc ends are allowed close since the bar
                    // sits in the gap. The way out beyond it is clear too, or blocked by a ring.
                    let exit = Body.segment(outer, center + dir * (start + length + GameRules.holderLength / 2 + 1 + GridWorld.hubInset + 8))
                    let inTheWay = bodies.filter { $0.id != leaf && $0.body.distance(to: exit) < 12 }.map(\.id)
                    let wayOutFits = blocked
                        ? !inTheWay.isEmpty && inTheWay.allSatisfy { radius[$0] != nil && !waiting.contains($0) } && exit.fits(halfHeight: halfHeight)
                        : hasRoom(exit, except: [leaf], minimum: 12)
                    guard hasRoom(.segment(inner, outer), except: [leaf]), wayOutFits,
                          draft.gapIsValid(centerDegrees: degrees, gapDegrees: ForgeRules.defaultGapDegrees, for: leaf),
                          let index = draft.index(of: leaf) else { continue }
                    draft.pieces[index].setGap(centerDegrees: degrees, degrees: ForgeRules.defaultGapDegrees)
                    fixedGaps.insert(leaf)
                    counter += 1
                    let id = "s\(counter)"
                    draft.pieces.append(.slideBar(id, at: inner + dir * GridWorld.hubInset, from: -GridWorld.hubInset,
                                                  to: length - GridWorld.hubInset, angleDegrees: degrees))
                    bodies.append((id, .segment(inner, outer)))
                    return true
                }
            }
            return false
        }

        /// A latch bar: its far end sits in a leaf's gap, its near end carries a clip gripping a new
        /// ring hung beyond it. That ring turns to drop the bar; only then can the leaf turn.
        mutating func addLatchBar() -> Bool {
            for leaf in openLeaves.shuffled(using: &rng) {
                // The bar is a turning piece, so once released it only leaves when nothing touches
                // it. The leaf's arc ends come within r·sin(40°) of the bar, which must exceed the
                // touching distance: a small leaf would hold the dropped bar forever.
                guard let r = radius[leaf], r * sin(AngleMath.radians(fromDegrees: ForgeRules.defaultGapDegrees / 2)) >= GameRules.touchDistance + 2,
                      let center = draft[leaf]?.position else { continue }
                for degrees in gapDirections(for: leaf) {
                    let dir = direction(degrees)
                    let length = Double(rng.int(in: 90...140))
                    let inner = center + dir * (r - 15)
                    let outer = center + dir * (r - 15 + length)
                    let held = rng.pick([30.0, 36, 42])
                    let heldCenter = outer + dir * (ForgeRules.preferredStem + held)
                    guard hasRoom(.segment(inner, outer), except: [leaf]), hasRoom(.circle(heldCenter, held)),
                          draft.gapIsValid(centerDegrees: degrees, gapDegrees: ForgeRules.defaultGapDegrees, for: leaf),
                          let index = draft.index(of: leaf) else { continue }
                    draft.pieces[index].setGap(centerDegrees: degrees, degrees: ForgeRules.defaultGapDegrees)
                    fixedGaps.insert(leaf)
                    counter += 1
                    let barID = "b\(counter)"
                    let pivot = (inner + outer) * 0.5
                    draft.pieces.append(.latchBar(barID, at: pivot, from: -length / 2, to: length / 2, angleDegrees: degrees))
                    bodies.append((barID, .segment(inner, outer)))
                    counter += 1
                    let ringID = "r\(counter)"
                    addRing(ringID, at: heldCenter, radius: held)
                    guard draft.addClip(from: barID, at: outer, to: ringID) else { return false }
                    parent[ringID] = barID
                    return true
                }
            }
            return false
        }

        // MARK: Gaps

        /// Plans every ring's gap. Roots with clips all round close up instead.
        mutating func planGaps(options: Options) -> Bool {
            for piece in draft.pieces where piece.radius != nil && !piece.isClosedRing && !fixedGaps.contains(piece.id) {
                let owns = (childCount[piece.id] ?? 0) > 0
                if isGripped(piece.id) {
                    // An owner must turn the way its sweep was kept clear for, not just some single step.
                    let steps = owns ? (turn[piece.id] ?? 1) : rng.lockSteps(in: options.lockRange)
                    guard let used = draft.planGap(for: piece.id, lockSteps: steps), !owns || used == steps else {
                        LevelTemplate.debug?("\(options.template): no gap for \(piece.id)")
                        return false
                    }
                } else if !draft.planFreeGap(for: piece.id, rng: &rng), let index = draft.index(of: piece.id) {
                    draft.pieces[index].closeRing()
                }
            }
            return true
        }
    }

    static func build(_ options: Options, rng: inout SplitMix64) -> Motif? {
        var builder = Builder(draft: LevelDraft(name: options.name, template: options.template), rng: rng)
        builder.halfHeight = min(options.halfHeight ?? boardHalfHeight, boardHalfHeight)
        defer { rng = builder.rng }

        if options.planet {
            // A giant closed ring with two rings hung inside it; the rest grows from those and from
            // its top and bottom.
            let giant = 110.0
            builder.addRing("r0", at: .zero, radius: giant, closed: true)
            let first = Double(rng.int(in: 0...35)) * 10
            for degrees in [first, first + 120 + Double(rng.int(in: -15...15)), first + 240 + Double(rng.int(in: -15...15))] {
                let r = rng.pick([28.0, 30, 34])
                let position = builder.direction(degrees) * (giant - ForgeRules.preferredStem - r)
                builder.counter += 1
                let id = "r\(builder.counter)"
                builder.addRing(id, at: position, radius: r)
                guard builder.draft.addClip(from: "r0", at: builder.direction(degrees) * giant, to: id) else { return nil }
                builder.parent[id] = "r0"
                builder.childCount["r0", default: 0] += 1
            }
        } else if options.hubs <= 1 {
            builder.addRing("r0", at: .zero, radius: rng.pick([34.0, 40, 46, 54]))
        } else {
            // Several seeds, well apart, so each tree has room to start before they meet.
            var seeds: [Point] = []
            for _ in 0..<200 where seeds.count < options.hubs {
                let r = rng.pick([34.0, 38, 44])
                let reachX = Int(halfWidth - r - 10), reachY = Int(builder.halfHeight - r - 10)
                let position = Point(Double(rng.int(in: -reachX...reachX)), Double(rng.int(in: -reachY...reachY)))
                guard seeds.allSatisfy({ $0.distance(to: position) >= 150 }) else { continue }
                builder.addRing(seeds.isEmpty ? "r0" : "h\(seeds.count)", at: position, radius: r)
                seeds.append(position)
            }
            // Every seed becomes a hub first: three rings round it before the trees start to grow.
            let hubIDs = builder.draft.pieces.map(\.id)
            for _ in 0..<3 {
                for hub in hubIDs {
                    for _ in 0..<4 where !builder.grow(options: options, on: hub) {}
                }
            }
        }

        let target = rng.int(in: options.rings)
        var stalls = 0
        while builder.draft.pieces.filter({ $0.radius != nil }).count < target - options.latchBars && stalls < 60 {
            if builder.grow(options: options) { stalls = 0 } else { stalls += 1 }
        }
        for _ in 0..<options.latchBars where !builder.addLatchBar() { break }
        // On a hard tangle a blocked bar is tried first, a free one only where none fits.
        for _ in 0..<options.pokeBars where !(options.blockedPokes && builder.addPokeBar(blocked: true)) && !builder.addPokeBar() { break }

        let rings = builder.draft.pieces.filter { $0.radius != nil }.count
        guard rings >= options.rings.lowerBound else {
            LevelTemplate.debug?("\(options.template): only \(rings) rings fitted, \(builder.bodies.count) bodies, owners \(builder.childCount)")
            return nil
        }
        // A seed nothing grew from would leave the board on load; take it out again.
        let barren = builder.draft.pieces.filter { $0.radius != nil && !builder.isGripped($0.id) && builder.childCount[$0.id] == nil }.map(\.id)
        builder.draft.pieces.removeAll { barren.contains($0.id) }
        // Closed hubs: a root with several clips reads better as a full ring.
        if !options.planet {
            for piece in builder.draft.pieces where piece.radius != nil && !builder.isGripped(piece.id) && builder.childCount[piece.id] ?? 0 >= 3 {
                if options.hubs > 1 || rng.chance(0.6), let index = builder.draft.index(of: piece.id) {
                    builder.draft.pieces[index].closeRing()
                }
            }
        }
        guard builder.planGaps(options: options) else { return nil }

        // Free angles: make sure the intended order of moves actually goes through.
        // Validation works in board coordinates; the tangle is built around the origin.
        let board: Board
        do {
            let motif = Motif(name: options.name, template: options.template, pieces: builder.draft.pieces)
            board = try LevelDraft(name: options.name, template: options.template, pieces: motif.placed(at: ForgeRules.center)).validate()
        } catch {
            LevelTemplate.debug?("\(options.template): invalid: \(error)")
            return nil
        }
        let stuck = LevelSolver(board: board).greedyPlayout()
        guard stuck.isEmpty || keepStuck else {
            LevelTemplate.debug?("\(options.template): cannot play through, stuck with \(stuck.joined(separator: ", "))")
            return nil
        }
        return Motif(name: options.name, template: options.template, pieces: builder.draft.pieces)
    }
}
