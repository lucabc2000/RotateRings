//
//  Collision.swift
//  RotateRings
//
//  Distance and intersection tests between primitives.
//  Segment–segment distance is closed form. Anything involving an arc samples points along
//  one primitive and measures the exact point-to-primitive distance against the other, in both
//  directions. The sampling error is bounded by half the sample spacing.
//

import Foundation

enum Geometry {

    // MARK: Point to primitive

    static func distance(from point: Point, to segment: Segment) -> Double {
        let d = segment.vector
        let lengthSquared = d.dot(d)
        guard lengthSquared > 1e-12 else { return point.distance(to: segment.from) }
        let t = max(0, min(1, (point - segment.from).dot(d) / lengthSquared))
        return point.distance(to: segment.from + d * t)
    }

    static func distance(from point: Point, to arc: Arc) -> Double {
        let v = point - arc.center
        if arc.contains(angle: v.angle) {
            return abs(v.length - arc.radius)
        }
        return min(point.distance(to: arc.startPoint), point.distance(to: arc.endPoint))
    }

    static func distance(from point: Point, to primitive: Primitive) -> Double {
        switch primitive {
        case .arc(let arc): return distance(from: point, to: arc)
        case .segment(let segment): return distance(from: point, to: segment)
        }
    }

    // MARK: Segment to segment

    /// Whether two segments properly cross each other. Touching / collinear cases are handled by the
    /// endpoint distances in `distance(_:_:)`, so they need no special treatment here.
    static func segmentsCross(_ a: Segment, _ b: Segment) -> Bool {
        let d1 = b.vector.cross(a.from - b.from)
        let d2 = b.vector.cross(a.to - b.from)
        let d3 = a.vector.cross(b.from - a.from)
        let d4 = a.vector.cross(b.to - a.from)
        return d1 * d2 < 0 && d3 * d4 < 0
    }

    static func distance(_ a: Segment, _ b: Segment) -> Double {
        if segmentsCross(a, b) { return 0 }
        return min(
            distance(from: a.from, to: b),
            distance(from: a.to, to: b),
            distance(from: b.from, to: a),
            distance(from: b.to, to: a)
        )
    }

    // MARK: Sampling

    static func samplePoints(on segment: Segment, spacing: Double) -> [Point] {
        let count = max(1, Int((segment.length / spacing).rounded(.up)))
        return (0...count).map { i in
            segment.from + segment.vector * (Double(i) / Double(count))
        }
    }

    static func samplePoints(on arc: Arc, spacing: Double) -> [Point] {
        let count = max(1, Int((arc.length / spacing).rounded(.up)))
        return (0...count).map { i in
            arc.point(at: arc.start + arc.sweep * Double(i) / Double(count))
        }
    }

    // MARK: Primitive to primitive

    /// Approximate minimum distance between two primitives (exact for segment–segment).
    static func distance(_ a: Primitive, _ b: Primitive, sampleSpacing: Double = GameRules.distanceSampleSpacing) -> Double {
        switch (a, b) {
        case (.segment(let s1), .segment(let s2)):
            return distance(s1, s2)

        case (.arc(let arc), .segment(let segment)), (.segment(let segment), .arc(let arc)):
            var best = Double.infinity
            for p in samplePoints(on: segment, spacing: sampleSpacing) {
                best = min(best, distance(from: p, to: arc))
            }
            for p in samplePoints(on: arc, spacing: sampleSpacing) {
                best = min(best, distance(from: p, to: segment))
            }
            return best

        case (.arc(let a1), .arc(let a2)):
            var best = Double.infinity
            for p in samplePoints(on: a1, spacing: sampleSpacing) {
                best = min(best, distance(from: p, to: a2))
            }
            for p in samplePoints(on: a2, spacing: sampleSpacing) {
                best = min(best, distance(from: p, to: a1))
            }
            return best
        }
    }

    /// Whether two stroked primitives overlap, treating both as having the given stroke thickness
    /// (so their center lines must be at least `thickness` apart to be clear of each other).
    static func intersects(
        _ a: Primitive,
        _ b: Primitive,
        thickness: Double = GameRules.strokeThickness,
        sampleSpacing: Double = GameRules.distanceSampleSpacing
    ) -> Bool {
        let ca = a.boundingCircle
        let cb = b.boundingCircle
        // Quick reject: bounding circles too far apart to possibly touch.
        if ca.center.distance(to: cb.center) > ca.radius + cb.radius + thickness {
            return false
        }
        return distance(a, b, sampleSpacing: sampleSpacing) < thickness
    }
}
