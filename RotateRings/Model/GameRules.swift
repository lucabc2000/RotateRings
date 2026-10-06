//
//  GameRules.swift
//  RotateRings
//
//  Tunable constants shared by the model and the renderer.
//

import Foundation

enum GameRules {
    /// Pieces rotate freely under the finger and stay where they are released. This step is the unit
    /// used by `Board.rotate(_:bySteps:)` for scripted moves (tests, level walkthroughs).
    static let rotationStepDegrees: Double = 45
    static var rotationStep: Double { AngleMath.radians(fromDegrees: rotationStepDegrees) }

    /// A finger closer than this to a piece's pivot has no usable angle; such moves are ignored.
    static let dragDeadZone: Double = 18

    /// Length (along the bar) of the fixed metal hub a sliding bar passes through. The bar is free once
    /// no part of its arm is within half this length of the hub's center.
    static let holderLength: Double = 36
    /// Distance between samples when checking a slide for collisions.
    static let slideSampleDistance: Double = 2
    /// A bent arm of a sliding bar stops when it comes this close to its hub's center: the hub's
    /// radius plus half a stroke. Only the arm that runs through the hub may pass it.
    static var hubClearance: Double { hubRadius + strokeThickness / 2 }

    /// Stroke width of every piece. Two center lines closer than this are a collision.
    static let strokeThickness: Double = 10
    /// Two body strokes with center lines closer than this are touching. A piece with no connection
    /// stays on the board as long as it touches something; it leaves the moment it is clear.
    static let touchDistance: Double = 16
    /// Side length of the square at the end of a clip stem.
    static let clipSize: Double = 16
    /// Radius of a bomb's body. It goes off when its edge comes within a stroke's edge of another
    /// piece, so the distance from its centre to that piece's centre line is `bombRadius +
    /// strokeThickness / 2`.
    static let bombRadius: Double = 12
    static var bombReach: Double { bombRadius + strokeThickness / 2 }
    /// Half the width of the hub's slot, measured from the axis: how close a bent arm may come to the
    /// hub's center before it is stopped (see `hubClearance`).
    static let hubRadius: Double = 9

    /// Angular resolution of the rotation sweep used for collision checks.
    static let sweepSampleDegrees: Double = 1.5
    static var sweepSampleStep: Double { AngleMath.radians(fromDegrees: sweepSampleDegrees) }
    /// Spacing of the points sampled along arcs and segments when measuring distances.
    static let distanceSampleSpacing: Double = 4

    /// How far a clip's grip point may stray from the gripped ring's circle before the ring is
    /// considered to be holding the clip owner back.
    static let clipHoldTolerance: Double = 2

    /// How close (in board units) a tap must be to a piece's stroke to select it.
    static let tapPickRadius: Double = 28
}
