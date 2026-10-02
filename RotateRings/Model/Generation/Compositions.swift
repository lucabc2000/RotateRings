//
//  Compositions.swift
//  RotateRings
//
//  The whole-board designs of the curve levels (16–50) and the plan that hands them out. Each level
//  belongs to one genre, and neighbouring levels never share one:
//
//  - figure: rings laid out as a symmetric shape on a square grid (`RingNet`);
//  - weave: the same on a diagonal grid, every clip at 45°;
//  - threaded: a ring figure with holes, and sliding bars in the holes that lock rings;
//  - maze: nothing but sliding bars, packed so they block each other's way out (`GridWorld`);
//  - cages: rings pinned by T-bars in a grid, with bars in the lanes between them; with only some
//    of the cages filled in, a workshop of bars around a few rings;
//  - showcase (every fifth level): the sun, or the largest board of one of the genres above.
//

import Foundation

enum Compositions {

    // MARK: Ring figures

    private static func shape(_ template: String, _ name: String, _ layout: RingNet.Layout, radius: Double, stem: Double, _ rows: [String]) -> RingNet.Shape {
        RingNet.Shape(name: name, template: template, layout: layout, radius: radius, stem: stem, rows: rows)
    }

    /// Ring figures by template id. Square figures come in three ring sizes (three big or medium
    /// rings across, or four small ones); diagonal figures in two. Stems are longer than
    /// `GameRules.touchDistance`, so a freed ring is never held back by a neighbour it only sits next to.
    static let shapes: [String: RingNet.Shape] = {
        let list: [RingNet.Shape] = [
            // Square, three medium rings across.
            shape("figure-block", "Block", .square, radius: 40, stem: 20, ["###", "###", "###"]),
            shape("figure-window", "Window", .square, radius: 40, stem: 20, ["###", "#o#", "###"]),
            shape("figure-totem", "Totem", .square, radius: 40, stem: 20, ["#o#", "###", "###", "#o#"]),
            shape("figure-hourglass", "Hourglass", .square, radius: 40, stem: 20, ["###", "o#o", "###", "o#o", "###"]),
            shape("figure-pillars", "Pillars", .square, radius: 40, stem: 20, ["#o#", "#o#", "###", "#o#", "#o#"]),
            shape("figure-frame", "Frame", .square, radius: 40, stem: 20, ["###", "#o#", "#o#", "#o#", "###"]),
            shape("figure-spine", "Spine", .square, radius: 40, stem: 20, ["o#o", "###", "o#o", "###", "o#o"]),
            // Square, three big rings across.
            shape("figure-grand", "Grand", .square, radius: 44, stem: 18, ["###", "###", "###", "###"]),
            shape("figure-tower", "Tower", .square, radius: 44, stem: 18, ["###", "###", "###", "###", "###"]),
            shape("figure-goblet", "Goblet", .square, radius: 44, stem: 18, ["###", "###", "o#o", "o#o", "###"]),
            // Square, four small rings across.
            shape("figure-diamond", "Diamond", .square, radius: 30, stem: 20, ["o##o", "####", "####", "o##o"]),
            shape("figure-border", "Border", .square, radius: 30, stem: 20, ["####", "#oo#", "#oo#", "#oo#", "####"]),
            shape("figure-tree", "Tree", .square, radius: 30, stem: 20, ["o##o", "o##o", "####", "####", "####"]),
            shape("figure-waist", "Waist", .square, radius: 30, stem: 20, ["####", "####", "o##o", "o##o", "####", "####"]),
            shape("figure-gate", "Gate", .square, radius: 30, stem: 20, ["####", "#oo#", "#oo#", "####", "#oo#", "####"]),
            shape("figure-castle", "Castle", .square, radius: 30, stem: 20, ["#oo#", "####", "#oo#", "####", "#oo#", "####", "#oo#"]),
            // Diagonal, small rings, five columns.
            shape("weave-diamond", "Diamond weave", .diagonal, radius: 32, stem: 18, ["..#..", ".#.#.", "#.#.#", ".#.#.", "..#.."]),
            shape("weave-cross", "Cross weave", .diagonal, radius: 32, stem: 18, ["#.o.#", ".#.#.", "o.#.o", ".#.#.", "#.o.#"]),
            shape("weave-hexagon", "Honeycomb", .diagonal, radius: 32, stem: 18, ["..#..", ".#.#.", "#.o.#", ".#.#.", "#.o.#", ".#.#.", "..#.."]),
            shape("weave-kite", "Kite", .diagonal, radius: 32, stem: 18, ["..#..", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "..#.."]),
            shape("weave-butterfly", "Butterfly", .diagonal, radius: 32, stem: 18, ["#.o.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.o.#"]),
            shape("weave-lantern", "Lantern", .diagonal, radius: 32, stem: 18, ["..#..", ".#.#.", "#.#.#", ".#.#.", "o.#.o", ".#.#.", "#.#.#", ".#.#.", "..#.."]),
            shape("weave-crystal", "Crystal", .diagonal, radius: 32, stem: 18, ["..#..", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "..#.."]),
            shape("weave-tapestry", "Tapestry", .diagonal, radius: 32, stem: 18, ["#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#"]),
            // Diagonal, big rings, three columns.
            shape("weave-braid", "Braid", .diagonal, radius: 45, stem: 18, ["#.#", ".#.", "#.#", ".#.", "#.#", ".#.", "#.#"]),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.template, $0) })
    }()

    /// A ring figure centred on the board. With `tails` it is a hard one: tails lock leaves, and
    /// threaded bars are more often stopped by the ring across their hole.
    static func net(_ shapeID: String, lock: ClosedRange<Int>, mirrored: Bool = true, crossClips: Int = 0, bars: Int = 0,
                    tails: Int = 0, anchorChance: Double = 0.4) -> LevelTemplate {
        let shape = shapes[shapeID]!
        var options = RingNet.Options()
        options.mirrored = mirrored
        options.crossClips = crossClips
        options.bars = bars
        options.tails = tails
        if tails > 0 { options.blockedBarChance = 0.7 }
        options.anchorChance = anchorChance
        options.lockRange = lock
        var kinds: Set<PieceKind> = [.cRing, .closedRing]
        if bars > 0 { kinds.insert(.slideBar) }
        if tails > 0 { kinds.insert(.tailRing) }
        return LevelTemplate.single(shapeID + (tails > 0 ? "-tails" : ""), kinds: kinds) { rng in RingNet.build(shape, options: options, rng: &rng) }
    }

    // MARK: Grids

    /// Sliding bars only. Small mazes use wider lanes so they still fill the board. With `freeLimit`
    /// no more than that many bars are free at a time while the maze is built.
    static func maze(cols: Int, rows: Int, bars: Int, elbowChance: Double = 0.45, freeLimit: Int? = nil) -> LevelTemplate {
        let id = "maze-\(cols)x\(rows)" + (freeLimit == nil ? "" : "-tight")
        let pitch = min(40, (GridWorld.maxWidth / Double(cols - 1)).rounded(.down), (GridWorld.maxHeight / Double(rows - 1)).rounded(.down))
        return LevelTemplate(id: id, kinds: [.slideBar, .lBar]) { _, rng in
            var plan = GridWorld.Plan(name: "Gridlock", template: id, cols: cols, rows: rows, bars: bars, elbowChance: elbowChance)
            plan.pitch = pitch
            plan.freeLimit = freeLimit
            return GridWorld.build(plan, rng: &rng)
        }
    }

    /// Caged rings with bars in the lanes. `count` of the `across` × `down` slots hold a cage.
    static func cages(across: Int, down: Int, count: Int? = nil, lanes: Int = 1, border: Int, bars: Int, elbowChance: Double = 0.4,
                      freeLimit: Int? = nil) -> LevelTemplate {
        let filled = count ?? across * down
        let id = "cages-\(across)x\(down)" + (filled < across * down ? "-\(filled)" : "") + (freeLimit == nil ? "" : "-tight")
        return LevelTemplate(id: id, kinds: [.cRing, .latchBar, .slideBar, .lBar]) { _, rng in
            var plan = GridWorld.cagePlan(name: filled < across * down ? "Workshop" : "Cages", template: id, across: across, down: down,
                                          count: filled, lanes: lanes, border: border, bars: bars, elbowChance: elbowChance, rng: &rng)
            plan.freeLimit = freeLimit
            return GridWorld.build(plan, rng: &rng)
        }
    }

    // MARK: Showcase

    static func sun(lock: ClosedRange<Int>) -> LevelTemplate {
        LevelTemplate.single("sun", kinds: [.closedRing, .cRing, .slideBar, .lBar]) { rng in Motifs.sun(lockRange: lock, rng: &rng) }
    }

    /// The sun with two moons side by side above or below it.
    static func sunAndMoons(lock: ClosedRange<Int>) -> LevelTemplate {
        LevelTemplate.stack("sun-moons", name: "Sun and moons", kinds: [.closedRing, .cRing, .slideBar, .lBar]) { rng in
            guard let sun = Motifs.sun(lockRange: lock, rng: &rng),
                  let first = Motifs.concentric(withSatellite: false, lockRange: lock, rng: &rng),
                  let second = Motifs.concentric(withSatellite: false, lockRange: lock, rng: &rng) else { return nil }
            return [sun, first, second]
        }
    }


    // MARK: Plan

    /// Levels built to be hard: few pieces are free at any time, so the player has to trace what
    /// holds what. They alternate with easier levels, and the sun showcases stay easy.
    static let hardLevels: Set<Int> = [22, 25, 27, 30, 32, 34, 35, 37, 39, 42, 44, 45, 47, 49, 50]

    /// The designs level `level` (16–50) may be built from.
    static func templates(level: Int) -> [LevelTemplate] {
        let lock = level < 30 ? 1...3 : 1...4
        switch level {
        case 16: return [net("figure-block", lock: lock), net("figure-window", lock: lock, bars: 1)]
        case 17: return [maze(cols: 7, rows: 9, bars: 9), maze(cols: 8, rows: 8, bars: 10)]
        case 18: return [net("weave-diamond", lock: lock), net("weave-cross", lock: lock, bars: 1)]
        case 19: return [cages(across: 2, down: 2, lanes: 2, border: 1, bars: 6)]
        case 20: return [sun(lock: lock)]
        case 21: return [net("figure-hourglass", lock: lock, bars: 2), net("figure-pillars", lock: lock, bars: 1), net("figure-totem", lock: lock, bars: 1)]
        case 22: return [maze(cols: 9, rows: 10, bars: 12, freeLimit: 2), maze(cols: 8, rows: 11, bars: 12, freeLimit: 2)]
        case 23: return [net("weave-hexagon", lock: lock, mirrored: false, bars: 2), net("weave-kite", lock: lock)]
        case 24: return [cages(across: 2, down: 3, count: 3, lanes: 2, border: 1, bars: 8)]
        case 25: return [net("figure-grand", lock: lock, crossClips: 1, tails: 3)]
        case 26: return [net("figure-frame", lock: lock, bars: 1), net("figure-spine", lock: lock, bars: 2)]
        case 27: return [cages(across: 2, down: 3, lanes: 2, border: 1, bars: 9, freeLimit: 3)]
        case 28: return [maze(cols: 10, rows: 12, bars: 16)]
        case 29: return [net("figure-diamond", lock: lock, bars: 2), net("figure-border", lock: lock, bars: 2)]
        case 30: return [cages(across: 3, down: 3, border: 0, bars: 10, freeLimit: 4)]
        case 31: return [net("weave-butterfly", lock: lock), net("weave-kite", lock: lock, crossClips: 1)]
        case 32: return [cages(across: 3, down: 3, count: 4, border: 0, bars: 13, freeLimit: 3)]
        case 33: return [maze(cols: 11, rows: 14, bars: 20)]
        case 34: return [net("figure-tower", lock: lock, crossClips: 1, tails: 3), net("figure-goblet", lock: lock, bars: 1, tails: 2)]
        case 35: return [net("weave-crystal", lock: lock, crossClips: 1, tails: 3)]
        case 36: return [cages(across: 3, down: 3, border: 0, bars: 8)]
        case 37: return [net("figure-waist", lock: lock, bars: 2, tails: 2), net("figure-gate", lock: lock, bars: 3, tails: 2)]
        case 38: return [maze(cols: 11, rows: 16, bars: 23)]
        case 39: return [net("weave-lantern", lock: lock, bars: 1, tails: 3), net("weave-tapestry", lock: lock, tails: 3)]
        case 40: return [sunAndMoons(lock: lock)]
        case 41: return [net("figure-tree", lock: lock, bars: 2), net("figure-border", lock: lock, crossClips: 1, bars: 2)]
        case 42: return [cages(across: 3, down: 4, count: 9, border: 0, bars: 11, freeLimit: 4)]
        case 43: return [maze(cols: 11, rows: 17, bars: 25)]
        case 44: return [net("figure-castle", lock: lock, bars: 3, tails: 2), net("figure-gate", lock: lock, crossClips: 1, bars: 3, tails: 3)]
        case 45: return [net("weave-tapestry", lock: lock, crossClips: 2, tails: 4)]
        case 46: return [net("weave-lantern", lock: lock, crossClips: 1, bars: 1), net("weave-butterfly", lock: lock, crossClips: 2)]
        case 47: return [maze(cols: 11, rows: 18, bars: 26, freeLimit: 3)]
        case 48: return [cages(across: 3, down: 4, count: 10, border: 0, bars: 8)]
        case 49: return [net("figure-castle", lock: lock, mirrored: false, crossClips: 2, bars: 4, tails: 5), net("figure-waist", lock: lock, crossClips: 2, bars: 2, tails: 3)]
        default: return [cages(across: 3, down: 4, count: 10, border: 0, bars: 10, freeLimit: 4)]
        }
    }

    /// Every curve template by id, for the generator tool's `compose` command.
    static let catalog: [String: LevelTemplate] = {
        var result: [String: LevelTemplate] = [:]
        for level in DifficultyCurve.firstCurveLevel...DifficultyCurve.lastLevel {
            for template in templates(level: level) where result[template.id] == nil { result[template.id] = template }
        }
        return result
    }()
}

extension Motifs {

    /// The flower with rays: a closed anchor with eight satellites, six of them locked by a bar that
    /// points away from the centre with its inner end in the satellite's gap. Slide a ray out, then
    /// its satellite can turn. The diagonal rays may end in a bent tip.
    static func sun(lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let anchorRadius = 48.0, satelliteRadius = 26.0
        let distance = anchorRadius + ForgeRules.preferredStem + satelliteRadius
        var draft = LevelDraft(name: "Sun", template: "sun")
        draft.pieces.append(.closedRing("o", at: .zero, radius: anchorRadius))
        func direction(_ degrees: Double) -> Point {
            Point(cos(AngleMath.radians(fromDegrees: degrees)), sin(AngleMath.radians(fromDegrees: degrees)))
        }
        for i in 0..<8 {
            let angle = Double(i) * 45
            draft.pieces.append(.ring("s\(i)", at: direction(angle) * distance, radius: satelliteRadius))
            guard draft.addClip(from: "o", at: direction(angle) * anchorRadius, to: "s\(i)") else { return nil }
        }
        let bent = rng.bool()
        let rayStart = distance + satelliteRadius - 10
        let rayLength = 56.0, tip = 28.0
        for i in 0..<8 {
            let angle = Double(i) * 45
            // The board is too narrow for rays to the left and right; those satellites get a plain lock.
            if i % 4 == 0 {
                guard draft.planGap(for: "s\(i)", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
                continue
            }
            guard let index = draft.index(of: "s\(i)"),
                  draft.gapIsValid(centerDegrees: angle, gapDegrees: ForgeRules.defaultGapDegrees, for: "s\(i)") else { return nil }
            draft.pieces[index].setGap(centerDegrees: angle, degrees: ForgeRules.defaultGapDegrees)
            let hub = direction(angle) * (rayStart + GridWorld.hubInset)
            if bent && i % 2 == 1 {
                // Tips bend towards the horizontal, mirrored left to right.
                let sign: Double = i == 1 || i == 5 ? -1 : 1
                draft.pieces.append(.slideElbow("ray\(i)", at: hub, from: -GridWorld.hubInset, to: rayLength - GridWorld.hubInset,
                                                legLength: sign * tip, angleDegrees: angle))
            } else {
                draft.pieces.append(.slideBar("ray\(i)", at: hub, from: -GridWorld.hubInset, to: rayLength - GridWorld.hubInset, angleDegrees: angle))
            }
        }
        return Motif(name: draft.name, template: draft.template, pieces: draft.pieces)
    }
}
