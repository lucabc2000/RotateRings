//
//  PieceKind.swift
//  RotateRings
//
//  The six piece types the tutorial introduces, derived from a level file's shape lists. The model
//  itself has no notion of kinds; this is only used by the generator, the difficulty score and the
//  Level Browser.
//

import Foundation

enum PieceKind: String, Codable, CaseIterable, Sendable, Comparable {
    /// A ring with a gap.
    case cRing
    /// A full circle; never releases its own clips.
    case closedRing
    /// A ring with a straight tail segment.
    case tailRing
    /// A turning bar (straight or bent) that carries a clip. A clip owner is pinned, so it never
    /// actually turns: it is a latch that blocks a ring until the ring it grips frees it.
    case latchBar
    /// A bent bar in a fixed metal hub: slides along the hub's axis, never turns.
    case lBar
    /// A straight bar in a fixed metal hub: slides along the hub's axis.
    case slideBar

    var displayName: String {
        switch self {
        case .cRing: "C-ring"
        case .closedRing: "closed ring"
        case .tailRing: "ring with tail"
        case .latchBar: "latch bar"
        case .lBar: "L-bar"
        case .slideBar: "sliding bar"
        }
    }

    static func < (lhs: PieceKind, rhs: PieceKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func classify(_ spec: LevelFile.PieceSpec) -> PieceKind {
        var arcs: [LevelFile.ArcSpec] = []
        var segments = 0
        for shape in spec.shapes {
            switch shape {
            case .arc(let arc): arcs.append(arc)
            case .segment: segments += 1
            }
        }
        if spec.motion == .slide { return segments >= 2 ? .lBar : .slideBar }
        if let ring = arcs.first {
            if segments > 0 { return .tailRing }
            return ring.sweep >= 360 ? .closedRing : .cRing
        }
        return .latchBar
    }

    /// Distinct kinds present in a level, sorted.
    static func kinds(in file: LevelFile) -> [PieceKind] {
        Array(Set(file.pieces.map(classify))).sorted()
    }
}
