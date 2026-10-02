//
//  Clip.swift
//  RotateRings
//

import Foundation

/// A small square on a short stem, attached to a piece's body, that grips the arc of another ring.
/// Coordinates are in the owning piece's local space (pivot at the origin).
struct Clip: Hashable, Sendable {
    /// Where the stem leaves the owner's body.
    var stemStart: Point
    /// Center of the square. The gripped ring's arc passes through this point.
    var stemEnd: Point
    /// ID of the ring piece this clip grips, or `nil` for a loose clip.
    var grips: String?

    var gripPoint: Point { stemEnd }

    /// Collision primitives of the clip: the stem plus two crossed bars approximating the square.
    func primitives(squareSize: Double = GameRules.clipSize) -> [Primitive] {
        let direction = (stemEnd - stemStart).normalized()
        let half = squareSize / 2
        let along = direction * half
        let across = direction.perpendicular * half
        return [
            .segment(Segment(from: stemStart, to: stemEnd)),
            .segment(Segment(from: stemEnd - along, to: stemEnd + along)),
            .segment(Segment(from: stemEnd - across, to: stemEnd + across)),
        ]
    }
}
