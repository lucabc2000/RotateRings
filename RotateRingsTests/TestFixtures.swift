//
//  TestFixtures.swift
//  RotateRingsTests
//
//  Helpers shared by the board, solver and generator tests.
//

import Foundation
@testable import RotateRings

let clockwiseStep = -AngleMath.radians(fromDegrees: 45)

/// Helpers to build pieces tersely. (Each test file keeps its own private `deg` helper.)
enum Make {
    /// C-ring with an 80° gap centered on `gapCenterDegrees`.
    static func ring(_ id: String, at position: Point, radius: Double = 50, gapCenterDegrees: Double, clips: [Clip] = []) -> Piece {
        let start = AngleMath.radians(fromDegrees: gapCenterDegrees + 40)
        return Piece(id: id, position: position, shapes: [.arc(Arc(center: .zero, radius: radius, start: start, sweep: AngleMath.radians(fromDegrees: 280)))], clips: clips)
    }

    static func closedRing(_ id: String, at position: Point, radius: Double, clips: [Clip] = []) -> Piece {
        Piece(id: id, position: position, shapes: [.arc(Arc(center: .zero, radius: radius, start: 0, sweep: Arc.closedSweep))], clips: clips)
    }

    /// Clip pointing straight down from the bottom of a radius-50 ring.
    static func downClip(grips: String) -> Clip {
        Clip(stemStart: Point(0, -50), stemEnd: Point(0, -70), grips: grips)
    }

    /// Clip pointing straight up from the top of a radius-50 ring.
    static func upClip(grips: String) -> Clip {
        Clip(stemStart: Point(0, 50), stemEnd: Point(0, 70), grips: grips)
    }

    /// Clip pointing left from the left side of a radius-50 ring.
    static func leftClip(grips: String) -> Clip {
        Clip(stemStart: Point(-50, 0), stemEnd: Point(-70, 0), grips: grips)
    }

    /// Ring `b` at the origin, gap on the left. Ring `a` above it grips `b`'s top point (angle 90°).
    static func twoRingBoard() -> Board {
        let a = ring("a", at: Point(0, 120), gapCenterDegrees: 90, clips: [downClip(grips: "b")])
        let b = ring("b", at: .zero, gapCenterDegrees: 180)
        return Board(pieces: [a, b])
    }
}
