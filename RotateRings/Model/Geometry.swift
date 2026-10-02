//
//  Geometry.swift
//  RotateRings
//
//  Pure geometry primitives used by the game model. No SpriteKit here.
//  Coordinate system: y points up, angles are radians, counterclockwise positive.
//

import Foundation

/// A 2D point or vector in board space.
struct Point: Hashable, Sendable, Codable {
    var x: Double
    var y: Double

    static let zero = Point(x: 0, y: 0)

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    // Encoded as a two element array `[x, y]` to keep level files compact.
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }

    var length: Double { (x * x + y * y).squareRoot() }

    /// Unit vector in the same direction, or `fallback` when the vector has no length.
    func normalized(fallback: Point = Point(0, 1)) -> Point {
        let len = length
        guard len > 1e-9 else { return fallback }
        return Point(x / len, y / len)
    }

    func distance(to other: Point) -> Double {
        (self - other).length
    }

    func dot(_ other: Point) -> Double {
        x * other.x + y * other.y
    }

    /// 2D cross product (z component).
    func cross(_ other: Point) -> Double {
        x * other.y - y * other.x
    }

    /// Angle of the vector from the origin, in radians.
    var angle: Double { atan2(y, x) }

    /// Rotates the point around the origin.
    func rotated(by angle: Double) -> Point {
        let c = cos(angle)
        let s = sin(angle)
        return Point(x * c - y * s, x * s + y * c)
    }

    /// Rotates around the origin and then translates. This is the local → world transform of a piece.
    func transformed(rotation: Double, translation: Point) -> Point {
        rotated(by: rotation) + translation
    }

    /// Perpendicular vector (rotated 90° counterclockwise).
    var perpendicular: Point { Point(-y, x) }

    static func + (lhs: Point, rhs: Point) -> Point { Point(lhs.x + rhs.x, lhs.y + rhs.y) }
    static func - (lhs: Point, rhs: Point) -> Point { Point(lhs.x - rhs.x, lhs.y - rhs.y) }
    static func * (lhs: Point, rhs: Double) -> Point { Point(lhs.x * rhs, lhs.y * rhs) }
    static prefix func - (p: Point) -> Point { Point(-p.x, -p.y) }
}

/// Angle helpers.
enum AngleMath {
    static let twoPi = 2 * Double.pi

    static func radians(fromDegrees degrees: Double) -> Double {
        degrees * .pi / 180
    }

    static func degrees(fromRadians radians: Double) -> Double {
        radians * 180 / .pi
    }

    /// Normalizes an angle into the half-open range `[0, 2π)`.
    static func normalized(_ angle: Double) -> Double {
        var result = angle.truncatingRemainder(dividingBy: twoPi)
        if result < 0 { result += twoPi }
        if result >= twoPi { result = 0 }
        return result
    }

    /// Smallest absolute difference between two angles, in `[0, π]`.
    static func difference(_ a: Double, _ b: Double) -> Double {
        let d = normalized(a - b)
        return min(d, twoPi - d)
    }

    /// Signed shortest rotation that takes `from` to `to`, in `(-π, π]`.
    static func shortestDelta(from: Double, to: Double) -> Double {
        let d = normalized(to - from)
        return d > .pi ? d - twoPi : d
    }
}

/// A counterclockwise angular range starting at `start` and spanning `sweep` radians.
struct AngularRange: Hashable, Sendable {
    var start: Double
    var sweep: Double

    var end: Double { start + sweep }
    var mid: Double { start + sweep / 2 }

    /// Whether `angle` lies inside the range, at least `margin` radians away from both edges.
    func contains(_ angle: Double, margin: Double = 0) -> Bool {
        let relative = AngleMath.normalized(angle - start)
        return relative >= margin - 1e-9 && relative <= sweep - margin + 1e-9
    }
}

/// A circular arc. A `sweep` of 2π (or more) is a closed circle.
struct Arc: Hashable, Sendable {
    var center: Point
    var radius: Double
    /// Start angle in radians.
    var start: Double
    /// Counterclockwise extent in radians, `0 < sweep <= 2π`.
    var sweep: Double

    static let closedSweep = AngleMath.twoPi

    var isClosed: Bool { sweep >= AngleMath.twoPi - 1e-9 }
    var end: Double { start + sweep }
    var length: Double { radius * sweep }

    var startPoint: Point { point(at: start) }
    var endPoint: Point { point(at: end) }

    func point(at angle: Double) -> Point {
        Point(center.x + radius * cos(angle), center.y + radius * sin(angle))
    }

    /// Whether the given polar angle (relative to the center) is covered by the arc.
    func contains(angle: Double) -> Bool {
        if isClosed { return true }
        let relative = AngleMath.normalized(angle - start)
        return relative <= sweep + 1e-9
    }

    /// The angular range not covered by the arc, or `nil` for a closed ring.
    var gap: AngularRange? {
        guard !isClosed else { return nil }
        return AngularRange(start: end, sweep: AngleMath.twoPi - sweep)
    }

    func transformed(rotation: Double, translation: Point) -> Arc {
        Arc(
            center: center.transformed(rotation: rotation, translation: translation),
            radius: radius,
            start: start + rotation,
            sweep: sweep
        )
    }
}

/// A straight line segment.
struct Segment: Hashable, Sendable {
    var from: Point
    var to: Point

    var vector: Point { to - from }
    var length: Double { vector.length }
    var midpoint: Point { Point((from.x + to.x) / 2, (from.y + to.y) / 2) }

    func transformed(rotation: Double, translation: Point) -> Segment {
        Segment(
            from: from.transformed(rotation: rotation, translation: translation),
            to: to.transformed(rotation: rotation, translation: translation)
        )
    }
}

/// The two drawing/collision primitives every piece is built from.
enum Primitive: Hashable, Sendable {
    case arc(Arc)
    case segment(Segment)

    func transformed(rotation: Double, translation: Point) -> Primitive {
        switch self {
        case .arc(let arc):
            return .arc(arc.transformed(rotation: rotation, translation: translation))
        case .segment(let segment):
            return .segment(segment.transformed(rotation: rotation, translation: translation))
        }
    }

    /// A circle that fully contains the primitive, used for quick rejection in collision tests.
    var boundingCircle: (center: Point, radius: Double) {
        switch self {
        case .arc(let arc):
            return (arc.center, arc.radius)
        case .segment(let segment):
            return (segment.midpoint, segment.length / 2)
        }
    }
}
