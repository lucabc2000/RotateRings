//
//  CollisionTests.swift
//  RotateRingsTests
//

import Foundation
import Testing
@testable import RotateRings

private func deg(_ degrees: Double) -> Double { AngleMath.radians(fromDegrees: degrees) }

struct CollisionTests {
    private let thickness: Double = 10

    @Test func crossingSegmentsHaveZeroDistance() {
        let a = Segment(from: Point(-10, 0), to: Point(10, 0))
        let b = Segment(from: Point(0, -10), to: Point(0, 10))
        #expect(Geometry.segmentsCross(a, b))
        #expect(Geometry.distance(a, b).isApproximately(0))
        #expect(Geometry.intersects(.segment(a), .segment(b), thickness: thickness))
    }

    @Test func parallelSegmentsRespectThickness() {
        let a = Segment(from: Point(0, 0), to: Point(100, 0))
        let near = Segment(from: Point(20, 8), to: Point(80, 8))
        let far = Segment(from: Point(20, 20), to: Point(80, 20))
        #expect(Geometry.distance(a, near).isApproximately(8))
        #expect(Geometry.intersects(.segment(a), .segment(near), thickness: thickness))
        #expect(!Geometry.intersects(.segment(a), .segment(far), thickness: thickness))
    }

    @Test func segmentEndpointNearOtherSegment() {
        // T shape that stops 6 units short of the bar.
        let bar = Segment(from: Point(0, 0), to: Point(100, 0))
        let stem = Segment(from: Point(50, 6), to: Point(50, 60))
        #expect(Geometry.distance(bar, stem).isApproximately(6))
        #expect(Geometry.intersects(.segment(bar), .segment(stem), thickness: thickness))
    }

    @Test func segmentThroughRingGapDoesNotCollide() {
        // Ring with a 80° gap at the bottom (centered on 270°).
        let ring = Arc(center: .zero, radius: 60, start: deg(310), sweep: deg(280))
        let throughGap = Segment(from: Point(0, -120), to: Point(0, -40))
        let throughArc = Segment(from: Point(-120, 0), to: Point(-40, 0))
        #expect(!Geometry.intersects(.arc(ring), .segment(throughGap), thickness: thickness))
        #expect(Geometry.intersects(.arc(ring), .segment(throughArc), thickness: thickness))
    }

    @Test func segmentNearArcEndpoint() {
        let ring = Arc(center: .zero, radius: 60, start: deg(310), sweep: deg(280))
        // Vertical bar just inside the gap edge, 8 units from the arc's end point at 310°.
        let end = ring.endPoint // same as the point at 310° + 280° = 590° = 230°
        let bar = Segment(from: Point(end.x + 8, end.y), to: Point(end.x + 8, end.y - 100))
        let distance = Geometry.distance(.arc(ring), .segment(bar))
        #expect(distance <= 8.5)
        #expect(Geometry.intersects(.arc(ring), .segment(bar), thickness: thickness))
    }

    @Test func concentricArcsKeepTheirSpacing() {
        let outer = Arc(center: .zero, radius: 60, start: 0, sweep: Arc.closedSweep)
        let inner = Arc(center: .zero, radius: 40, start: deg(40), sweep: deg(280))
        let distance = Geometry.distance(.arc(outer), .arc(inner))
        #expect(distance > 19.5 && distance <= 20.0001)
        #expect(!Geometry.intersects(.arc(outer), .arc(inner), thickness: thickness))
    }

    @Test func separateRingsCollideOnlyWhenClose() {
        let a = Arc(center: .zero, radius: 50, start: 0, sweep: Arc.closedSweep)
        let touching = Arc(center: Point(100, 0), radius: 50, start: 0, sweep: Arc.closedSweep)
        let apart = Arc(center: Point(120, 0), radius: 50, start: 0, sweep: Arc.closedSweep)
        #expect(Geometry.intersects(.arc(a), .arc(touching), thickness: thickness))
        #expect(!Geometry.intersects(.arc(a), .arc(apart), thickness: thickness))
        #expect(Geometry.distance(.arc(a), .arc(apart)) > 19.5)
    }

    @Test func gapFacingArcDoesNotTouchNeighbour() {
        // Two C-rings 95 apart whose gaps face each other: the arcs never get closer than the gap edges.
        let left = Arc(center: .zero, radius: 50, start: deg(40), sweep: deg(280))          // gap toward +x
        let right = Arc(center: Point(95, 0), radius: 50, start: deg(220), sweep: deg(280)) // gap toward -x
        #expect(!Geometry.intersects(.arc(left), .arc(right), thickness: thickness))
        // Turning the right ring half way around points its arc at the left ring's gap edges: still clear.
        let halfTurn = Arc(center: right.center, radius: 50, start: deg(40), sweep: deg(280))
        #expect(!Geometry.intersects(.arc(left), .arc(halfTurn), thickness: thickness))
        // Turning the left ring as well makes the two arcs face each other. The circles overlap
        // (radii 50 + 50 > 95), so the arcs actually cross → distance ~0 → collision.
        let leftTurned = Arc(center: .zero, radius: 50, start: deg(220), sweep: deg(280))
        #expect(Geometry.distance(.arc(leftTurned), .arc(halfTurn)) < 0.5)
        #expect(Geometry.intersects(.arc(leftTurned), .arc(halfTurn), thickness: thickness))
    }

    @Test func boundingCircleQuickReject() {
        let a = Primitive.segment(Segment(from: Point(0, 0), to: Point(10, 0)))
        let b = Primitive.arc(Arc(center: Point(1000, 1000), radius: 5, start: 0, sweep: 1))
        #expect(!Geometry.intersects(a, b, thickness: thickness))
    }
}
