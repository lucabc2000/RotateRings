//
//  GeometryTests.swift
//  RotateRingsTests
//

import Foundation
import Testing
@testable import RotateRings

private func deg(_ degrees: Double) -> Double { AngleMath.radians(fromDegrees: degrees) }

struct GeometryTests {

    @Test func angleNormalization() {
        #expect(AngleMath.normalized(deg(370)).isApproximately(deg(10)))
        #expect(AngleMath.normalized(deg(-90)).isApproximately(deg(270)))
        #expect(AngleMath.normalized(deg(360)).isApproximately(0))
        #expect(AngleMath.difference(deg(350), deg(10)).isApproximately(deg(20)))
    }

    @Test func pointTransforms() {
        let p = Point(10, 0)
        let rotated = p.rotated(by: deg(90))
        #expect(rotated.x.isApproximately(0))
        #expect(rotated.y.isApproximately(10))

        let world = p.transformed(rotation: deg(180), translation: Point(100, 50))
        #expect(world.x.isApproximately(90))
        #expect(world.y.isApproximately(50))
    }

    @Test func pointCodesAsArray() throws {
        let data = try JSONEncoder().encode(Point(3, -4))
        #expect(String(decoding: data, as: UTF8.self) == "[3,-4]")
        let decoded = try JSONDecoder().decode(Point.self, from: Data("[1.5, 2]".utf8))
        #expect(decoded == Point(1.5, 2))
    }

    @Test func arcAngularContainmentAndGap() throws {
        // Covers 130° → 410°, so the gap is 50° → 130°, centered on 90°.
        let arc = Arc(center: .zero, radius: 50, start: deg(130), sweep: deg(280))
        #expect(arc.contains(angle: deg(180)))
        #expect(arc.contains(angle: deg(0)))
        #expect(arc.contains(angle: deg(45)))
        #expect(!arc.contains(angle: deg(90)))
        #expect(!arc.isClosed)

        let gap = try #require(arc.gap)
        #expect(gap.contains(deg(90)))
        #expect(gap.contains(deg(60)))
        #expect(!gap.contains(deg(60), margin: deg(15)))
        #expect(!gap.contains(deg(180)))
        #expect(AngleMath.normalized(gap.mid).isApproximately(deg(90)))
    }

    @Test func closedArcHasNoGap() {
        let ring = Arc(center: .zero, radius: 40, start: 0, sweep: Arc.closedSweep)
        #expect(ring.isClosed)
        #expect(ring.gap == nil)
        #expect(ring.contains(angle: deg(123)))
    }

    @Test func arcTransform() {
        let arc = Arc(center: Point(10, 0), radius: 5, start: 0, sweep: deg(90))
        let moved = arc.transformed(rotation: deg(90), translation: Point(100, 100))
        #expect(moved.center.x.isApproximately(100))
        #expect(moved.center.y.isApproximately(110))
        #expect(moved.start.isApproximately(deg(90)))
        #expect(moved.sweep.isApproximately(deg(90)))
    }

    @Test func pointToSegmentDistance() {
        let segment = Segment(from: Point(0, 0), to: Point(10, 0))
        #expect(Geometry.distance(from: Point(5, 3), to: segment).isApproximately(3))
        #expect(Geometry.distance(from: Point(-4, 0), to: segment).isApproximately(4))
        #expect(Geometry.distance(from: Point(13, 4), to: segment).isApproximately(5))
        let point = Segment(from: Point(1, 1), to: Point(1, 1))
        #expect(Geometry.distance(from: Point(4, 5), to: point).isApproximately(5))
    }

    @Test func pointToArcDistance() {
        // Right half circle: -90° → 90°.
        let arc = Arc(center: .zero, radius: 10, start: deg(-90), sweep: deg(180))
        #expect(Geometry.distance(from: Point(13, 0), to: arc).isApproximately(3))
        #expect(Geometry.distance(from: Point(4, 0), to: arc).isApproximately(6))
        // Behind the arc: the closest points are the endpoints (0, ±10).
        #expect(Geometry.distance(from: Point(-10, 10), to: arc).isApproximately(10))
    }

    @Test func clipPrimitivesFormStemAndSquare() {
        let clip = Clip(stemStart: Point(0, -50), stemEnd: Point(0, -70), grips: "x")
        let primitives = clip.primitives(squareSize: 16)
        #expect(primitives.count == 3)
        guard case .segment(let stem) = primitives[0] else { Issue.record("expected stem"); return }
        #expect(stem.from == Point(0, -50))
        #expect(stem.to == Point(0, -70))
        guard case .segment(let across) = primitives[2] else { Issue.record("expected crossbar"); return }
        #expect(across.length.isApproximately(16))
        #expect(across.midpoint.y.isApproximately(-70))
    }
}

extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 1e-6) -> Bool {
        abs(self - other) <= tolerance
    }
}
