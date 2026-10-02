//
//  ForgeGeometry.swift
//  RotateRings
//
//  Building blocks for generated levels: the drafting rules and a mutable piece description that is
//  easy to place, mirror and wire before it becomes a `LevelFile.PieceSpec`. Drafts work in degrees
//  and board units, y up, like the level files.
//

import Foundation

/// Layout rules every generated level obeys.
enum ForgeRules {
    static let boardWidth = 360.0
    static let boardHeight = 640.0
    static let center = Point(180, 320)
    /// Nothing is drawn closer than this to the board edge.
    static let margin = 24.0
    /// Clip stems shorter than this look glued on; longer ones look flimsy.
    static let stemRange = 15.0...30.0
    static let preferredStem = 20.0
    /// Angular grid of the solver and of every clip contact / gap centre.
    static let gridDegrees = GameRules.rotationStepDegrees
    /// Default gap of a C-ring.
    static let defaultGapDegrees = 80.0
    /// Gap used when a clip sits only one grid step from the gap: narrow enough for the clip square to
    /// stay fully on the arc, wide enough for a comfortable release window.
    static let narrowGapDegrees = 60.0

    /// The widest gap that still leaves a clip one grid step away fully on the arc, capped at
    /// `narrowGapDegrees`. Small rings get a narrower gap; below `minGapDegrees` a one-step lock is
    /// not possible at all (see `supportsOneStepLock`).
    static func narrowGapDegrees(radius: Double) -> Double {
        min(narrowGapDegrees, (2 * (gridDegrees - contactClearanceDegrees(radius: radius))).rounded(.down))
    }

    static func supportsOneStepLock(radius: Double) -> Bool {
        narrowGapDegrees(radius: radius) >= minGapDegrees(radius: radius)
    }
    /// Gap of a ring gripped by two owners. When the first owner is freed it stays on the board, and
    /// its loose clip has to swing out of this gap without touching the arc ends.
    static let sharedGapDegrees = 100.0
    /// Smallest angular window inside which a drag must stop to release a clip.
    static let minReleaseWindowDegrees = 24.0
    /// The same window for a ring held by two clips up to a quarter turn apart, which is freed by
    /// turning its gap over both clips at once. Narrower than for a single clip: the gap already has
    /// to span both, and it should still read as a ring.
    static let sharedReleaseWindowDegrees = 16.0
    static let colors = ["coral", "yellow", "mint", "sky", "purple"]

    /// Half the angle the clip square covers on a ring of this radius.
    static func clipHalfAngleDegrees(radius: Double) -> Double {
        AngleMath.degrees(fromRadians: asin(min(1, GameRules.clipSize / 2 / radius)))
    }

    /// Narrowest gap that still leaves `minReleaseWindowDegrees` for the player to hit. Contacts and
    /// gap centres are grid-aligned, so a grid move always lands in the middle of that window.
    static func minGapDegrees(radius: Double) -> Double {
        2 * clipHalfAngleDegrees(radius: radius) + minReleaseWindowDegrees
    }

    /// How far (in degrees) a clip contact must stay outside a gap edge so the clip starts gripped.
    static func contactClearanceDegrees(radius: Double) -> Double {
        clipHalfAngleDegrees(radius: radius) + 2
    }

    /// How far a clip's own stem root must stay from the owner's gap edge so the stem leaves the arc.
    static let stemRootClearanceDegrees = 8.0
}

func normalizedDegrees(_ degrees: Double) -> Double {
    var value = degrees.truncatingRemainder(dividingBy: 360)
    if value < 0 { value += 360 }
    return value >= 360 ? 0 : value
}

/// Smallest absolute difference between two angles in degrees, in 0...180.
func degreeDifference(_ a: Double, _ b: Double) -> Double {
    let d = normalizedDegrees(a - b)
    return min(d, 360 - d)
}

/// A piece under construction.
struct DraftPiece {
    var id: String
    var kind: PieceKind
    var motion: Piece.Motion = .rotation
    var position: Point
    var rotationDegrees: Double = 0
    var shapes: [LevelFile.ShapeSpec]
    var clips: [LevelFile.ClipSpec] = []
    var color: String?

    // MARK: Ring access

    private var ringIndex: Int? {
        shapes.firstIndex { if case .arc = $0 { return true } else { return false } }
    }

    var ringArc: LevelFile.ArcSpec? {
        guard let index = ringIndex, case .arc(let arc) = shapes[index] else { return nil }
        return arc
    }

    var radius: Double? { ringArc?.radius }

    var isClosedRing: Bool { (ringArc?.sweep ?? 0) >= 360 }

    /// Width of the gap in degrees, nil for closed rings and non-rings.
    var gapDegrees: Double? {
        guard let arc = ringArc, arc.sweep < 360 else { return nil }
        return 360 - arc.sweep
    }

    /// Centre of the gap in local degrees.
    var gapCenterDegrees: Double? {
        guard let arc = ringArc, arc.sweep < 360 else { return nil }
        return normalizedDegrees(arc.start + arc.sweep / 2 + 180)
    }

    mutating func setGap(centerDegrees: Double, degrees: Double) {
        guard let index = ringIndex, case .arc(var arc) = shapes[index] else { return }
        arc.start = normalizedDegrees(centerDegrees + degrees / 2)
        arc.sweep = 360 - degrees
        shapes[index] = .arc(arc)
    }

    /// Adds a straight tail leaving the ring's arc at `degrees` (local).
    mutating func addTail(atDegrees degrees: Double, length: Double) {
        guard let radius else { return }
        let direction = Point(cos(AngleMath.radians(fromDegrees: degrees)), sin(AngleMath.radians(fromDegrees: degrees)))
        shapes.append(.segment(.init(from: direction * radius, to: direction * (radius + length))))
        kind = .tailRing
    }

    /// Closes the ring's gap, keeping its tails and clips.
    mutating func closeRing() {
        guard let index = ringIndex, case .arc(var arc) = shapes[index] else { return }
        arc.start = 0
        arc.sweep = 360
        shapes[index] = .arc(arc)
        if kind == .cRing { kind = .closedRing }
    }

    // MARK: Transforms

    func toWorld(_ local: Point) -> Point {
        local.rotated(by: AngleMath.radians(fromDegrees: rotationDegrees)) + position
    }

    func toLocal(_ world: Point) -> Point {
        (world - position).rotated(by: -AngleMath.radians(fromDegrees: rotationDegrees))
    }

    func translated(by offset: Point) -> DraftPiece {
        var copy = self
        copy.position = position + offset
        return copy
    }

    /// Mirrors the piece about `center`. Rotating pieces must have zero rotation (templates keep it so).
    /// A sliding piece keeps its hub axis pointing along the mirrored arm: the axis is mirrored and the
    /// local shape is re-expressed in the new frame, so bent arms end up on the mirrored side.
    func mirrored(flipX: Bool, flipY: Bool, about center: Point = .zero) -> DraftPiece {
        guard flipX || flipY else { return self }
        var copy = self
        copy.position = Point(flipX ? 2 * center.x - position.x : position.x, flipY ? 2 * center.y - position.y : position.y)
        func point(_ p: Point) -> Point { Point(flipX ? -p.x : p.x, flipY ? -p.y : p.y) }
        if motion == .slide {
            let oldAxis = AngleMath.radians(fromDegrees: rotationDegrees)
            let newAxisVector = point(Point(1, 0).rotated(by: oldAxis))
            let newAxis = newAxisVector.angle
            copy.rotationDegrees = normalizedDegrees(AngleMath.degrees(fromRadians: newAxis))
            // World-space mirror of a local point, expressed in the new local frame.
            func local(_ p: Point) -> Point { point(p.rotated(by: oldAxis)).rotated(by: -newAxis) }
            copy.shapes = shapes.map { shape in
                switch shape {
                case .arc(let arc):
                    return .arc(arc)
                case .segment(var segment):
                    segment.from = Self.tidy(local(segment.from))
                    segment.to = Self.tidy(local(segment.to))
                    return .segment(segment)
                }
            }
            copy.clips = clips.map { clip in
                var clip = clip
                clip.stemStart = Self.tidy(local(clip.stemStart))
                clip.stemEnd = Self.tidy(local(clip.stemEnd))
                return clip
            }
            return copy
        }
        precondition(rotationDegrees == 0, "mirroring assumes unrotated drafts")
        func angle(_ a: Double) -> Double {
            var result = a
            if flipX { result = 180 - result }
            if flipY { result = -result }
            return normalizedDegrees(result)
        }
        copy.shapes = shapes.map { shape in
            switch shape {
            case .arc(var arc):
                arc.center = point(arc.center)
                if arc.sweep < 360 {
                    // Reflection reverses orientation: the arc now runs from the image of its end.
                    let end = arc.start + arc.sweep
                    let start = flipX != flipY ? angle(end) : angle(arc.start)
                    arc.start = start
                }
                return .arc(arc)
            case .segment(var segment):
                segment.from = point(segment.from)
                segment.to = point(segment.to)
                return .segment(segment)
            }
        }
        copy.clips = clips.map { clip in
            var clip = clip
            clip.stemStart = point(clip.stemStart)
            clip.stemEnd = point(clip.stemEnd)
            return clip
        }
        return copy
    }

    // MARK: Factories

    static func ring(_ id: String, at position: Point, radius: Double, gapCenterDegrees: Double = 0, gapDegrees: Double = ForgeRules.defaultGapDegrees) -> DraftPiece {
        var piece = DraftPiece(id: id, kind: .cRing, position: position, shapes: [.arc(.init(center: .zero, radius: radius, start: 0, sweep: 360 - gapDegrees))])
        piece.setGap(centerDegrees: gapCenterDegrees, degrees: gapDegrees)
        return piece
    }

    static func closedRing(_ id: String, at position: Point, radius: Double) -> DraftPiece {
        DraftPiece(id: id, kind: .closedRing, position: position, shapes: [.arc(.init(center: .zero, radius: radius, start: 0, sweep: 360))])
    }

    /// A C-ring with straight tails leaving its arc at the given local angles.
    static func tailRing(_ id: String, at position: Point, radius: Double, tailAngles: [Double], tailLength: Double, gapCenterDegrees: Double = 0, gapDegrees: Double = ForgeRules.defaultGapDegrees) -> DraftPiece {
        var piece = ring(id, at: position, radius: radius, gapCenterDegrees: gapCenterDegrees, gapDegrees: gapDegrees)
        piece.kind = .tailRing
        for angle in tailAngles {
            let direction = Point(cos(AngleMath.radians(fromDegrees: angle)), sin(AngleMath.radians(fromDegrees: angle)))
            piece.shapes.append(.segment(.init(from: direction * radius, to: direction * (radius + tailLength))))
        }
        return piece
    }

    /// A straight latch bar pivoting at the origin, along the given local angle. The caller adds the
    /// clip that pins it.
    static func latchBar(_ id: String, at position: Point, from: Double, to: Double, angleDegrees: Double = 90) -> DraftPiece {
        let direction = Point(cos(AngleMath.radians(fromDegrees: angleDegrees)), sin(AngleMath.radians(fromDegrees: angleDegrees)))
        return DraftPiece(id: id, kind: .latchBar, position: position, shapes: [.segment(.init(from: direction * from, to: direction * to))])
    }

    /// A bent latch bar: one arm from `armStart` to `corner`, a second from `corner` to `armEnd`, all
    /// local. The caller adds the clip that pins it.
    static func latchElbow(_ id: String, at position: Point, armStart: Point, corner: Point, armEnd: Point) -> DraftPiece {
        DraftPiece(id: id, kind: .latchBar, position: position, shapes: [
            .segment(.init(from: armStart, to: corner)),
            .segment(.init(from: corner, to: armEnd)),
        ])
    }

    /// A bar of total length `length` centred in a hub at `position`, sliding along `angleDegrees`.
    static func slideBar(_ id: String, at position: Point, length: Double, angleDegrees: Double = 90) -> DraftPiece {
        slideBar(id, at: position, from: -length / 2, to: length / 2, angleDegrees: angleDegrees)
    }

    /// A straight bar in a hub at `position`: its arm runs from `from` to `to` along the hub axis
    /// (`angleDegrees`), measured from the hub. The range must cover the hub.
    static func slideBar(_ id: String, at position: Point, from: Double, to: Double, angleDegrees: Double = 90) -> DraftPiece {
        DraftPiece(id: id, kind: .slideBar, motion: .slide, position: position, rotationDegrees: angleDegrees,
                   shapes: [.segment(.init(from: Point(from, 0), to: Point(to, 0)))])
    }

    /// An L-bar in a hub: the arm through the hub runs from `from` to `to` along the axis, and a leg
    /// of signed length `legLength` leaves the `to` end perpendicular to the axis (positive is the
    /// axis turned 90° counterclockwise). The leg can never pass the hub, so the bar only leaves at
    /// the `from` end.
    static func slideElbow(_ id: String, at position: Point, from: Double, to: Double, legLength: Double, angleDegrees: Double = 90) -> DraftPiece {
        DraftPiece(id: id, kind: .lBar, motion: .slide, position: position, rotationDegrees: angleDegrees, shapes: [
            .segment(.init(from: Point(from, 0), to: Point(to, 0))),
            .segment(.init(from: Point(to, 0), to: Point(to, legLength))),
        ])
    }

    // MARK: Output

    /// The piece as it is written to the level file, with trigonometric noise rounded away.
    var spec: LevelFile.PieceSpec {
        LevelFile.PieceSpec(
            id: id,
            color: color,
            motion: motion == .slide ? .slide : nil,
            position: Self.tidy(position),
            rotation: rotationDegrees == 0 ? nil : Self.tidy(rotationDegrees),
            shapes: shapes.map { shape in
                switch shape {
                case .arc(let arc):
                    return .arc(.init(center: Self.tidy(arc.center), radius: Self.tidy(arc.radius), start: Self.tidy(arc.start), sweep: Self.tidy(arc.sweep)))
                case .segment(let segment):
                    return .segment(.init(from: Self.tidy(segment.from), to: Self.tidy(segment.to)))
                }
            },
            clips: clips.isEmpty ? nil : clips.map { .init(stemStart: Self.tidy($0.stemStart), stemEnd: Self.tidy($0.stemEnd), grips: $0.grips) }
        )
    }

    /// Rounds to a thousandth and turns negative zero into zero.
    static func tidy(_ value: Double) -> Double {
        let rounded = (value * 1000).rounded() / 1000
        return rounded == 0 ? 0 : rounded
    }

    static func tidy(_ point: Point) -> Point {
        Point(tidy(point.x), tidy(point.y))
    }
}
