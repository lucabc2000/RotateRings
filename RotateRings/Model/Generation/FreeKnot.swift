//
//  FreeKnot.swift
//  RotateRings
//
//  Knots without a grid (LEVEL-DESIGN.md §13). Rings of mixed sizes grow out from a seed, each
//  placed a stem's length from one ring, or from two at once, so that it can be held by both. Then
//  they are wired like `Knot`: clips run downhill in one ranking, so most rings hold and are held,
//  and no ring waits for itself.
//
//  Distances and sizes are free; directions are not quite. A ring's gap has to be turned onto each
//  clip that grips it in whole grid steps, so every contact on a ring must be a multiple of 45° from
//  the others. Every placement therefore runs along one of eight directions, turned by a random
//  angle per board, which keeps all contacts on one lattice while the board itself looks placed by
//  hand.
//
//  Variants, all through `Options`:
//  - gate tails: tails long enough to reach into a neighbour's circle, so they only swing past
//    while that neighbour's gap faces them (open the gate, swing through);
//  - a giant closed ring the knot grows inside and around, with bars inside;
//  - a larger board with more, smaller rings (a zoomed-out level).
//
//  Whether a board plays through is left to the solver, as with `Knot`.
//

import Foundation

enum FreeKnot {
    struct Options {
        var rings: ClosedRange<Int> = 16...20
        /// Ring radii to draw from. Rings that will hold and be held need 30 or more to turn one
        /// step with their clips (`Tangle.oneStepRadius`), but here rings turn as far as they like,
        /// so smaller ones are fine.
        var radii: [Double] = [22, 24, 26, 28, 30, 34, 38]
        /// Share of new rings placed against two rings at once, which gives rings with two holders.
        var closeChance = 0.85
        var maxHolders = 2
        var maxClips = 2
        var maxLinks = 3
        var linkChance = 0.9
        /// How strongly the ranking follows the distance from a starting ring (see `Knot.Options`).
        var chain = 0.75
        /// Chance that a ring nothing grips is closed.
        var anchorChance = 0.25
        var tailShare = 0.0
        /// Tails that reach into a neighbour's circle (gates) instead of short stubs.
        var gateTails = false
        /// Sliding bars poking into rings' gaps from open space.
        var pokes = 0
        var bombs = 0
        /// Radius of a giant closed ring at the centre that the knot grows inside and around.
        var giant: Double? = nil
        var board = BoardSize.standard
        var name = "Free knot"
        var template = "free"
    }

    /// Stems between linked rings. At least `Tangle.clearance`, so rings never touch.
    static let stems = 18.0...22.0
    static let clearance = Tangle.clearance
    /// Between rings that are not linked: a ring's own clip (stem plus square) or tail swings
    /// round it when it turns, and must pass a neighbour it is not linked to.
    static let farClearance = 34.0
    static let stubLength = 14.0
    /// A gate tail crosses the arc of a neighbour one short stem away by about 10 units.
    static let gateLength = 30.0
    /// The solver keeps every connection in one 64-bit word.
    static let maxConnections = 60

    private struct Ring {
        var id: String
        var center: Point
        var radius: Double
        var isGiant = false
    }

    private struct Link: Hashable {
        var a: String
        var b: String
    }

    static func build(_ options: Options, rng: inout SplitMix64) -> Motif? {
        let phase = Double(rng.int(in: 0...8)) * 5
        func direction(_ k: Int) -> Point {
            let radians = AngleMath.radians(fromDegrees: phase + Double(k) * ForgeRules.gridDegrees)
            return Point(cos(radians), sin(radians))
        }
        func lattice(_ k: Int) -> Double { normalizedDegrees(phase + Double(k) * ForgeRules.gridDegrees) }
        let extent = options.board.halfExtent
        let pad = GameRules.strokeThickness / 2 + (options.tailShare > 0 ? (options.gateTails ? gateLength : stubLength) : 0) * 0.5

        var rings: [Ring] = []
        var links = Set<Link>()
        var linkCount: [String: Int] = [:]
        /// Lattice directions each ring has links in. A ring must keep three neighbouring
        /// directions free, or no gap fits beside its clips.
        var linkDirections: [String: Set<Int>] = [:]
        var counter = 0

        func fits(_ center: Point, _ radius: Double) -> Bool {
            abs(center.x) + radius + pad <= extent.x && abs(center.y) + radius + pad <= extent.y
        }
        /// Clear of the rings it links to by `clearance` and of every other ring by `farClearance`;
        /// rings inside the giant count as clear of it when they keep that distance on the inside.
        func hasRoom(_ center: Point, _ radius: Double, linked: Set<String>) -> Bool {
            guard fits(center, radius) else { return false }
            return rings.allSatisfy { other in
                let d = center.distance(to: other.center)
                let gap: Double
                if d >= radius + other.radius { gap = d - radius - other.radius } else {
                    let inner = min(radius, other.radius), outer = max(radius, other.radius)
                    gap = d + inner <= outer ? outer - d - inner : 0
                }
                return gap >= (linked.contains(other.id) ? clearance : farClearance)
            }
        }
        func addRing(_ center: Point, _ radius: Double) -> String {
            counter += 1
            let id = "f\(counter)"
            rings.append(Ring(id: id, center: center, radius: radius))
            return id
        }
        func ring(_ id: String) -> Ring { rings.first { $0.id == id }! }
        /// Lattice index of the direction from `a` towards where its link to `b` attaches.
        func latticeIndex(from a: Ring, to b: Ring) -> Int {
            var vector = b.center - a.center
            // A ring inside the giant meets it on the far side of itself, facing outwards.
            if b.isGiant { vector = a.center - b.center }
            if a.isGiant && a.center.distance(to: b.center) + b.radius < a.radius { vector = b.center - a.center }
            let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: vector.angle) - phase)
            return Int((degrees / ForgeRules.gridDegrees).rounded()) % 8
        }
        func keepsGapRoom(_ id: String, adding k: Int) -> Bool {
            guard id != "g" else { return true }
            let taken = (linkDirections[id] ?? []).union([k])
            return (0..<8).contains { j in !taken.contains(j) && !taken.contains((j + 1) % 8) && !taken.contains((j + 7) % 8) }
        }
        func canLink(_ a: Ring, _ b: Ring) -> Bool {
            keepsGapRoom(a.id, adding: latticeIndex(from: a, to: b)) && keepsGapRoom(b.id, adding: latticeIndex(from: b, to: a))
        }
        func link(_ a: String, _ b: String) {
            guard links.insert(Link(a: min(a, b), b: max(a, b))).inserted else { return }
            linkCount[a, default: 0] += 1
            linkCount[b, default: 0] += 1
            let ra = ring(a), rb = ring(b)
            linkDirections[a, default: []].insert(latticeIndex(from: ra, to: rb))
            linkDirections[b, default: []].insert(latticeIndex(from: rb, to: ra))
        }

        // Seed.
        if let giant = options.giant {
            rings.append(Ring(id: "g", center: .zero, radius: giant, isGiant: true))
        } else {
            _ = addRing(.zero, rng.pick(options.radii.filter { $0 >= 30 }))
        }

        /// One new ring a stem from `owner`, along a lattice direction. Inside the giant when
        /// `inside`, otherwise outside whatever it hangs on.
        /// Of several spots that fit, one of the most central, so the knot grows compact and fills
        /// its holes instead of trailing off.
        func compact<T>(_ spots: [(center: Point, value: T)]) -> T? {
            guard !spots.isEmpty else { return nil }
            let ranked = spots.sorted { $0.center.length < $1.center.length }
            return ranked[rng.int(in: 0...min(2, ranked.count - 1))].value
        }

        func placeSingle() -> Bool {
            let anchors = rings.filter { (linkCount[$0.id] ?? 0) < ($0.isGiant ? 8 : options.maxLinks) }
            guard !anchors.isEmpty else { return false }
            var spots: [(center: Point, value: (anchor: Ring, center: Point, radius: Double))] = []
            for _ in 0..<80 where spots.count < 10 {
                let anchor = rng.pick(anchors)
                let k = rng.int(in: 0...7)
                let r = rng.pick(options.radii)
                let stem = Double(rng.int(in: Int(stems.lowerBound)...Int(stems.upperBound)))
                let inside = anchor.isGiant && rng.chance(0.6)
                let distance = inside ? anchor.radius - stem - r : anchor.radius + stem + r
                guard distance > 0 else { continue }
                let center = anchor.center + direction(k) * distance
                guard hasRoom(center, r, linked: [anchor.id]), canLink(anchor, Ring(id: "new", center: center, radius: r)) else { continue }
                spots.append((center, (anchor, center, r)))
            }
            guard let pick = compact(spots) else { return false }
            let id = addRing(pick.center, pick.radius)
            link(pick.anchor.id, id)
            return true
        }

        /// One new ring a stem from each of two rings at once: solves for the two stems along a pair
        /// of lattice directions. Rings with two holders come from here.
        func placeBetween() -> Bool {
            let open = rings.filter { !$0.isGiant && (linkCount[$0.id] ?? 0) < options.maxLinks }
            guard open.count >= 2 else { return false }
            var found: [(center: Point, radius: Double, a: String, b: String)] = []
            for _ in 0..<200 where found.count < 8 {
                let a = rng.pick(open), b = rng.pick(open)
                guard a.id != b.id, a.center.distance(to: b.center) < a.radius + b.radius + 2 * (stems.upperBound + 46) else { continue }
                // Held by two: big enough for a holder's clip to swing out of a gap that fits.
                let r = rng.pick(options.radii.filter { $0 >= 30 } + [30])
                let ka = rng.int(in: 0...7), kb = rng.int(in: 0...7)
                let da = direction(ka), db = direction(kb)
                let det = -da.x * db.y + db.x * da.y
                guard abs(det) > 0.2 else { continue }
                // a + da (ra + r + sa) = b + db (rb + r + sb)
                let v = (b.center - a.center) + db * (b.radius + r) - da * (a.radius + r)
                let sa = (-v.x * db.y + db.x * v.y) / det
                let sb = (da.x * v.y - da.y * v.x) / det
                guard stems.contains(sa), stems.contains(sb) else { continue }
                let center = a.center + da * (a.radius + r + sa)
                let new = Ring(id: "new", center: center, radius: r)
                guard hasRoom(center, r, linked: [a.id, b.id]), canLink(a, new), canLink(b, new) else { continue }
                // The new ring's own two links must leave it room for a gap too.
                let ka2 = latticeIndex(from: new, to: a), kb2 = latticeIndex(from: new, to: b)
                guard (0..<8).contains(where: { j in ![ka2, kb2].contains(j) && ![ka2, kb2].contains((j + 1) % 8) && ![ka2, kb2].contains((j + 7) % 8) }) else { continue }
                found.append((center, r, a.id, b.id))
            }
            guard let pick = compact(found.map { ($0.center, $0) }) else { return false }
            let id = addRing(pick.center, pick.radius)
            link(pick.a, id)
            link(pick.b, id)
            return true
        }

        let target = rng.int(in: options.rings)
        var stalls = 0
        while rings.filter({ !$0.isGiant }).count < target && stalls < 150 {
            let placed = rings.count >= 3 && rng.chance(options.closeChance) ? (placeBetween() || placeSingle()) : placeSingle()
            stalls = placed ? 0 : stalls + 1
        }
        guard rings.filter({ !$0.isGiant }).count >= options.rings.lowerBound else {
            LevelTemplate.debug?("\(options.template): only \(rings.count) rings fitted")
            return nil
        }
        // Neighbours that happen to sit a stem apart along a lattice direction can link too.
        for (i, a) in rings.enumerated() where !a.isGiant {
            for b in rings[(i + 1)...] where !b.isGiant {
                let d = a.center.distance(to: b.center) - a.radius - b.radius
                guard stems.contains(d) else { continue }
                let angle = normalizedDegrees(AngleMath.degrees(fromRadians: (b.center - a.center).angle))
                guard (0..<8).contains(where: { degreeDifference(lattice($0), angle) < 0.5 }), canLink(a, b) else { continue }
                link(a.id, b.id)
            }
        }

        // One ranking: clips run from the higher ring to the lower. The giant is above everything
        // (a closed ring can only hold).
        let ringIDs = rings.map(\.id)
        var neighbours: [String: [String]] = [:]
        for l in links { neighbours[l.a, default: []].append(l.b); neighbours[l.b, default: []].append(l.a) }
        let origin = rng.pick(rings.filter { !$0.isGiant }).id
        var hops: [String: Int] = [origin: 0]
        var queue = [origin]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            for next in neighbours[current] ?? [] where hops[next] == nil && next != "g" {
                hops[next] = hops[current]! + 1
                queue.append(next)
            }
        }
        let farthest = Double(max(1, hops.values.max() ?? 1))
        var score: [String: Double] = [:]
        for id in ringIDs {
            if id == "g" { score[id] = 10; continue }
            let distance = Double(hops[id] ?? Int(farthest)) / farthest
            score[id] = options.chain * distance + (1 - options.chain) * Double(rng.int(in: 0...1000)) / 1000
        }

        var holders: [String: [String]] = [:]
        var targets: [String: [String]] = [:]
        var used: [String: Int] = [:]
        func join(_ l: Link, force: Bool = false) -> Bool {
            let (owner, target) = score[l.a]! > score[l.b]! ? (l.a, l.b) : (l.b, l.a)
            let ownerLimit = owner == "g" ? 8 : options.maxClips
            guard (used[owner] ?? 0) < (owner == "g" ? 8 : options.maxLinks), (used[target] ?? 0) < options.maxLinks,
                  (targets[owner]?.count ?? 0) < ownerLimit, (holders[target]?.count ?? 0) < options.maxHolders else { return false }
            // A small ring cannot take a second holder: no gap on it lets the first one's clip
            // swing out once it stays behind.
            guard ring(target).radius >= Tangle.oneStepRadius || holders[target] == nil else { return false }
            guard force || rng.chance(options.linkChance) else { return false }
            targets[owner, default: []].append(target)
            holders[target, default: []].append(owner)
            used[owner, default: 0] += 1
            used[target, default: 0] += 1
            return true
        }
        let shuffled = links.sorted { ($0.a, $0.b) < ($1.a, $1.b) }.shuffled(using: &rng)
        var skipped: [Link] = []
        for l in shuffled where !join(l) { skipped.append(l) }
        for l in skipped where (used[l.a] ?? 0) == 0 || (used[l.b] ?? 0) == 0 { _ = join(l, force: true) }
        let kept = rings.filter { (used[$0.id] ?? 0) > 0 }
        guard kept.count >= 4 else { return nil }

        var draft = LevelDraft(name: options.name, template: options.template, board: options.board)
        var closed = Set<String>()
        for r in kept {
            if r.isGiant || (holders[r.id] == nil && rng.chance(options.anchorChance)) {
                closed.insert(r.id)
                draft.pieces.append(.closedRing(r.id, at: r.center, radius: r.radius))
            } else {
                draft.pieces.append(.ring(r.id, at: r.center, radius: r.radius))
            }
        }
        for r in kept {
            for t in targets[r.id] ?? [] {
                guard draft.addRingClip(from: r.id, to: t) else {
                    LevelTemplate.debug?("\(options.template): clip \(r.id)→\(t) does not fit")
                    return nil
                }
            }
        }

        func standing(_ pieces: [DraftPiece]) -> Error? {
            let motif = Motif(name: options.name, template: options.template, pieces: pieces)
            do {
                _ = try LevelDraft(name: options.name, template: options.template, pieces: motif.placed(at: options.board.center, board: options.board), board: options.board).validate()
                return nil
            } catch {
                return error
            }
        }
        func stands(_ pieces: [DraftPiece]) -> Bool { standing(pieces) == nil }
        func linkAngle(_ from: String, _ to: String) -> Double {
            let a = ring(from), b = ring(to)
            // Seen from a ring inside the giant, the giant's clip comes from outward.
            if b.isGiant { return normalizedDegrees(AngleMath.degrees(fromRadians: (a.center - b.center).angle) + (a.center.distance(to: b.center) < b.radius ? 0 : 180)) }
            return normalizedDegrees(AngleMath.degrees(fromRadians: (b.center - a.center).angle))
        }

        /// A held ring's gap must let each holder's clip swing out once the gap sits on it. A holder
        /// needs one way out, not both, so for each holder the easier turn decides (unlike
        /// `LevelDraft.sharedGapRequirement`, which covers both and rarely fits on a crowded ring).
        func gapWidth(_ id: String) -> Double {
            // A ring held once and holding nothing leaves the moment that holder lets go, so there
            // is nothing for the clip to swing out of.
            let staysBehind = (holders[id]?.count ?? 0) >= 2 || !(targets[id] ?? []).isEmpty
            guard holders[id] != nil, staysBehind, let ring = draft[id], let radius = ring.radius else { return ForgeRules.defaultGapDegrees }
            let band = GameRules.strokeThickness + GameRules.clipSize / 2
            var halfGap = ForgeRules.defaultGapDegrees / 2
            // A holder nothing holds leaves as soon as its clips let go; its clip never swings out.
            for owner in draft.pieces where holders[owner.id] != nil {
                for clip in owner.clips where clip.grips == id {
                    let contact = normalizedDegrees(AngleMath.degrees(fromRadians: (owner.toWorld(clip.stemEnd) - ring.position).angle))
                    var easiest = Double.infinity
                    for turn in [1.0, -1.0] {
                        var needed = 0.0
                        for step in 1...Int(ForgeRules.gridDegrees) {
                            let angle = AngleMath.radians(fromDegrees: owner.rotationDegrees + turn * Double(step))
                            let relative = clip.stemEnd.rotated(by: angle) + owner.position - ring.position
                            guard abs(relative.length - radius) < band else { continue }
                            let clearance = AngleMath.degrees(fromRadians: asin(min(1, (GameRules.clipSize / 2 + GameRules.strokeThickness) / max(relative.length, 1))))
                            needed = max(needed, degreeDifference(AngleMath.degrees(fromRadians: relative.angle), contact) + clearance + 2)
                        }
                        easiest = min(easiest, needed)
                    }
                    halfGap = max(halfGap, easiest)
                }
            }
            return min(150, (2 * halfGap / 5).rounded(.up) * 5)
        }

        // Bars poking into gaps from open space, planned before the other gaps: the poked ring's gap
        // faces the bar, so the ring cannot turn until the bar has slid out.
        var fixedGaps = Set<String>()
        var bars: [DraftPiece] = []
        func barRoom(_ from: Point, _ to: Point, except: String) -> Bool {
            let segment = Segment(from: from, to: to)
            let ends = [from, to]
            guard ends.allSatisfy({ abs($0.x) + 6 <= extent.x && abs($0.y) + 6 <= extent.y }) else { return false }
            for other in kept where other.id != except {
                let near = Geometry.samplePoints(on: segment, spacing: GameRules.distanceSampleSpacing)
                    .map { abs($0.distance(to: other.center) - other.radius) }.min() ?? .infinity
                if near < 14 { return false }
            }
            return bars.allSatisfy { bar in
                guard case .segment(let s) = bar.shapes[0] else { return true }
                return Geometry.distance(segment, Segment(from: bar.toWorld(s.from), to: bar.toWorld(s.to))) >= 14
            }
        }
        for _ in 0..<options.pokes {
            var done = false
            for r in kept.shuffled(using: &rng) where !done && !closed.contains(r.id) && !fixedGaps.contains(r.id) {
                let taken = ((holders[r.id] ?? []) + (targets[r.id] ?? [])).map { linkAngle(r.id, $0) }
                for k in (0..<8).shuffled(using: &rng) {
                    let degrees = lattice(k)
                    guard taken.allSatisfy({ degreeDifference($0, degrees) >= 90 }),
                          draft.gapIsValid(centerDegrees: degrees, gapDegrees: gapWidth(r.id), for: r.id) else { continue }
                    let dir = direction(k)
                    let start = r.radius - 10
                    let length = Double(rng.int(in: 50...80))
                    let inner = r.center + dir * start
                    let exitEnd = r.center + dir * (start + length + GameRules.holderLength / 2 + 1 + GridWorld.hubInset + 8)
                    // Inside the giant the bar points inward, away from the giant's arc, or not at all.
                    guard barRoom(r.center + dir * (r.radius + 8), exitEnd, except: r.id),
                          let index = draft.index(of: r.id) else { continue }
                    draft.pieces[index].setGap(centerDegrees: degrees, degrees: gapWidth(r.id))
                    fixedGaps.insert(r.id)
                    bars.append(.slideBar("p\(bars.count)", at: inner + dir * GridWorld.hubInset, from: -GridWorld.hubInset,
                                          to: length - GridWorld.hubInset, angleDegrees: degrees))
                    done = true
                    break
                }
            }
        }

        // Gaps on the lattice. A held ring's gap lets each holder's loose clip swing out but never
        // spans two clips: holders are let go one at a time.
        for r in kept where !closed.contains(r.id) && !fixedGaps.contains(r.id) {
            guard let index = draft.index(of: r.id) else { return nil }
            // No fallback to the plain gap: one too narrow for a holder's clip to swing out of
            // jams the board (the clip catches on the gap's edge a few degrees into the turn).
            let widths = [gapWidth(r.id)]
            var placed = false
            for width in widths where !placed {
                let choices = (0..<8).map(lattice).filter { draft.gapIsValid(centerDegrees: $0, gapDegrees: width, for: r.id) }
                guard !choices.isEmpty else { continue }
                draft.pieces[index].setGap(centerDegrees: rng.pick(choices), degrees: width)
                placed = true
            }
            guard placed else {
                let contacts = draft.contactAngles(on: r.id).map { Int($0) }, roots = draft.stemRootAngles(of: r.id).map { Int($0) }
                LevelTemplate.debug?("\(options.template): no gap for \(r.id) r\(Int(r.radius)) width \(Int(widths[0])) phase \(Int(phase)) contacts \(contacts) roots \(roots)")
                return nil
            }
        }
        draft.pieces += bars
        if let error = standing(draft.pieces) {
            LevelTemplate.debug?("\(options.template): does not stand: \(error)")
            return nil
        }

        // Bombs on rings that can turn from the start (no clip of their own, not poked).
        if options.bombs > 0 {
            var placed = 0
            let free = kept.filter { !closed.contains($0.id) && (targets[$0.id] ?? []).isEmpty && !fixedGaps.contains($0.id) }
            for r in free.shuffled(using: &rng) where placed < options.bombs {
                guard let index = draft.index(of: r.id) else { continue }
                let piece = draft.pieces[index]
                let gapHalf = (piece.gapDegrees ?? 0) / 2
                let busy = draft.contactAngles(on: r.id) + draft.stemRootAngles(of: r.id)
                let choices = (0..<8).map(lattice).filter { angle in
                    (piece.gapCenterDegrees.map { degreeDifference($0, angle) > gapHalf + 30 } ?? true) && busy.allSatisfy { degreeDifference($0, angle) >= 40 }
                }
                guard !choices.isEmpty else { continue }
                let angle = AngleMath.radians(fromDegrees: rng.pick(choices))
                draft.pieces[index].bomb = Point(cos(angle), sin(angle)) * r.radius
                if stands(draft.pieces) { placed += 1 } else { draft.pieces[index].bomb = nil }
            }
            guard placed > 0 else {
                LevelTemplate.debug?("\(options.template): no ring for a bomb")
                return nil
            }
        }

        // Tails on the lattice, clear of the gap and of every link. Stubs only get in the way of
        // clips; gate tails reach into the neighbour they point past.
        if options.tailShare > 0 {
            let length = options.gateTails ? gateLength : stubLength
            for r in kept.shuffled(using: &rng) where !closed.contains(r.id) && rng.chance(options.tailShare) {
                guard let index = draft.index(of: r.id), let gap = draft.pieces[index].gapCenterDegrees else { continue }
                let taken = ((holders[r.id] ?? []) + (targets[r.id] ?? [])).map { linkAngle(r.id, $0) }
                let choices = (0..<8).map(lattice).filter { angle in
                    degreeDifference(angle, gap) >= 90 && taken.allSatisfy { degreeDifference($0, angle) >= 60 }
                        && draft.pieces[index].bomb.map { degreeDifference(AngleMath.degrees(fromRadians: $0.angle), angle) >= 45 } ?? true
                }
                guard !choices.isEmpty else { continue }
                let before = draft.pieces[index]
                draft.pieces[index].addTail(atDegrees: rng.pick(choices), length: length)
                if !stands(draft.pieces) { draft.pieces[index] = before }
            }
        }

        let connections = draft.pieces.reduce(0) { $0 + $1.clips.count + ($1.motion == .slide ? 1 : 0) }
        guard connections <= maxConnections else {
            LevelTemplate.debug?("\(options.template): \(connections) connections, too many for the solver")
            return nil
        }
        let motif = Motif(name: options.name, template: options.template, pieces: draft.pieces)
        guard motif.width <= options.board.width - 2 * ForgeRules.margin, motif.height <= options.board.height - 2 * ForgeRules.margin,
              stands(draft.pieces) else {
            LevelTemplate.debug?("\(options.template): does not fit or stand")
            return nil
        }
        return motif
    }
}
