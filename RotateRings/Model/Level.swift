//
//  Level.swift
//  RotateRings
//
//  The Codable level file format. Angles in files are degrees (counterclockwise), lengths are board
//  units, and every piece's shapes are in local coordinates with the rotation pivot at the origin.
//

import Foundation

struct LevelFile: Codable, Equatable, Sendable {
    struct BoardSize: Codable, Equatable, Sendable {
        var width: Double
        var height: Double
    }

    struct ArcSpec: Codable, Equatable, Sendable {
        var center: Point
        var radius: Double
        /// Start angle in degrees.
        var start: Double
        /// Counterclockwise extent in degrees. 360 makes a closed ring.
        var sweep: Double
    }

    struct SegmentSpec: Codable, Equatable, Sendable {
        var from: Point
        var to: Point
    }

    /// Either `{"arc": {...}}` or `{"segment": {...}}`.
    enum ShapeSpec: Codable, Equatable, Sendable {
        case arc(ArcSpec)
        case segment(SegmentSpec)

        private enum CodingKeys: String, CodingKey {
            case arc, segment
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let arc = try container.decodeIfPresent(ArcSpec.self, forKey: .arc) {
                self = .arc(arc)
            } else if let segment = try container.decodeIfPresent(SegmentSpec.self, forKey: .segment) {
                self = .segment(segment)
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "A shape must contain either an \"arc\" or a \"segment\" key."
                ))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .arc(let arc): try container.encode(arc, forKey: .arc)
            case .segment(let segment): try container.encode(segment, forKey: .segment)
            }
        }
    }

    struct ClipSpec: Codable, Equatable, Sendable {
        var stemStart: Point
        var stemEnd: Point
        /// ID of the ring this clip grips.
        var grips: String?
    }

    /// A piece. Two kinds of motion:
    /// - `"rotation"` (default): the piece turns around `position`. Rings, tails and clip latches.
    /// - `"slide"`: a bar in a fixed metal hub. `position` is the hub, `rotation` is the hub's axis in
    ///   degrees, and the shape segment lying on the local x axis is the arm that runs through the hub.
    ///   The whole piece (bent arms included) slides along that axis and never turns; a bent arm stops
    ///   at the hub, and the bar is free once its arm has left the hub.
    struct PieceSpec: Codable, Equatable, Sendable {
        var id: String
        var color: String?
        /// `"rotation"` (default) or `"slide"`.
        var motion: Piece.Motion?
        /// World position of the pivot, or of the hub for a sliding piece.
        var position: Point
        /// Initial rotation in degrees. For a sliding piece this is the hub's axis.
        var rotation: Double?
        var shapes: [ShapeSpec]
        var clips: [ClipSpec]?
    }

    var id: Int
    var name: String
    var board: BoardSize
    var pieces: [PieceSpec]
}

enum LevelError: Error, LocalizedError, Equatable {
    case duplicatePieceID(String)
    case unknownGripTarget(piece: String, target: String)
    case gripTargetHasNoRing(piece: String, target: String)
    case clipNotOnRing(piece: String, clipIndex: Int, target: String)
    case emptyPiece(String)
    case invalidArc(piece: String)
    case fileNotFound(level: Int)
    case resourceNotFound(String)
    case slideBarWithoutAxialArm(piece: String)
    case slideBarOutsideHub(piece: String)
    case turningBarWithoutClip(piece: String)

    var errorDescription: String? {
        switch self {
        case .duplicatePieceID(let id):
            return "Duplicate piece id \"\(id)\"."
        case .unknownGripTarget(let piece, let target):
            return "Piece \"\(piece)\" grips unknown piece \"\(target)\"."
        case .gripTargetHasNoRing(let piece, let target):
            return "Piece \"\(piece)\" grips \"\(target)\", which has no ring arc."
        case .clipNotOnRing(let piece, let clipIndex, let target):
            return "Clip \(clipIndex) of piece \"\(piece)\" does not sit on the arc of \"\(target)\"."
        case .emptyPiece(let id):
            return "Piece \"\(id)\" has no shapes."
        case .invalidArc(let piece):
            return "Piece \"\(piece)\" has an arc with a non-positive radius or sweep."
        case .fileNotFound(let level):
            return "Level \(level) was not found in the bundle."
        case .resourceNotFound(let name):
            return "Resource \(name) was not found in the bundle."
        case .slideBarWithoutAxialArm(let piece):
            return "Sliding piece \"\(piece)\" has no segment on its local x axis to run through the hub."
        case .slideBarOutsideHub(let piece):
            return "Sliding piece \"\(piece)\" does not start inside its hub."
        case .turningBarWithoutClip(let piece):
            return "Piece \"\(piece)\" is a bar without a hub or a clip; bars either slide in a hub or latch onto a ring."
        }
    }
}

extension LevelFile {
    /// Validates the level and converts it into a model `Board`.
    func makeBoard() throws -> Board {
        var seen = Set<String>()
        for spec in pieces {
            guard seen.insert(spec.id).inserted else { throw LevelError.duplicatePieceID(spec.id) }
            guard !spec.shapes.isEmpty else { throw LevelError.emptyPiece(spec.id) }
        }

        let modelPieces = try pieces.map { spec -> Piece in
            let shapes: [Primitive] = try spec.shapes.map { shape in
                switch shape {
                case .arc(let arc):
                    guard arc.radius > 0, arc.sweep > 0 else { throw LevelError.invalidArc(piece: spec.id) }
                    return .arc(Arc(
                        center: arc.center,
                        radius: arc.radius,
                        start: AngleMath.radians(fromDegrees: arc.start),
                        sweep: min(Arc.closedSweep, AngleMath.radians(fromDegrees: arc.sweep))
                    ))
                case .segment(let segment):
                    return .segment(Segment(from: segment.from, to: segment.to))
                }
            }

            let clips: [Clip] = try (spec.clips ?? []).map { clip in
                if let target = clip.grips {
                    guard let targetSpec = pieces.first(where: { $0.id == target }) else {
                        throw LevelError.unknownGripTarget(piece: spec.id, target: target)
                    }
                    let hasRing = targetSpec.shapes.contains { if case .arc = $0 { return true } else { return false } }
                    guard hasRing else { throw LevelError.gripTargetHasNoRing(piece: spec.id, target: target) }
                }
                return Clip(stemStart: clip.stemStart, stemEnd: clip.stemEnd, grips: clip.grips)
            }

            return Piece(
                id: spec.id,
                color: spec.color ?? "coral",
                motion: spec.motion ?? .rotation,
                position: spec.position,
                rotation: AngleMath.radians(fromDegrees: spec.rotation ?? 0),
                shapes: shapes,
                clips: clips
            )
        }

        for piece in modelPieces {
            if piece.motion == .slide {
                guard piece.axialArm != nil else { throw LevelError.slideBarWithoutAxialArm(piece: piece.id) }
                guard Board.isInHolder(piece) else { throw LevelError.slideBarOutsideHub(piece: piece.id) }
            } else if piece.ringArc == nil && piece.clips.isEmpty {
                throw LevelError.turningBarWithoutClip(piece: piece.id)
            }
        }

        // Every gripping clip must actually sit on its target ring's circle.
        for piece in modelPieces {
            for (index, clip) in piece.clips.enumerated() {
                guard let target = clip.grips,
                      let ring = modelPieces.first(where: { $0.id == target }),
                      let arc = ring.worldRingArc() else { continue }
                let grip = piece.worldGripPoint(clipIndex: index)
                if abs(grip.distance(to: arc.center) - arc.radius) > GameRules.clipHoldTolerance {
                    throw LevelError.clipNotOnRing(piece: piece.id, clipIndex: index, target: target)
                }
            }
        }

        return Board(pieces: modelPieces)
    }
}
