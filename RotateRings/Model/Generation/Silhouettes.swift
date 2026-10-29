//
//  Silhouettes.swift
//  RotateRings
//
//  Outlines a free-form knot can grow inside (`FreeKnot.Options.silhouette`, LEVEL-DESIGN.md §15).
//  A silhouette is data: shapes that add room and shapes that cut it away again, each a circle, a
//  polygon or a capsule (a thick line). Coordinates are in half board widths from the centre, x to
//  the right and y up, so a shape keeps its proportions on every board: x runs from -1 to 1 and y
//  from about -1.9 to 1.9 on the standard board. To add a shape, add an entry to `all`.
//

import Foundation

struct Silhouette {
    enum Part {
        case circle(center: Point, radius: Double)
        /// Corners in order; the polygon may be concave.
        case polygon([Point])
        /// Every point within `radius` of the polyline through `points`.
        case capsule([Point], radius: Double)

        func contains(_ p: Point) -> Bool {
            switch self {
            case .circle(let center, let radius):
                return p.distance(to: center) <= radius
            case .polygon(let corners):
                var inside = false
                var j = corners.count - 1
                for i in corners.indices {
                    let a = corners[i], b = corners[j]
                    if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
                    j = i
                }
                return inside
            case .capsule(let points, let radius):
                return zip(points, points.dropFirst()).contains { Geometry.distance(from: p, to: Segment(from: $0, to: $1)) <= radius }
            }
        }
    }

    var name: String
    var add: [Part]
    var cut: [Part] = []

    /// Whether the board point `p` (relative to the board's centre) is inside, on a board whose
    /// half width inside the margins is `unit`.
    func contains(_ p: Point, unit: Double) -> Bool {
        let q = Point(p.x / unit, p.y / unit)
        return add.contains { $0.contains(q) } && !cut.contains { $0.contains(q) }
    }

    /// Left-right symmetric, so a mirrored knot can use it.
    var isSymmetric: Bool

    static let all: [String: Silhouette] = {
        func p(_ x: Double, _ y: Double) -> Point { Point(x, y) }
        /// A point on a circle, angle in degrees.
        func on(_ center: Point, _ radius: Double, _ degrees: Double) -> Point {
            let a = degrees * .pi / 180
            return Point(center.x + radius * cos(a), center.y + radius * sin(a))
        }
        let list = [
            Silhouette(name: "circle", add: [.circle(center: p(0, 0), radius: 1)], isSymmetric: true),
            Silhouette(name: "donut", add: [.circle(center: p(0, 0), radius: 1)], cut: [.circle(center: p(0, 0), radius: 0.36)], isSymmetric: true),
            // Two half rings joined at the middle, as one thick line.
            Silhouette(name: "scurve", add: [.capsule(stride(from: 90.0, through: 360, by: 15).map { on(p(0, 0.75), 0.62, $0) }
                                                      + stride(from: 180.0, through: 450, by: 15).map { on(p(0, -0.75), 0.62, -$0) },
                                                      radius: 0.36)], isSymmetric: false),
            Silhouette(name: "crescent", add: [.circle(center: p(0, 0), radius: 1)], cut: [.circle(center: p(0.55, 0.2), radius: 0.78)], isSymmetric: false),
            Silhouette(name: "heart", add: [.circle(center: p(-0.48, 0.6), radius: 0.52), .circle(center: p(0.48, 0.6), radius: 0.52),
                                            .polygon([p(-0.98, 0.5), p(0.98, 0.5), p(0, -1.45)])], isSymmetric: true),
            Silhouette(name: "diamond", add: [.polygon([p(0, 1.8), p(1, 0), p(0, -1.8), p(-1, 0)])], isSymmetric: true),
            Silhouette(name: "arch", add: [.circle(center: p(0, 0.5), radius: 1), .polygon([p(-1, 0.5), p(1, 0.5), p(1, -1.75), p(-1, -1.75)])],
                       cut: [.circle(center: p(0, 0.5), radius: 0.4), .polygon([p(-0.4, 0.5), p(0.4, 0.5), p(0.4, -1.75), p(-0.4, -1.75)])],
                       isSymmetric: true),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
    }()
}
