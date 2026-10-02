//
//  Motifs.swift
//  RotateRings
//
//  Small self-contained puzzles ("motifs") built around a local origin. Tutorial levels use one
//  motif centred on the board; later levels stack several. Every motif keeps its clip contacts and
//  gap centres on the 45° grid so the solver's moves are exactly the player's natural drags.
//
//  Two kinds of bar. Latch bars carry a clip; a clip owner is pinned, so they never move and only
//  leave when the ring they grip frees them. Hub bars (straight or bent) sit in a fixed metal hub and
//  slide along its axis; they leave when the arm has slid out of the hub.
//

import Foundation

extension SplitMix64 {
    mutating func int(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func bool() -> Bool {
        next() & 1 == 1
    }

    mutating func pick<T>(_ options: [T]) -> T {
        options[Int(next() % UInt64(options.count))]
    }

    /// A lock step count in `range`, with random sign.
    mutating func lockSteps(in range: ClosedRange<Int>) -> Int {
        int(in: range) * (bool() ? 1 : -1)
    }
}

/// A puzzle fragment in local coordinates.
struct Motif {
    var name: String
    var template: String
    var pieces: [DraftPiece]

    /// Axis-aligned extent of all strokes, including clips and stroke width.
    var bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        func include(_ center: Point, _ radius: Double) {
            minX = min(minX, center.x - radius); maxX = max(maxX, center.x + radius)
            minY = min(minY, center.y - radius); maxY = max(maxY, center.y + radius)
        }
        let pad = GameRules.strokeThickness / 2
        for piece in pieces {
            for shape in piece.shapes {
                switch shape {
                case .arc(let arc): include(piece.toWorld(arc.center), arc.radius + pad)
                case .segment(let segment):
                    include(piece.toWorld(segment.from), pad)
                    include(piece.toWorld(segment.to), pad)
                }
            }
            for clip in piece.clips {
                include(piece.toWorld(clip.stemEnd), GameRules.clipSize / 2 + pad)
            }
            if piece.motion == .slide {
                // Room for the holder; the bar itself is covered by its segment.
                include(piece.position, GameRules.holderLength / 2 + pad)
            }
        }
        return (minX, maxX, minY, maxY)
    }

    var width: Double { let b = bounds; return b.maxX - b.minX }
    var height: Double { let b = bounds; return b.maxY - b.minY }

    /// The motif shifted onto `center`. Vertically the bounds are centred. Horizontally the motif's
    /// origin (where its featured piece sits) goes to `center.x`, unless that would push the motif
    /// past the board margins, in which case it is shifted just enough to fit; `anchored: false`
    /// centres the bounds horizontally instead.
    func placed(at center: Point, anchored: Bool = true) -> [DraftPiece] {
        let b = bounds
        var dx = anchored ? center.x : center.x - (b.minX + b.maxX) / 2
        if anchored {
            let minX = ForgeRules.margin, maxX = ForgeRules.boardWidth - ForgeRules.margin
            if b.minX + dx < minX { dx = minX - b.minX }
            if b.maxX + dx > maxX { dx = maxX - b.maxX }
        }
        let offset = Point(dx, center.y - (b.minY + b.maxY) / 2)
        return pieces.map { $0.translated(by: offset) }
    }

    func mirrored(flipX: Bool, flipY: Bool) -> Motif {
        var copy = self
        copy.pieces = pieces.map { $0.mirrored(flipX: flipX, flipY: flipY) }
        return copy
    }
}

enum Motifs {

    private static func finish(_ draft: LevelDraft) -> Motif {
        Motif(name: draft.name, template: draft.template, pieces: draft.pieces)
    }

    // MARK: Rings

    /// A vertical chain: each ring grips the one below it. The bottom ring turns first.
    static func ringChain(count: Int, radius: Double = 45, lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let spacing = 2 * radius + ForgeRules.preferredStem
        var draft = LevelDraft(name: count == 2 ? "Two rings" : "Chain of \(count)", template: "ringChain\(count)")
        let top = Double(count - 1) * spacing / 2
        for i in 0..<count {
            draft.pieces.append(.ring("r\(i)", at: Point(0, top - Double(i) * spacing), radius: radius))
        }
        for i in 0..<(count - 1) {
            guard draft.addRingClip(from: "r\(i)", to: "r\(i + 1)") else { return nil }
        }
        guard draft.planFreeGap(for: "r0", rng: &rng) else { return nil }
        for i in 1..<count {
            guard draft.planGap(for: "r\(i)", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        }
        return finish(rng.bool() ? draft : LevelDraft(name: draft.name, template: draft.template, pieces: draft.pieces.map { $0.mirrored(flipX: false, flipY: true) }))
    }

    /// An L of three rings: a side ring grips the middle, the middle grips the bottom.
    static func ringCorner(radius: Double = 40, lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let spacing = 2 * radius + ForgeRules.preferredStem
        var draft = LevelDraft(name: "Corner", template: "ringCorner")
        draft.pieces = [
            .ring("m", at: .zero, radius: radius),
            .ring("b", at: Point(0, -spacing), radius: radius),
            .ring("s", at: Point(spacing, 0), radius: radius),
        ]
        guard draft.addRingClip(from: "s", to: "m"), draft.addRingClip(from: "m", to: "b") else { return nil }
        guard draft.planFreeGap(for: "s", rng: &rng),
              draft.planGap(for: "m", lockSteps: rng.lockSteps(in: lockRange)) != nil,
              draft.planGap(for: "b", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        return finish(draft).mirrored(flipX: rng.bool(), flipY: rng.bool())
    }

    /// A closed anchor ring in the centre whose clips hold `count` satellites. Each satellite turns
    /// its gap to the anchor's clip; the anchor leaves with the last one.
    static func anchorStar(count: Int, lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let anchorRadius = 40.0
        let satelliteRadius = count >= 4 ? 40.0 : 45.0
        let distance = anchorRadius + ForgeRules.preferredStem + satelliteRadius
        let angles: [Double]
        switch count {
        case 2: angles = [90, 270]
        case 3: angles = [90, 210, 330]
        default: angles = [0, 90, 180, 270]
        }
        var draft = LevelDraft(name: count == 2 ? "Anchor" : "Star of \(count)", template: "anchorStar\(count)")
        draft.pieces.append(.closedRing("o", at: .zero, radius: anchorRadius))
        for (i, angle) in angles.enumerated() {
            let direction = Point(cos(AngleMath.radians(fromDegrees: angle)), sin(AngleMath.radians(fromDegrees: angle)))
            draft.pieces.append(.ring("s\(i)", at: direction * distance, radius: satelliteRadius))
            guard draft.addClip(from: "o", at: direction * anchorRadius, to: "s\(i)") else { return nil }
        }
        for i in angles.indices {
            guard draft.planGap(for: "s\(i)", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        }
        return finish(draft).mirrored(flipX: rng.bool(), flipY: count == 3 && rng.bool())
    }

    /// A closed outer ring gripping a C-ring inside it, optionally also a satellite outside.
    static func concentric(withSatellite: Bool, lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let outerRadius = 65.0
        let innerRadius = 40.0
        let angle = withSatellite ? rng.pick([90.0, 270.0]) : Double(rng.int(in: 0...7)) * 45
        let direction = Point(cos(AngleMath.radians(fromDegrees: angle)), sin(AngleMath.radians(fromDegrees: angle)))
        var draft = LevelDraft(name: withSatellite ? "Closed loop" : "Inside out", template: withSatellite ? "concentricSatellite" : "concentric")
        draft.pieces = [
            .closedRing("o", at: .zero, radius: outerRadius),
            .ring("i", at: .zero, radius: innerRadius),
        ]
        guard draft.addClip(from: "o", at: direction * outerRadius, to: "i") else { return nil }
        guard draft.planGap(for: "i", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        if withSatellite {
            let satelliteRadius = 40.0
            let away = -direction
            draft.pieces.append(.ring("s", at: away * (outerRadius + ForgeRules.preferredStem + satelliteRadius), radius: satelliteRadius))
            guard draft.addClip(from: "o", at: away * outerRadius, to: "s") else { return nil }
            guard draft.planGap(for: "s", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        }
        return finish(draft)
    }

    // MARK: Bars

    /// A latch bar whose clip grips ring A above while its lower end sits in ring B's gap. B is locked
    /// by one or two side rings. A frees the bar, then B can turn to free its locks.
    static func barLatch(locks: Int, lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let halfLength = 60.0
        let ringA = 45.0, ringB = 50.0, lockRadius = 35.0
        var draft = LevelDraft(name: locks == 1 ? "Latch" : "Double latch", template: locks == 1 ? "barLatch" : "barLatch2")
        draft.pieces = [
            .latchBar("bar", at: .zero, from: -halfLength, to: halfLength),
            .ring("a", at: Point(0, halfLength + ForgeRules.preferredStem + ringA), radius: ringA),
            .ring("b", at: Point(0, -(halfLength + ringB - 15)), radius: ringB),
        ]
        guard draft.addClip(from: "bar", at: Point(0, halfLength), to: "a") else { return nil }
        let sides: [Double] = locks == 1 ? [rng.bool() ? 1 : -1] : [1, -1]
        for (i, side) in sides.enumerated() {
            let lockX = side * (ringB + 15 + lockRadius)
            draft.pieces.append(.ring("l\(i)", at: Point(lockX, draft["b"]!.position.y), radius: lockRadius))
            guard draft.addRingClip(from: "l\(i)", to: "b") else { return nil }
            guard draft.planFreeGap(for: "l\(i)", rng: &rng) else { return nil }
        }
        // B's gap must face the bar; the locks sit a quarter turn away on the grid.
        guard let bIndex = draft.index(of: "b") else { return nil }
        draft.pieces[bIndex].setGap(centerDegrees: 90, degrees: ForgeRules.defaultGapDegrees)
        guard draft.gapIsValid(centerDegrees: 90, gapDegrees: ForgeRules.defaultGapDegrees, for: "b") else { return nil }
        guard draft.planGap(for: "a", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        return finish(draft)
    }

    /// Places `count` lock rings of `radius` on ring `ringID`'s circle so that each lock's clip contact
    /// is `steps[i]` grid steps from `gapCenter`, on the given side(s). Each lock grips the ring and
    /// gets a free gap. Returns false when any contact fails to fit beside the gap.
    private static func addLocks(to draft: inout LevelDraft, ringID: String, gapCenter: Double, gapDegrees: Double,
                                 steps: [Int], radius: Double, rng: inout SplitMix64) -> Bool {
        guard let ring = draft[ringID], let ringRadius = ring.radius else { return false }
        let distance = ringRadius + ForgeRules.preferredStem + radius
        for (i, step) in steps.enumerated() {
            let angle = AngleMath.radians(fromDegrees: gapCenter + Double(step) * ForgeRules.gridDegrees)
            draft.pieces.append(.ring("k\(i)", at: ring.position + Point(cos(angle), sin(angle)) * distance, radius: radius))
            guard draft.addRingClip(from: "k\(i)", to: ringID) else { return false }
            guard draft.planFreeGap(for: "k\(i)", rng: &rng) else { return false }
        }
        guard let index = draft.index(of: ringID) else { return false }
        draft.pieces[index].setGap(centerDegrees: gapCenter, degrees: gapDegrees)
        return draft.gapIsValid(centerDegrees: gapCenter, gapDegrees: gapDegrees, for: ringID)
    }

    /// Gap width for a ring whose nearest lock is `steps` grid steps from the gap centre.
    private static func gapWidth(radius: Double, nearestSteps steps: Int) -> Double {
        abs(steps) == 1 ? ForgeRules.narrowGapDegrees(radius: radius) : ForgeRules.defaultGapDegrees
    }

    /// A sliding bar in a hub below ring R, its top end poking up into R's gap so R cannot turn. R is
    /// gripped by one or two lock rings. Slide the bar down and out, then turn R to free its locks.
    static func slideLatch(locks: Int, lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let ringR = 45.0, lockRadius = 40.0
        let hubY = -95.0
        var draft = LevelDraft(name: locks == 1 ? "Slider" : "Double slider", template: locks == 1 ? "slideLatch" : "slideLatch2")
        draft.pieces = [
            .ring("r", at: .zero, radius: ringR, gapCenterDegrees: 270),
            // Arm from 100 below the hub up to R's circle (y = -45): the arc runs into it when R turns.
            // Pushed up, the bar runs into the far side of R before its lower end could leave the hub,
            // so the only way out is down.
            .slideBar("s", at: Point(0, hubY), from: -100, to: -ringR - hubY),
        ]
        let step = rng.int(in: lockRange)
        // One lock on a random side; two locks on both sides, same distance.
        let steps = locks == 1 ? [rng.bool() ? step : -step] : [step, -step]
        guard addLocks(to: &draft, ringID: "r", gapCenter: 270, gapDegrees: gapWidth(radius: ringR, nearestSteps: step),
                       steps: steps, radius: lockRadius, rng: &rng) else { return nil }
        return finish(draft).mirrored(flipX: rng.bool(), flipY: rng.bool())
    }

    /// An L-bar in a hub beside ring R: its vertical arm runs past R and its leg reaches across R's
    /// upward gap, so R cannot turn. The leg can never pass the hub, so the only way out is up. R is
    /// gripped by one or two lock rings on the far side. Slide the elbow out, then turn R.
    static func elbowSlide(locks: Int, lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let ringR = 45.0, lockRadius = 40.0
        let hub = Point(75, -60)
        let legY = 52.0
        var draft = LevelDraft(name: locks == 1 ? "Elbow slider" : "Double elbow", template: locks == 1 ? "elbowSlide" : "elbowSlide2")
        draft.pieces = [
            .ring("r", at: .zero, radius: ringR, gapCenterDegrees: 90),
            // Axis points up; the leg (local +y) points left across the top of R, ending above its centre.
            .slideElbow("e", at: hub, from: -50, to: legY - hub.y, legLength: hub.x),
        ]
        let step = rng.int(in: lockRange)
        // Locks go on the left, away from the arm: 135°, 180°, 225°, … Two locks sit a half turn apart
        // on the grid so they never touch each other.
        let steps = locks == 1 ? [step] : [step, step + 2]
        guard addLocks(to: &draft, ringID: "r", gapCenter: 90, gapDegrees: gapWidth(radius: ringR, nearestSteps: step),
                       steps: steps, radius: lockRadius, rng: &rng) else { return nil }
        return finish(draft).mirrored(flipX: rng.bool(), flipY: rng.bool())
    }

    /// A sliding bar reaching into two rings, each locked by a side ring. Slide the bar down to free
    /// the top ring, then slide it out to free the bottom one.
    static func slideGate(lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let ringRadius = 50.0, lockRadius = 35.0, ringY = 130.0
        var draft = LevelDraft(name: "Gate", template: "slideGate")
        draft.pieces = [
            .slideBar("s", at: .zero, length: 200),
            .ring("t", at: Point(0, ringY), radius: ringRadius, gapCenterDegrees: 270),
            .ring("b", at: Point(0, -ringY), radius: ringRadius, gapCenterDegrees: 90),
        ]
        let lockX = ringRadius + 15 + lockRadius
        let topSide: Double = rng.bool() ? 1 : -1
        let bottomSide: Double = rng.bool() ? 1 : -1
        draft.pieces.append(.ring("lt", at: Point(topSide * lockX, ringY), radius: lockRadius))
        draft.pieces.append(.ring("lb", at: Point(bottomSide * lockX, -ringY), radius: lockRadius))
        guard draft.addRingClip(from: "lt", to: "t"), draft.addRingClip(from: "lb", to: "b") else { return nil }
        guard draft.gapIsValid(centerDegrees: 270, gapDegrees: ForgeRules.defaultGapDegrees, for: "t"),
              draft.gapIsValid(centerDegrees: 90, gapDegrees: ForgeRules.defaultGapDegrees, for: "b") else { return nil }
        guard draft.planFreeGap(for: "lt", rng: &rng), draft.planFreeGap(for: "lb", rng: &rng) else { return nil }
        _ = lockRange
        return finish(draft)
    }

    /// A bent latch bar pinned by a latch ring; its long arm reaches through ring S's gap. Turn the
    /// latch to drop the bar, then S can turn to free its own lock.
    static func elbowLatch(lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let ringS = 45.0, latchRadius = 30.0, lockRadius = 40.0
        var draft = LevelDraft(name: "Elbow", template: "elbowLatch")
        draft.pieces = [
            .ring("s", at: .zero, radius: ringS, gapCenterDegrees: 0),
            .latchElbow("e", at: Point(90, 0), armStart: Point(-105, 0), corner: Point(20, 0), armEnd: Point(20, 80)),
            .ring("latch", at: Point(110, 80 + ForgeRules.preferredStem + latchRadius), radius: latchRadius),
        ]
        guard draft.addClip(from: "e", at: Point(110, 80), to: "latch") else { return nil }
        let lockSpot = rng.pick([Point(0, ringS + ForgeRules.preferredStem + lockRadius),
                                 Point(0, -(ringS + ForgeRules.preferredStem + lockRadius)),
                                 Point(-(ringS + ForgeRules.preferredStem + lockRadius), 0)])
        draft.pieces.append(.ring("k", at: lockSpot, radius: lockRadius))
        guard draft.addRingClip(from: "k", to: "s") else { return nil }
        guard draft.gapIsValid(centerDegrees: 0, gapDegrees: ForgeRules.defaultGapDegrees, for: "s") else { return nil }
        guard draft.planGap(for: "latch", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        guard draft.planFreeGap(for: "k", rng: &rng) else { return nil }
        return finish(draft).mirrored(flipX: rng.bool(), flipY: rng.bool())
    }

    // MARK: Tails

    /// A ring with a tail that reaches into a neighbour's gap. The neighbour cannot turn until the
    /// tail ring moves; the tail ring itself is held by a ring above.
    static func tailGate(lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let ringX = 45.0, other = 40.0, tailLength = 20.0
        let spacingX = ringX + ForgeRules.preferredStem + other
        var draft = LevelDraft(name: "Tail", template: "tailGate")
        // The tail ends exactly on N's circle, inside N's gap. Any further and it would snag N's arc
        // ends when X turns; any shorter and N could turn past it.
        draft.pieces = [
            .tailRing("x", at: .zero, radius: ringX, tailAngles: [0], tailLength: tailLength),
            .ring("u", at: Point(0, spacingX), radius: other),
            .ring("n", at: Point(ringX + tailLength + other, 0), radius: other, gapCenterDegrees: 180),
        ]
        let wY: Double = rng.bool() ? 1 : -1
        let nPosition = draft["n"]!.position
        draft.pieces.append(.ring("w", at: Point(nPosition.x, wY * (2 * other + ForgeRules.preferredStem)), radius: other))
        guard draft.addRingClip(from: "u", to: "x"), draft.addRingClip(from: "w", to: "n") else { return nil }
        guard draft.gapIsValid(centerDegrees: 180, gapDegrees: ForgeRules.defaultGapDegrees, for: "n") else { return nil }
        guard draft.planGap(for: "x", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        guard draft.planFreeGap(for: "u", rng: &rng), draft.planFreeGap(for: "w", rng: &rng) else { return nil }
        return finish(draft).mirrored(flipX: rng.bool(), flipY: false)
    }

    /// A ring whose tails carry clips gripping one or two rings. Those rings free the tail ring, which
    /// then turns to free the ring holding it.
    static func tailClip(tails: Int, withAnchor: Bool, lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let ringX = 40.0, other = 40.0, tailLength = 25.0
        let reach = ringX + tailLength
        var draft = LevelDraft(name: tails == 1 ? "Hook" : "Double hook", template: tails == 1 ? "tailClip" : "tailClip2")
        let tailAngles: [Double] = tails == 1 ? [90] : [90, 270]
        draft.pieces.append(.tailRing("x", at: .zero, radius: ringX, tailAngles: tailAngles, tailLength: tailLength))
        for (i, angle) in tailAngles.enumerated() {
            let direction = Point(cos(AngleMath.radians(fromDegrees: angle)), sin(AngleMath.radians(fromDegrees: angle)))
            draft.pieces.append(.ring("y\(i)", at: direction * (reach + ForgeRules.preferredStem + other), radius: other))
            guard draft.addClip(from: "x", at: direction * reach, to: "y\(i)") else { return nil }
        }
        if withAnchor {
            draft.pieces.append(.ring("u", at: Point(ringX + ForgeRules.preferredStem + other, 0), radius: other))
            guard draft.addRingClip(from: "u", to: "x") else { return nil }
            guard draft.planGap(for: "x", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
            guard draft.planFreeGap(for: "u", rng: &rng) else { return nil }
        } else {
            guard draft.planFreeGap(for: "x", rng: &rng) else { return nil }
        }
        for i in tailAngles.indices {
            guard draft.planGap(for: "y\(i)", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        }
        return finish(draft).mirrored(flipX: rng.bool(), flipY: tails == 1 && rng.bool())
    }
}
