//
//  Piece.swift
//  RotateRings
//

import Foundation

/// Identifies which part of a piece a world primitive came from.
enum PrimitiveSource: Hashable, Sendable {
    /// Index into `Piece.shapes`.
    case body(Int)
    /// Index into `Piece.clips`.
    case clip(Int)
}

/// A primitive placed in board space, tagged with its origin.
struct WorldPrimitive: Hashable, Sendable {
    let primitive: Primitive
    let source: PrimitiveSource
}

/// A generic board piece: a list of shape primitives, a pivot, an optional gap (implied by a ring arc
/// with a sweep below 2π) and clips. All local coordinates are relative to the pivot at the origin.
struct Piece: Identifiable, Hashable, Sendable {
    typealias ID = String

    /// How the player moves the piece.
    enum Motion: String, Hashable, Sendable, Codable {
        /// Turns around the pivot at the local origin.
        case rotation
        /// Slides along its local x axis through a fixed holder at the local origin. `rotation` is
        /// fixed and only sets the direction of the axis.
        case slide
    }

    let id: ID
    /// Palette name used by the renderer.
    let color: String
    let motion: Motion
    /// World position of the pivot (rotation) or of the holder (slide).
    var position: Point
    /// Current rotation around the pivot, radians, counterclockwise positive.
    var rotation: Double
    /// Rotation the piece started with.
    let baseRotation: Double
    /// Distance the piece has slid along its axis from its starting place (slide motion only).
    var offset: Double = 0
    /// Body primitives in local space.
    let shapes: [Primitive]
    let clips: [Clip]

    init(id: ID, color: String = "coral", motion: Motion = .rotation, position: Point, rotation: Double = 0, shapes: [Primitive], clips: [Clip] = []) {
        self.id = id
        self.color = color
        self.motion = motion
        self.position = position
        self.rotation = rotation
        self.baseRotation = rotation
        self.shapes = shapes
        self.clips = clips
    }

    /// The value the player changes: rotation or slide offset, depending on `motion`.
    var movement: Double {
        get { motion == .slide ? offset : rotation }
        set {
            if motion == .slide { offset = newValue } else { rotation = newValue }
        }
    }

    // MARK: Placement

    /// World direction a sliding piece moves along.
    var slideAxis: Point { Point(1, 0).rotated(by: rotation) }

    /// World position of the local origin after sliding.
    var translation: Point {
        motion == .slide ? position + slideAxis * offset : position
    }

    // MARK: Ring

    /// Index of the arc that acts as this piece's ring (the first arc in `shapes`), if any.
    var ringArcIndex: Int? {
        shapes.firstIndex { if case .arc = $0 { return true } else { return false } }
    }

    var ringArc: Arc? {
        guard let index = ringArcIndex, case .arc(let arc) = shapes[index] else { return nil }
        return arc
    }

    /// The ring arc in world space.
    func worldRingArc() -> Arc? {
        ringArc?.transformed(rotation: rotation, translation: translation)
    }

    // MARK: Hub

    /// Only sliding pieces have a hub: the fixed metal sleeve at `position` that the arm on the local
    /// x axis runs through. Turning pieces never show one.
    var hasHub: Bool { motion == .slide }

    /// The arm of a sliding piece that runs through its hub: the body segment lying on the local x axis.
    var axialArm: Segment? {
        for shape in shapes {
            if case .segment(let segment) = shape, Self.isAxial(segment) { return segment }
        }
        return nil
    }

    /// Whether a local segment lies on the x axis (the hub axis).
    static func isAxial(_ segment: Segment) -> Bool {
        abs(segment.from.y) < 0.5 && abs(segment.to.y) < 0.5
    }

    // MARK: World geometry

    /// World position of the grip point of clip `index`.
    func worldGripPoint(clipIndex index: Int) -> Point {
        clips[index].gripPoint.transformed(rotation: rotation, translation: translation)
    }

    /// All collision primitives (body and clips) in world space.
    func worldPrimitives() -> [WorldPrimitive] {
        let origin = translation
        var result: [WorldPrimitive] = []
        result.reserveCapacity(shapes.count + clips.count * 3)
        for (index, shape) in shapes.enumerated() {
            result.append(WorldPrimitive(primitive: shape.transformed(rotation: rotation, translation: origin), source: .body(index)))
        }
        for (index, clip) in clips.enumerated() {
            for primitive in clip.primitives() {
                result.append(WorldPrimitive(primitive: primitive.transformed(rotation: rotation, translation: origin), source: .clip(index)))
            }
        }
        return result
    }

    /// Distance from a world point to the nearest part of this piece.
    func distance(to point: Point) -> Double {
        worldPrimitives().reduce(Double.infinity) { best, wp in
            min(best, Geometry.distance(from: point, to: wp.primitive))
        }
    }
}
