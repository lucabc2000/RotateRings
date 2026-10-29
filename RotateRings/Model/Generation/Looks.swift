//
//  Looks.swift
//  RotateRings
//
//  What a board looks like at a glance, as opposed to what its design is called (LEVEL-DESIGN.md
//  §15). The planners keep neighbouring levels in different families, so a stretch of levels does
//  not show the same picture over and over. Derived from the template id, which every report and
//  candidate records.
//

import Foundation

enum Look: String, Codable, CaseIterable, Sendable {
    /// Rings of one size on a rectangular square grid, holes or short bars at most (`Knot`).
    case gridField
    /// The same grid with U-bars linking distant rings (Stronghold).
    case gridBars
    /// Knots and webs on the diagonal grid.
    case diagonal
    /// Boards without a grid: wild knots, gates, thickets, tangles.
    case freeform
    /// Sliding bars in lanes: mazes, cages, workshops (`GridWorld`).
    case barMaze
    /// Symmetric ring figures and weaves (`RingNet`), the bullseye, mirrored free-form knots.
    case figure
    /// Free-form knots grown inside an outline (`Silhouette`): a heart, an arch, an S curve.
    case shaped
    /// A web of closed hubs on a rectangle (`HubWeb`): a grid field with a checkerboard of hubs.
    case hub
    /// A web with an outline of its own (gem, cross, arch, …).
    case hubShape
    /// A big ring as the focal point: giant ring, planet, sun.
    case giant
    /// Picture milestones (later step).
    case picture
    /// Small breather boards (later step).
    case small

    /// The family that counts for "never the same family within three levels": a rectangular web
    /// looks like a grid field.
    var spacing: Look { self == .hub ? .gridField : self }

    private static let outlinedWebs: Set<String> = ["hubs-gem", "hubs-cross", "hubs-arch", "hubs-hourglass", "hubs-heart", "hubs-frame"]

    static func of(template id: String) -> Look {
        let parts = id.split(separator: "-")
        if parts.contains("small") { return .small }
        let kind = parts.first.map(String.init) ?? id
        let mask = parts.count > 1 ? "\(kind)-\(parts[1])" : kind
        switch kind {
        case "hubs":
            if outlinedWebs.contains(mask) { return .hubShape }
            return mask == "hubs-weave" || mask == "hubs-kite" ? .diagonal : .hub
        case "knot":
            if mask == "knot-weave" || mask == "knot-kite" { return .diagonal }
            return parts.contains { $0.hasPrefix("u") && Int($0.dropFirst()) != nil } ? .gridBars : .gridField
        case "free", "dense":
            if parts.contains("sil") { return .shaped }
            return parts.contains("mirror") ? .figure : .freeform
        case "tangle": return .freeform
        case "giant", "planet", "sun": return .giant
        case "maze", "cages": return .barMaze
        case "picture": return .picture
        case "figure", "weave", "bullseye": return .figure
        default: return .figure
        }
    }
}
