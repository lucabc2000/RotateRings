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
//  - a larger board with more, smaller rings (a zoomed-out level);
//  - mirrored left to right: every ring is placed with its mirror image and every link with its
//    image, on a lattice turned by 0° or 22.5° so that mirrored directions stay on it;
//  - inside a silhouette (`Silhouette`): rings only where they fit inside the outline, each new one
//    where the outline is emptiest, so the knot fills the shape;
//  - around one or two large anchor rings placed first, as a focal point;
//  - on a picture (`Picture`): its rings instead of grown ones, snapped onto the lattice.
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
        /// Mirror the knot left to right (see the file comment). Rings on the axis only where the
        /// lattice has a vertical direction, so their gap, tail, bomb or bar can point straight up or
        /// down. A link between a ring and its own image has its clip on the axis, owned by one.
        var mirror = false
        var mirrorColors = true
        /// Grow only inside this outline, filling it evenly.
        var silhouette: Silhouette? = nil
        /// Large rings placed first, which the knot grows around: a focal point (one or two).
        var anchors = 0
        var anchorRadii: [Double] = [46, 52, 58]
        /// Rings (and bars) as drawn in a picture, instead of grown ones.
        var picture: Picture? = nil
        /// Locks added to a picture: rings with two or three neighbours made closed, so they hold
        /// them all and leave only once every one of them has its gap on its clip.
        var pictureLocks = 0
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
        let mirror = options.mirror
        // A mirror about the vertical maps the lattice onto itself only when it is turned by a
        // multiple of 22.5°, and only unturned does it have the vertical that rings on the axis need
        // to tie the two halves together (turned by 22.5°, every board fell apart in two).
        // A picture is drawn on the unturned lattice.
        let phase = mirror || options.picture != nil ? 0 : Double(rng.int(in: 0...8)) * 5
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
        /// A picture's rings that are always closed: they only hold, above everything they touch.
        var pictureClosed = Set<String>()
        /// With `mirror`: each ring's mirror image (itself on the axis; the giant is its own).
        var twinOf: [String: String] = ["g": "g"]
        func twin(_ id: String) -> String { twinOf[id] ?? id }
        /// The lattice direction of the mirror image of direction `k`.
        func twin(direction k: Int) -> Int { (Int(((180 - 2 * phase) / ForgeRules.gridDegrees).rounded()) - k + 16) % 8 }
        /// Lattice directions a ring on the axis may keep its gap in: straight up or down.
        let upright = mirror && phase == 0 ? [2, 6] : []

        func fits(_ center: Point, _ radius: Double) -> Bool {
            guard abs(center.x) + radius + pad <= extent.x && abs(center.y) + radius + pad <= extent.y else { return false }
            guard let silhouette = options.silhouette else { return true }
            // The whole ring inside the outline, not only its centre.
            let reach = radius + GameRules.strokeThickness / 2 + 2
            return silhouette.contains(center, unit: extent.x) && (0..<16).allSatisfy { i in
                let a = Double(i) * .pi / 8
                return silhouette.contains(center + Point(cos(a), sin(a)) * reach, unit: extent.x)
            }
        }
        /// Where a first ring may go: a grid over the board (through the centre, so the axis is on
        /// it), inside the outline if there is one.
        func seedPoints() -> [Point] {
            let xs = stride(from: 0.0, through: extent.x, by: 8).flatMap { $0 == 0 ? [$0] : [-$0, $0] }
            let ys = stride(from: 0.0, through: extent.y, by: 8).flatMap { $0 == 0 ? [$0] : [-$0, $0] }
            return xs.flatMap { x in ys.map { Point(x, $0) } }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                .filter { options.silhouette?.contains($0, unit: extent.x) ?? true }
        }
        /// How crowded the board is around a spot: the outline is filled where it is emptiest.
        func crowding(_ center: Point) -> Int {
            rings.filter { !$0.isGiant && $0.center.distance(to: center) < 110 }.count
        }
        let shaped = options.silhouette != nil || options.anchors > 0
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
            guard id != "g" && !pictureClosed.contains(id) else { return true }
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

        /// Mirror: links these pairs and their images, or none of them when a ring would run out of
        /// links or of room for its gap (on the axis: room straight up or down).
        func linkMirrored(_ pairs: [(String, String)]) -> Bool {
            var unique: [Link] = []
            for (a, b) in pairs + pairs.map({ (twin($0.0), twin($0.1)) }) where a != b {
                let l = Link(a: min(a, b), b: max(a, b))
                if !links.contains(l) && !unique.contains(l) { unique.append(l) }
            }
            var added: [String: Set<Int>] = [:]
            var count: [String: Int] = [:]
            for l in unique {
                let ra = ring(l.a), rb = ring(l.b)
                added[l.a, default: []].insert(latticeIndex(from: ra, to: rb))
                added[l.b, default: []].insert(latticeIndex(from: rb, to: ra))
                count[l.a, default: 0] += 1
                count[l.b, default: 0] += 1
            }
            for (id, extra) in count where id != "g" {
                guard (linkCount[id] ?? 0) + extra <= options.maxLinks else { return false }
                let taken = (linkDirections[id] ?? []).union(added[id] ?? [])
                let room = (0..<8).filter { j in !taken.contains(j) && !taken.contains((j + 1) % 8) && !taken.contains((j + 7) % 8) }
                guard twin(id) == id ? room.contains(where: upright.contains) : !room.isEmpty else { return false }
            }
            for l in unique { link(l.a, l.b) }
            return true
        }
        /// Mirror: a ring and its image (one ring on the axis), linked to `partners` and their
        /// images, or nothing.
        func addMirrored(_ center: Point, _ radius: Double, linkedTo partners: [String]) -> Bool {
            let onAxis = abs(center.x) < 0.01
            guard !onAxis || !upright.isEmpty else { return false }
            let center = onAxis ? Point(0, center.y) : center
            // Clear of its own image too.
            guard onAxis || 2 * abs(center.x) - 2 * radius >= farClearance else { return false }
            let id = addRing(center, radius)
            var added = [id]
            if onAxis {
                twinOf[id] = id
            } else {
                let image = addRing(Point(-center.x, center.y), radius)
                twinOf[id] = image
                twinOf[image] = id
                added.append(image)
            }
            if linkMirrored(partners.map { ($0, id) }) { return true }
            rings.removeAll { added.contains($0.id) }
            counter -= added.count
            for ring in added { twinOf[ring] = nil }
            return false
        }

        // Seed (a mirrored knot seeds itself further down).
        if let giant = options.giant {
            rings.append(Ring(id: "g", center: .zero, radius: giant, isGiant: true))
        } else if let picture = options.picture {
            // The picture's rings, each one that nearly touches a ring placed before it moved to a
            // stem's length from it along the nearest lattice direction, so the two can be clipped.
            var centers = picture.rings.map { Point($0.x, $0.y) }
            var snapped = [Bool](repeating: false, count: centers.count)
            for root in centers.indices where !snapped[root] {
                snapped[root] = true
                var stack = [root]
                while let i = stack.popLast() {
                    for j in centers.indices where !snapped[j] {
                        let vector = centers[j] - centers[i]
                        let gap = vector.length - picture.rings[i].r - picture.rings[j].r
                        let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: vector.angle))
                        let k = Int((degrees / ForgeRules.gridDegrees).rounded()) % 8
                        guard (8.0...34.0).contains(gap), degreeDifference(degrees, lattice(k)) <= 10 else { continue }
                        // The stem as drawn, within what a clip spans.
                        let stem = min(max(gap, stems.lowerBound), stems.upperBound)
                        centers[j] = centers[i] + direction(k) * (picture.rings[i].r + picture.rings[j].r + stem)
                        snapped[j] = true
                        stack.append(j)
                    }
                }
            }
            // A ring whose neighbours leave no three free directions in a row has no room for a gap:
            // it is closed.
            func touching(_ i: Int) -> Set<Int> {
                Set(centers.indices.compactMap { j -> Int? in
                    let vector = centers[j] - centers[i]
                    let degrees = normalizedDegrees(AngleMath.degrees(fromRadians: vector.angle))
                    guard j != i, stems.contains(vector.length - picture.rings[i].r - picture.rings[j].r) else { return nil }
                    return (0..<8).first { degreeDifference(lattice($0), degrees) < 0.5 }
                })
            }
            func hasGapRoom(_ taken: Set<Int>) -> Bool {
                (0..<8).contains { j in !taken.contains(j) && !taken.contains((j + 1) % 8) && !taken.contains((j + 7) % 8) }
            }
            for (index, spec) in picture.rings.enumerated() {
                guard fits(centers[index], spec.r) else {
                    LevelTemplate.debug?("\(options.template): ring \(index) does not fit the board")
                    return nil
                }
                let id = addRing(centers[index], spec.r)
                if spec.closed == true || touching(index).count > options.maxLinks || !hasGapRoom(touching(index)) { pictureClosed.insert(id) }
            }
        } else if !mirror && !shaped {
            _ = addRing(.zero, rng.pick(options.radii.filter { $0 >= 30 }))
        } else if !mirror {
            // Inside the outline; the first anchor near its middle, a second anywhere with room.
            let points = seedPoints()
            let middle = points.reduce(Point.zero) { $0 + $1 } * (1 / Double(max(1, points.count)))
            for index in 0..<max(1, options.anchors) {
                let radius = rng.pick(options.anchors > 0 ? options.anchorRadii : options.radii.filter { $0 >= 30 })
                var spots = points.filter { fits($0, radius) && hasRoom($0, radius, linked: []) }
                if index == 0 { spots = Array(spots.sorted { $0.distance(to: middle) < $1.distance(to: middle) }.prefix(12)) }
                guard !spots.isEmpty else {
                    LevelTemplate.debug?("\(options.template): no room for a first ring of \(Int(radius))")
                    return nil
                }
                _ = addRing(rng.pick(spots), radius)
            }
        }

        /// One new ring a stem from `owner`, along a lattice direction. Inside the giant when
        /// `inside`, otherwise outside whatever it hangs on.
        /// Of several spots that fit, one of the most central, so the knot grows compact and fills
        /// its holes instead of trailing off.
        func compact<T>(_ spots: [(center: Point, value: T)]) -> T? {
            guard !spots.isEmpty else { return nil }
            let ranked = options.silhouette == nil ? spots.sorted { $0.center.length < $1.center.length }
                : spots.sorted { (crowding($0.center), $0.center.length) < (crowding($1.center), $1.center.length) }
            return ranked[rng.int(in: 0...min(2, ranked.count - 1))].value
        }
        /// Mirror: the spots from one of the most central on, outwards, until one fits with its image.
        func compactMirrored<T>(_ spots: [(center: Point, value: T)], _ place: (T) -> Bool) -> Bool {
            guard !spots.isEmpty else { return false }
            let ranked = options.silhouette == nil ? spots.sorted { $0.center.length < $1.center.length }
                : spots.sorted { (crowding($0.center), $0.center.length) < (crowding($1.center), $1.center.length) }
            let first = rng.int(in: 0...min(2, ranked.count - 1))
            return ranked[first...].contains { place($0.value) }
        }

        func placeSingle() -> Bool {
            let anchors = rings.filter { (linkCount[$0.id] ?? 0) < ($0.isGiant ? 8 : options.maxLinks) }
            guard !anchors.isEmpty else { return false }
            var spots: [(center: Point, value: (anchor: Ring, center: Point, radius: Double))] = []
            for _ in 0..<(mirror ? 240 : 80) where spots.count < (mirror ? 24 : 10) {
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
            if mirror { return compactMirrored(spots) { addMirrored($0.center, $0.radius, linkedTo: [$0.anchor.id]) } }
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
            for _ in 0..<(mirror ? 500 : 200) where found.count < (mirror ? 16 : 8) {
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
            if mirror { return compactMirrored(found.map { ($0.center, $0) }) { addMirrored($0.center, $0.radius, linkedTo: [$0.a, $0.b]) } }
            guard let pick = compact(found.map { ($0.center, $0) }) else { return false }
            let id = addRing(pick.center, pick.radius)
            link(pick.a, id)
            link(pick.b, id)
            return true
        }

        let target = rng.int(in: options.rings)
        var stalls = 0
        if mirror {
            if options.giant == nil && !shaped {
                // On the axis where the lattice allows it, otherwise a pair a little apart.
                let radius = rng.pick(options.radii.filter { $0 >= 30 })
                if upright.isEmpty {
                    let first = addRing(Point(-(radius + farClearance / 2 + 1), 0), radius)
                    let second = addRing(Point(radius + farClearance / 2 + 1, 0), radius)
                    twinOf[first] = second
                    twinOf[second] = first
                } else {
                    let seed = addRing(.zero, radius)
                    twinOf[seed] = seed
                }
            } else if options.giant == nil {
                // One first ring on the axis (lattice and outline permitting), or a pair; two
                // anchors are always a pair.
                let radius = rng.pick(options.anchors > 0 ? options.anchorRadii : options.radii.filter { $0 >= 30 })
                let points = seedPoints()
                let axis = upright.isEmpty || options.anchors >= 2 ? [] : points.filter { $0.x == 0 && fits($0, radius) }
                if !axis.isEmpty {
                    let seed = addRing(rng.pick(axis), radius)
                    twinOf[seed] = seed
                } else {
                    let pairs = points.filter { $0.x <= -(radius + farClearance / 2) && fits($0, radius) }
                    guard !pairs.isEmpty else {
                        LevelTemplate.debug?("\(options.template): no room for a first pair of \(Int(radius))")
                        return nil
                    }
                    let spot = rng.pick(pairs)
                    let first = addRing(spot, radius)
                    let second = addRing(Point(-spot.x, spot.y), radius)
                    twinOf[first] = second
                    twinOf[second] = first
                }
            }
            while rings.filter({ !$0.isGiant }).count < target && stalls < 150 {
                let placed = rings.count >= 3 && rng.chance(options.closeChance) ? (placeBetween() || placeSingle()) : placeSingle()
                stalls = placed ? 0 : stalls + 1
            }
        } else if options.picture == nil {
            while rings.filter({ !$0.isGiant }).count < target && stalls < 150 {
                let placed = rings.count >= 3 && rng.chance(options.closeChance) ? (placeBetween() || placeSingle()) : placeSingle()
                stalls = placed ? 0 : stalls + 1
            }
        }
        guard options.picture != nil || rings.filter({ !$0.isGiant }).count >= options.rings.lowerBound else {
            LevelTemplate.debug?("\(options.template): only \(rings.count) rings fitted")
            return nil
        }
        // Neighbours that happen to sit a stem apart along a lattice direction can link too.
        for (i, a) in rings.enumerated() where !a.isGiant {
            for b in rings[(i + 1)...] where !b.isGiant {
                let d = a.center.distance(to: b.center) - a.radius - b.radius
                // A picture's snapped stems may come out a hair short of a whole number.
                let slack = options.picture == nil ? 0 : 0.01
                guard (stems.lowerBound - slack...stems.upperBound + slack).contains(d) else { continue }
                let angle = normalizedDegrees(AngleMath.degrees(fromRadians: (b.center - a.center).angle))
                guard (0..<8).contains(where: { degreeDifference(lattice($0), angle) < 0.5 }) else { continue }
                if mirror {
                    _ = linkMirrored([(a.id, b.id)])
                } else if canLink(a, b) {
                    link(a.id, b.id)
                }
            }
        }

        // A picture's locks: a ring with two or three neighbours, none of them closed, made closed.
        if options.pictureLocks > 0 {
            var neighbourIDs: [String: Set<String>] = [:]
            for l in links { neighbourIDs[l.a, default: []].insert(l.b); neighbourIDs[l.b, default: []].insert(l.a) }
            for _ in 0..<options.pictureLocks {
                let choices = rings.filter { r in
                    !pictureClosed.contains(r.id) && (2...3).contains(neighbourIDs[r.id]?.count ?? 0)
                        && !(neighbourIDs[r.id] ?? []).contains(where: pictureClosed.contains)
                }
                guard !choices.isEmpty else {
                    LevelTemplate.debug?("\(options.template): no ring can be a lock")
                    break
                }
                // Rather one whose neighbours have neighbours of their own: then a ring it grips is
                // also gripped elsewhere, and the lock asks for a moment of timing, not just patience.
                func reach(_ r: Ring) -> Int { (neighbourIDs[r.id] ?? []).reduce(0) { $0 + (neighbourIDs[$1]?.count ?? 1) - 1 } }
                let best = choices.map(reach).max()!
                pictureClosed.insert(rng.pick(choices.filter { reach($0) == best }).id)
            }
        }

        // One ranking: clips run from the higher ring to the lower. The giant is above everything
        // (a closed ring can only hold).
        let ringIDs = rings.map(\.id)
        var neighbours: [String: [String]] = [:]
        for l in links { neighbours[l.a, default: []].append(l.b); neighbours[l.b, default: []].append(l.a) }
        let onAxis = rings.filter { !$0.isGiant && mirror && twin($0.id) == $0.id }
        let origin = rng.pick(onAxis.isEmpty ? rings.filter { !$0.isGiant } : onAxis).id
        // Mirrored: hops from the origin or its image, so images rank alike.
        var hops: [String: Int] = [origin: 0]
        hops[twin(origin)] = 0
        var queue = Array(Set([origin, twin(origin)])).sorted()
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
            if id == "g" || pictureClosed.contains(id) { score[id] = 10; continue }
            // In a picture a ring with one neighbour is held by it, never the other way round: a
            // small neighbour could not take it as a second holder.
            if options.picture != nil, neighbours[id]?.count == 1 { score[id] = -1; continue }
            if mirror, let image = score[twin(id)], twin(id) != id { score[id] = image; continue }
            let distance = Double(hops[id] ?? Int(farthest)) / farthest
            score[id] = options.chain * distance + (1 - options.chain) * Double(rng.int(in: 0...1000)) / 1000
        }

        var holders: [String: [String]] = [:]
        var targets: [String: [String]] = [:]
        var used: [String: Int] = [:]
        func join(_ l: Link, force: Bool = false) -> Bool {
            let (owner, target) = score[l.a]! > score[l.b]! ? (l.a, l.b) : (l.b, l.a)
            let ownerLimit = owner == "g" || pictureClosed.contains(owner) ? 8 : options.maxClips
            let ownerLinks = owner == "g" || pictureClosed.contains(owner) ? 8 : options.maxLinks
            // Two closed rings never clip together: neither could ever let go.
            guard !pictureClosed.contains(target), (used[owner] ?? 0) < ownerLinks, (used[target] ?? 0) < options.maxLinks,
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
        if mirror {
            func image(_ l: Link) -> Link { Link(a: min(twin(l.a), twin(l.b)), b: max(twin(l.a), twin(l.b))) }
            /// A link and its image, or neither.
            func joinBoth(_ l: Link) -> Bool {
                guard join(l, force: true) else { return false }
                if image(l) == l || join(image(l), force: true) { return true }
                let (owner, target) = score[l.a]! > score[l.b]! ? (l.a, l.b) : (l.b, l.a)
                targets[owner]!.removeLast()
                holders[target]!.removeLast()
                used[owner]! -= 1
                used[target]! -= 1
                return false
            }
            var seen = Set<Link>()
            for l in shuffled where !seen.contains(l) {
                seen.formUnion([l, image(l)])
                if !rng.chance(options.linkChance) || !joinBoth(l) { skipped.append(l) }
            }
            for l in skipped where (used[l.a] ?? 0) == 0 || (used[l.b] ?? 0) == 0 { _ = joinBoth(l) }
        } else {
            for l in shuffled where !join(l) { skipped.append(l) }
            for l in skipped where (used[l.a] ?? 0) == 0 || (used[l.b] ?? 0) == 0 { _ = join(l, force: true) }
        }
        let kept = rings.filter { (used[$0.id] ?? 0) > 0 }
        guard kept.count >= 4 else { return nil }
        // A picture keeps every ring: one without a clip would leave on load and leave a hole.
        guard options.picture == nil || kept.count == rings.count else {
            let lost = rings.filter { (used[$0.id] ?? 0) == 0 }.map { r in "\(r.id) (\(links.filter { $0.a == r.id || $0.b == r.id }.count) links)" }
            LevelTemplate.debug?("\(options.template): \(lost.joined(separator: ", ")) of the picture got no clip")
            return nil
        }
        if mirror || options.anchors > 1 {
            // One knot, not two mirror images side by side (those play the same puzzle twice), nor
            // two knots around two anchors: every ring placed hangs together with every other.
            let placed = rings.filter { !$0.isGiant }.map(\.id)
            var reached: Set<String> = [placed[0]]
            var frontier = [placed[0]]
            while let current = frontier.popLast() {
                for next in neighbours[current] ?? [] where next != "g" && reached.insert(next).inserted { frontier.append(next) }
            }
            guard reached.count == placed.count else {
                LevelTemplate.debug?("\(options.template): the knot falls apart in two (phase \(phase), \(reached.count) of \(placed.count))")
                return nil
            }
        }

        var draft = LevelDraft(name: options.name, template: options.template, board: options.board)
        var closed = Set<String>()
        if mirror {
            for r in kept where !r.isGiant && r.id <= twin(r.id) && holders[r.id] == nil && holders[twin(r.id)] == nil {
                if rng.chance(options.anchorChance) { closed.formUnion([r.id, twin(r.id)]) }
            }
        }
        for r in kept {
            if mirror {
                if r.isGiant || closed.contains(r.id) {
                    closed.insert(r.id)
                    draft.pieces.append(.closedRing(r.id, at: r.center, radius: r.radius))
                } else {
                    draft.pieces.append(.ring(r.id, at: r.center, radius: r.radius))
                }
            } else if r.isGiant || pictureClosed.contains(r.id) || (holders[r.id] == nil && rng.chance(options.anchorChance)) {
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

        /// The mirror image of an angle, and whether an angle is its own image (straight up or down).
        func mirrored(_ degrees: Double) -> Double { normalizedDegrees(180 - degrees) }
        func isUpright(_ degrees: Double) -> Bool { degreeDifference(degrees, 90) < 0.5 || degreeDifference(degrees, 270) < 0.5 }

        // Bars poking into gaps from open space, planned before the other gaps: the poked ring's gap
        // faces the bar, so the ring cannot turn until the bar has slid out.
        var fixedGaps = Set<String>()
        var bars: [DraftPiece] = []
        func barRoom(_ from: Point, _ to: Point, except: String) -> Bool { barRoom(from, to, except: [except]) }
        func barRoom(_ from: Point, _ to: Point, except: Set<String>) -> Bool {
            let segment = Segment(from: from, to: to)
            let ends = [from, to]
            guard ends.allSatisfy({ abs($0.x) + 6 <= extent.x && abs($0.y) + 6 <= extent.y }) else { return false }
            for other in kept where !except.contains(other.id) {
                let near = Geometry.samplePoints(on: segment, spacing: GameRules.distanceSampleSpacing)
                    .map { abs($0.distance(to: other.center) - other.radius) }.min() ?? .infinity
                if near < 14 { return false }
            }
            return bars.allSatisfy { bar in
                guard case .segment(let s) = bar.shapes[0] else { return true }
                return Geometry.distance(segment, Segment(from: bar.toWorld(s.from), to: bar.toWorld(s.to))) >= 14
            }
        }
        /// The bar poking into `r` along direction `k`, or nil when there is no room for it.
        func poke(_ r: Ring, _ k: Int, length: Double) -> (index: Int, degrees: Double, bar: DraftPiece)? {
            let degrees = lattice(k)
            let taken = ((holders[r.id] ?? []) + (targets[r.id] ?? [])).map { linkAngle(r.id, $0) }
            guard taken.allSatisfy({ degreeDifference($0, degrees) >= 90 }),
                  draft.gapIsValid(centerDegrees: degrees, gapDegrees: gapWidth(r.id), for: r.id) else { return nil }
            let dir = direction(k)
            let start = r.radius - 10
            let inner = r.center + dir * start
            let exitEnd = r.center + dir * (start + length + GameRules.holderLength / 2 + 1 + GridWorld.hubInset + 8)
            guard barRoom(r.center + dir * (r.radius + 8), exitEnd, except: r.id), let index = draft.index(of: r.id) else { return nil }
            return (index, degrees, .slideBar("p\(bars.count)", at: inner + dir * GridWorld.hubInset, from: -GridWorld.hubInset,
                                              to: length - GridWorld.hubInset, angleDegrees: degrees))
        }
        // A picture's own bars: lines poking into a ring (stopped by another ring, or free to slide
        // out), and U-bars over two rings. A board where one does not fit is thrown away.
        let exitTravel = GameRules.holderLength / 2 + 1 + GridWorld.hubInset
        for (number, bar) in (options.picture?.bars ?? []).enumerated() {
            let k = Int((normalizedDegrees(bar.degrees) / ForgeRules.gridDegrees).rounded()) % 8
            let degrees = lattice(k), dir = direction(k)
            func takes(_ r: Ring) -> Bool {
                let taken = ((holders[r.id] ?? []) + (targets[r.id] ?? [])).map { linkAngle(r.id, $0) }
                return !closed.contains(r.id) && !fixedGaps.contains(r.id) && taken.allSatisfy { degreeDifference($0, degrees) >= 90 }
                    && draft.gapIsValid(centerDegrees: degrees, gapDegrees: gapWidth(r.id), for: r.id)
            }
            var piece: DraftPiece?
            var poked: [Ring] = []
            if let pair = bar.rings, pair.count == 2 {
                let a = rings[pair[0]], b = rings[pair[1]]
                if takes(a), takes(b) {
                    // Hubs a little beyond the rings; the arms reach back into both gaps.
                    let reach = max(a.radius, b.radius) + 26
                    let start = min(a.radius, b.radius) - 10
                    piece = .uBar("p\(bars.count)", at: (a.center + b.center) * 0.5 + dir * reach, width: a.center.distance(to: b.center),
                                  from: -(reach - start), to: bar.length ?? 40, angleDegrees: degrees)
                    poked = [a, b]
                }
            } else if let index = bar.ring {
                let r = rings[index]
                let start = r.radius - 10
                var end = start + (bar.length ?? 60)
                var except: Set<String> = [r.id]
                var exitEnd = r.center + dir * (end + exitTravel + 8)
                if let stop = bar.stop {
                    let s = rings[stop]
                    end = r.center.distance(to: s.center) - s.radius - exitTravel - 2
                    except.insert(s.id)
                    exitEnd = r.center + dir * end
                }
                if takes(r), end - start >= 2 * GridWorld.hubInset, barRoom(r.center + dir * (r.radius + 8), exitEnd, except: except) {
                    piece = .slideBar("p\(bars.count)", at: r.center + dir * (start + GridWorld.hubInset), from: -GridWorld.hubInset,
                                      to: end - start - GridWorld.hubInset, angleDegrees: degrees)
                    poked = [r]
                }
            }
            // The bars are lines of the picture: without one it would look broken.
            guard var piece else {
                LevelTemplate.debug?("\(options.template): no room for bar \(number)")
                return nil
            }
            piece.color = bar.color
            for r in poked {
                if let index = draft.index(of: r.id) { draft.pieces[index].setGap(centerDegrees: degrees, degrees: gapWidth(r.id)) }
                fixedGaps.insert(r.id)
            }
            bars.append(piece)
        }
        for _ in 0..<(mirror ? options.pokes : 0) {
            var done = false
            for r in kept.shuffled(using: &rng) where !done && !closed.contains(r.id) && !fixedGaps.contains(r.id) && r.id <= twin(r.id) {
                let length = Double(rng.int(in: 50...80))
                for k in (0..<8).shuffled(using: &rng) where twin(r.id) != r.id || isUpright(lattice(k)) {
                    guard let first = poke(r, k, length: length) else { continue }
                    draft.pieces[first.index].setGap(centerDegrees: first.degrees, degrees: gapWidth(r.id))
                    bars.append(first.bar)
                    if twin(r.id) != r.id {
                        guard let second = poke(ring(twin(r.id)), twin(direction: k), length: length) else {
                            bars.removeLast()
                            continue
                        }
                        draft.pieces[second.index].setGap(centerDegrees: second.degrees, degrees: gapWidth(twin(r.id)))
                        bars.append(second.bar)
                    }
                    fixedGaps.formUnion([r.id, twin(r.id)])
                    done = true
                    break
                }
            }
        }
        for _ in 0..<(mirror ? 0 : options.pokes) {
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
                var choices = (0..<8).map(lattice).filter { draft.gapIsValid(centerDegrees: $0, gapDegrees: width, for: r.id) }
                if mirror {
                    // The image's gap at the mirrored angle; on the axis straight up or down.
                    choices = twin(r.id) == r.id ? choices.filter(isUpright)
                        : choices.filter { draft.gapIsValid(centerDegrees: mirrored($0), gapDegrees: gapWidth(twin(r.id)), for: twin(r.id)) }
                }
                guard !choices.isEmpty else { continue }
                // A picture's ring keeps its gap where the picture wants it, if it can.
                let preferred = options.picture.flatMap { picture in rings.firstIndex { $0.id == r.id }.flatMap { picture.rings[$0].gap } }
                let center = preferred.flatMap { want in choices.first { degreeDifference($0, want) < 1 } } ?? rng.pick(choices)
                draft.pieces[index].setGap(centerDegrees: center, degrees: width)
                if mirror, twin(r.id) != r.id, let image = draft.index(of: twin(r.id)) {
                    draft.pieces[image].setGap(centerDegrees: mirrored(center), degrees: gapWidth(twin(r.id)))
                    fixedGaps.insert(twin(r.id))
                }
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
            func bombAngles(_ id: String) -> [Double] {
                guard let index = draft.index(of: id) else { return [] }
                let piece = draft.pieces[index]
                let gapHalf = (piece.gapDegrees ?? 0) / 2
                let busy = draft.contactAngles(on: id) + draft.stemRootAngles(of: id)
                return (0..<8).map(lattice).filter { angle in
                    (piece.gapCenterDegrees.map { degreeDifference($0, angle) > gapHalf + 30 } ?? true) && busy.allSatisfy { degreeDifference($0, angle) >= 40 }
                }
            }
            let freeIDs = Set(free.map(\.id))
            for r in free.shuffled(using: &rng) where placed < options.bombs && (!mirror || (r.id <= twin(r.id) && freeIDs.contains(twin(r.id)))) {
                guard let index = draft.index(of: r.id) else { continue }
                var choices = bombAngles(r.id)
                if mirror {
                    let imageAngles = bombAngles(twin(r.id))
                    choices = twin(r.id) == r.id ? choices.filter(isUpright)
                        : choices.filter { angle in imageAngles.contains { degreeDifference($0, mirrored(angle)) < 0.5 } }
                }
                guard !choices.isEmpty else { continue }
                let degrees = rng.pick(choices)
                let angle = AngleMath.radians(fromDegrees: degrees)
                draft.pieces[index].bomb = Point(cos(angle), sin(angle)) * r.radius
                let image = mirror && twin(r.id) != r.id ? draft.index(of: twin(r.id)) : nil
                if let image {
                    let imageAngle = AngleMath.radians(fromDegrees: mirrored(degrees))
                    draft.pieces[image].bomb = Point(cos(imageAngle), sin(imageAngle)) * r.radius
                }
                if stands(draft.pieces) {
                    placed += image == nil ? 1 : 2
                } else {
                    draft.pieces[index].bomb = nil
                    if let image { draft.pieces[image].bomb = nil }
                }
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
            func tailAngles(_ id: String) -> [Double] {
                guard let index = draft.index(of: id), let gap = draft.pieces[index].gapCenterDegrees else { return [] }
                let taken = ((holders[id] ?? []) + (targets[id] ?? [])).map { linkAngle(id, $0) }
                return (0..<8).map(lattice).filter { angle in
                    degreeDifference(angle, gap) >= 90 && taken.allSatisfy { degreeDifference($0, angle) >= 60 }
                        && draft.pieces[index].bomb.map { degreeDifference(AngleMath.degrees(fromRadians: $0.angle), angle) >= 45 } ?? true
                }
            }
            for r in kept.shuffled(using: &rng) where !closed.contains(r.id) && (!mirror || r.id <= twin(r.id)) && rng.chance(options.tailShare) {
                guard let index = draft.index(of: r.id) else { continue }
                var choices = tailAngles(r.id)
                if mirror {
                    let imageAngles = tailAngles(twin(r.id))
                    choices = twin(r.id) == r.id ? choices.filter(isUpright)
                        : choices.filter { angle in imageAngles.contains { degreeDifference($0, mirrored(angle)) < 0.5 } }
                }
                guard !choices.isEmpty else { continue }
                let before = draft.pieces
                let angle = rng.pick(choices)
                draft.pieces[index].addTail(atDegrees: angle, length: length)
                if mirror, twin(r.id) != r.id, let image = draft.index(of: twin(r.id)) {
                    draft.pieces[image].addTail(atDegrees: mirrored(angle), length: length)
                }
                if !stands(draft.pieces) { draft.pieces = before }
            }
        }

        let connections = draft.pieces.reduce(0) { $0 + $1.clips.count + ($1.motion == .slide ? 1 : 0) }
        guard connections <= maxConnections else {
            LevelTemplate.debug?("\(options.template): \(connections) connections, too many for the solver")
            return nil
        }
        if let picture = options.picture {
            // A picture keeps its colours by part; tails and clips are drawn in their ring's.
            for (index, spec) in picture.rings.enumerated() {
                if let color = spec.color, let piece = draft.index(of: "f\(index + 1)") { draft.pieces[piece].color = color }
            }
        }
        var motif = Motif(name: options.name, template: options.template, pieces: draft.pieces)
        motif.mirrorColors = mirror && options.mirrorColors
        motif.keepColors = options.picture.map { picture in picture.rings.allSatisfy { $0.color != nil } } ?? false
        guard motif.width <= options.board.width - 2 * ForgeRules.margin, motif.height <= options.board.height - 2 * ForgeRules.margin,
              stands(draft.pieces) else {
            LevelTemplate.debug?("\(options.template): does not fit or stand")
            return nil
        }
        return motif
    }
}
