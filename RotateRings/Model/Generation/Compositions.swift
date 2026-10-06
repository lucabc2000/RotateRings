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
//  - tangle: a free-form cluster grown from one seed (chains, used for the hard ones) or from
//    several closed hubs (easy and pretty); planet wraps one in a giant ring (`Tangle`);
//  - showcase (every fifth level): the sun, the bullseye, or the largest board of a genre above.
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

    // MARK: Hub webs

    /// Masks for hub webs. Holes (`o`) sit where a hub would, two cells apart, so the rings around
    /// them can be poked by a bar.
    static let webShapes: [String: RingNet.Shape] = {
        let list: [RingNet.Shape] = [
            // Square, three big rings across.
            shape("hubs-nine", "Nine", .square, radius: 44, stem: 18, ["###", "###", "###"]),
            shape("hubs-twelve", "Twelve", .square, radius: 44, stem: 18, ["###", "###", "###", "###"]),
            shape("hubs-grand", "Grand web", .square, radius: 44, stem: 18, ["###", "###", "###", "###", "###"]),
            // Square, three medium rings across.
            shape("hubs-column", "Column", .square, radius: 40, stem: 20, ["###", "###", "###", "###", "###", "###"]),
            // Square, four small rings across. All holes of a mask sit on cells of one colour of
            // the checkerboard (column + row even), because that colour becomes the hubs.
            shape("hubs-field", "Field", .square, radius: 30, stem: 20, ["####", "####", "####", "####", "####", "####"]),
            shape("hubs-tall", "Tall field", .square, radius: 30, stem: 20, ["####", "####", "####", "####", "####", "####", "####"]),
            shape("hubs-diamond", "Cut web", .square, radius: 30, stem: 20, [".##.", "####", "####", "####", "####", "####", ".##."]),
            shape("hubs-gaps", "Gaps", .square, radius: 30, stem: 20, ["####", "#o##", "####", "###o", "####", "#o##", "####"]),
            shape("hubs-sieve", "Sieve", .square, radius: 30, stem: 20, ["o###", "####", "##o#", "####", "o###", "####", "##o#"]),
            shape("hubs-riddle", "Riddle", .square, radius: 30, stem: 20, ["####", "#o##", "####", "###o", "o###", "####", "##o#"]),
            shape("hubs-lace", "Lace", .square, radius: 30, stem: 20, ["####", "#o##", "##o#", "####", "o###", "###o", "####"]),
            shape("hubs-ports", "Ports", .square, radius: 30, stem: 20, [".##.", "#o##", "####", "####", "##o#", "####", ".##."]),
            shape("hubs-final", "Stronghold", .square, radius: 30, stem: 20, ["####", "#o##", "####", "####", "####", "###o", "####"]),
            // Diagonal, five columns of small rings. Only half as many cells of one colour as of the
            // other, so these webs need less preparing; holes would thin the hubs further.
            shape("hubs-kite", "Web kite", .diagonal, radius: 32, stem: 18, ["..#..", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "..#.."]),
            shape("hubs-weave", "Woven web", .diagonal, radius: 32, stem: 18, ["#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#", ".#.#.", "#.#.#"]),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.template, $0) })
    }()

    /// A web of closed hubs and shared rings (`HubWeb`).
    static func hubWeb(_ shapeID: String, clips: ClosedRange<Int> = 2...4, holders: Int = 3, bars: Int = 0, tails: Double = 0) -> LevelTemplate {
        let shape = webShapes[shapeID]!
        var options = HubWeb.Options()
        options.clips = clips
        options.holdersPerRing = holders
        options.bars = bars
        options.tailShare = tails
        options.name = shape.name
        let id = shapeID + (tails > 0 ? "-tails" : "")
        options.template = id
        var kinds: Set<PieceKind> = [.cRing, .closedRing]
        if bars > 0 { kinds.insert(.slideBar) }
        if tails > 0 { kinds.insert(.tailRing) }
        return LevelTemplate.single(id, kinds: kinds) { rng in HubWeb.build(shape, options: options, rng: &rng) }
    }

    /// Rings that hold and are held (`Knot`), on one of the web masks.
    static func knot(_ shapeID: String, holders: Int = 2, clips: Int = 2, link: Double = 0.85, anchors: Double = 0.25, bars: Int = 0, uBars: Int = 0,
                     tails: Double = 0, bombs: Int = 0) -> LevelTemplate {
        let shape = webShapes[shapeID]!
        var options = Knot.Options()
        options.maxHolders = holders
        options.maxClips = clips
        options.linkChance = link
        options.anchorChance = anchors
        options.tailShare = tails
        options.bars = bars
        options.uBars = uBars
        options.bombs = bombs
        options.name = shape.name
        let id = shapeID.replacingOccurrences(of: "hubs-", with: "knot-") + "-\(holders)\(clips)" + (bars > 0 ? "-b\(bars)" : "")
            + (uBars > 0 ? "-u\(uBars)" : "") + (tails > 0 ? "-tails" : "") + (bombs > 0 ? "-bomb\(bombs)" : "")
        options.template = id
        var kinds: Set<PieceKind> = [.cRing, .closedRing]
        if tails > 0 { kinds.insert(.tailRing) }
        if bars > 0 { kinds.insert(.slideBar) }
        if uBars > 0 { kinds.insert(.uBar) }
        return LevelTemplate.single(id, kinds: kinds) { rng in Knot.build(shape, options: options, rng: &rng) }
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

    // MARK: Tangles

    /// A free-form cluster of rings and bars. `planet` wraps it in a giant ring.
    static func tangle(rings: ClosedRange<Int>, pokes: Int = 0, latches: Int = 0, planet: Bool = false, hubs: Int = 1,
                       chain: Double = 0.55, blocked: Bool = false, lock: ClosedRange<Int>) -> LevelTemplate {
        var options = Tangle.Options(rings: rings)
        options.hubs = hubs
        options.blockedPokes = blocked
        options.pokeBars = pokes
        options.latchBars = latches
        options.planet = planet
        options.chain = chain
        options.lockRange = lock
        if rings.upperBound >= 16 { options.radii = [22, 24, 26, 30, 32, 36] } else if rings.upperBound >= 12 { options.radii = [24, 28, 30, 34, 40, 46] }
        options.name = planet ? "Planet" : "Tangle"
        options.template = (planet ? "planet-" : "tangle-") + "\(rings.lowerBound)-\(rings.upperBound)"
            + (pokes + latches > 0 ? "-locked" : "") + (hubs > 1 ? "-\(hubs)hubs" : "") + (blocked ? "-tight" : "")
        var kinds: Set<PieceKind> = [.cRing, .closedRing]
        if pokes > 0 { kinds.insert(.slideBar) }
        if latches > 0 { kinds.insert(.latchBar) }
        let template = options.template
        return LevelTemplate.single(template, kinds: kinds) { rng in Tangle.build(options, rng: &rng) }
    }

    // MARK: Showcase

    /// A bullseye of four nested rings sharing the board with a small tangle.
    static func bullseye(lock: ClosedRange<Int>) -> LevelTemplate {
        LevelTemplate.stack("bullseye", name: "Bullseye", kinds: [.closedRing, .cRing, .slideBar]) { rng in
            var options = Tangle.Options(rings: 6...8)
            options.pokeBars = 1
            options.radii = [24, 28, 30, 34, 38]
            options.halfHeight = 138
            options.lockRange = lock
            options.template = "bullseye"
            guard let target = Motifs.bullseye(lockRange: lock, rng: &rng), let tangle = Tangle.build(options, rng: &rng) else { return nil }
            return [target, tangle]
        }
    }

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
    /// Past level 50 everything is hard except the breather at each 5; see `lateTemplates`.
    // PLAN-BEGIN
    /// No level is ranked as hard any more: every level from 11 on takes the candidate closest to
    /// its target on the difficulty curve (`DifficultyCurve.targets`).
    static let hardLevels: Set<Int> = []

    /// The design of each level from 11 to 100. The table is written by hand-tuned planning, not
    /// by a formula: targets rise in uneven waves (LEVEL-DESIGN.md §10), and each level gets the
    /// design whose usual difficulty is closest to its target, never the same kind of board twice
    /// running and preferably not the same kind of difficulty either (finding a chain, things in
    /// the way, lining rings up, ordering bars, reading a picture).
    static func templates(level: Int) -> [LevelTemplate] {
        let lock = 1...4
        switch level {
        case 11: return [knot("hubs-nine", holders: 2)]
        case 12: return [knot("hubs-nine", holders: 2, tails: 0.4)]
        case 13: return [hubWeb("hubs-nine", clips: 2...3, holders: 2, tails: 0.85)]
        case 14: return [tangle(rings: 15...18, pokes: 2, latches: 1, hubs: 3, lock: lock)]
        case 15: return [knot("hubs-nine", holders: 2, bars: 1, tails: 0.4)]
        case 16: return [maze(cols: 8, rows: 10, bars: 11, freeLimit: 2)]
        case 17: return [net("weave-crystal", lock: lock, crossClips: 1, tails: 3)]
        case 18: return [knot("hubs-twelve", holders: 2)]
        case 19: return [knot("hubs-twelve", holders: 2, bars: 2)]
        case 20: return [knot("hubs-grand", holders: 2, bars: 1, uBars: 1)]
        case 21: return [net("figure-block", lock: lock)]
        case 22: return [knot("hubs-twelve", holders: 2, bars: 2, tails: 0.4)]
        case 23: return [knot("hubs-grand", holders: 2, bars: 3)]
        case 24: return [net("weave-butterfly", lock: lock)]
        case 25: return [knot("hubs-twelve", holders: 2, uBars: 1)]
        case 26: return [knot("hubs-grand", holders: 2, bombs: 1)]
        case 27: return [cages(across: 3, down: 3, count: 4, border: 0, bars: 13, freeLimit: 3)]
        case 28: return [knot("hubs-nine", holders: 2, bars: 1)]
        case 29: return [maze(cols: 10, rows: 14, bars: 17, freeLimit: 2)]
        case 30: return [knot("hubs-column", holders: 3, bars: 1, uBars: 1)]
        case 31: return [hubWeb("hubs-twelve", clips: 2...3, holders: 2, tails: 0.85)]
        case 32: return [knot("hubs-column", holders: 3, bombs: 1)]
        case 33: return [tangle(rings: 11...14, pokes: 1, latches: 1, lock: lock)]
        case 34: return [knot("hubs-grand", holders: 2, bars: 3, tails: 0.4)]
        case 35: return [hubWeb("hubs-grand", clips: 3...4, holders: 3, tails: 0.85)]
        case 36: return [net("weave-lantern", lock: lock, bars: 1, tails: 3)]
        case 37: return [knot("hubs-column", holders: 3, bars: 3, tails: 0.4, bombs: 1)]
        case 38: return [sunAndMoons(lock: lock)]
        case 39: return [knot("hubs-kite", holders: 2, tails: 0.3)]
        case 40: return [tangle(rings: 13...16, pokes: 2, latches: 2, chain: 0.7, lock: lock)]
        case 41: return [knot("hubs-grand", holders: 2, tails: 0.4, bombs: 1)]
        case 42: return [hubWeb("hubs-weave", clips: 3...4, holders: 3, tails: 0.85)]
        case 43: return [net("weave-tapestry", lock: lock, crossClips: 2, tails: 4)]
        case 44: return [knot("hubs-twelve", holders: 2, tails: 0.4, bombs: 1)]
        case 45: return [knot("hubs-field", holders: 3, uBars: 2)]
        case 46: return [net("weave-kite", lock: lock, crossClips: 1)]
        case 47: return [hubWeb("hubs-column", clips: 3...4, holders: 3, tails: 0.85)]
        case 48: return [maze(cols: 11, rows: 18, bars: 23, freeLimit: 3)]
        case 49: return [knot("hubs-column", holders: 3, bars: 3, bombs: 1)]
        case 50: return [knot("hubs-field", holders: 3, bars: 2, uBars: 1)]
        case 51: return [net("weave-lantern", lock: lock, bars: 1, tails: 3)]
        case 52: return [maze(cols: 11, rows: 16, bars: 21, freeLimit: 3)]
        case 53: return [hubWeb("hubs-weave", clips: 3...4, holders: 3, tails: 0.85)]
        case 54: return [tangle(rings: 17...21, pokes: 3, latches: 2, chain: 0.75, lock: lock)]
        case 55: return [maze(cols: 11, rows: 20, bars: 26, freeLimit: 3)]
        case 56: return [hubWeb("hubs-kite", clips: 3...4, holders: 3, tails: 0.85)]
        case 57: return [cages(across: 3, down: 4, count: 5, border: 0, bars: 15, freeLimit: 3)]
        case 58: return [knot("hubs-column", holders: 3, bombs: 1)]
        case 59: return [knot("hubs-field", holders: 3, bars: 4)]
        case 60: return [maze(cols: 11, rows: 15, bars: 19, freeLimit: 3)]
        case 61: return [knot("hubs-column", holders: 3, bars: 1, uBars: 1, bombs: 1)]
        case 62: return [knot("hubs-column", holders: 3, tails: 0.4)]
        case 63: return [knot("hubs-weave", holders: 3, tails: 0.4)]
        case 64: return [knot("hubs-grand", holders: 2, bars: 1, uBars: 1, bombs: 1)]
        case 65: return [net("weave-tapestry", lock: lock, crossClips: 2, tails: 4)]
        case 66: return [maze(cols: 11, rows: 18, bars: 23, freeLimit: 3)]
        case 67: return [hubWeb("hubs-field", clips: 3...4, holders: 3, tails: 0.85)]
        case 68: return [cages(across: 3, down: 4, count: 6, border: 0, bars: 16, freeLimit: 3)]
        case 69: return [knot("hubs-tall", holders: 3, bars: 2, uBars: 2, bombs: 1)]
        case 70: return [knot("hubs-column", holders: 3, bars: 3, tails: 0.4)]
        case 71: return [cages(across: 3, down: 4, count: 5, border: 0, bars: 15, freeLimit: 3)]
        case 72: return [knot("hubs-field", holders: 3, bombs: 1)]
        case 73: return [knot("hubs-field", holders: 3, uBars: 2)]
        case 74: return [knot("hubs-field", holders: 3, bars: 4, tails: 0.4)]
        case 75: return [hubWeb("hubs-riddle", clips: 3...4, holders: 3, bars: 4, tails: 0.85)]
        case 76: return [maze(cols: 11, rows: 15, bars: 19, freeLimit: 3)]
        case 77: return [knot("hubs-field", holders: 3, bars: 2, uBars: 1, bombs: 2)]
        case 78: return [knot("hubs-field", holders: 3, tails: 0.4)]
        case 79: return [maze(cols: 11, rows: 16, bars: 21, freeLimit: 3)]
        case 80: return [knot("hubs-field", holders: 3, bars: 4)]
        case 81: return [hubWeb("hubs-gaps", clips: 3...4, holders: 3, bars: 4, tails: 0.85)]
        case 82: return [knot("hubs-tall", holders: 3, bars: 6, tails: 0.4, bombs: 2)]
        case 83: return [cages(across: 3, down: 3, count: 4, border: 0, bars: 13, freeLimit: 3)]
        case 84: return [hubWeb("hubs-lace", clips: 3...4, holders: 3, bars: 4, tails: 0.85)]
        case 85: return [hubWeb("hubs-field", clips: 3...4, holders: 3, tails: 0.85)]
        case 86: return [knot("hubs-field", holders: 3, bombs: 2)]
        case 87: return [knot("hubs-tall", holders: 3, bars: 6)]
        case 88: return [knot("hubs-weave", holders: 3, tails: 0.4)]
        case 89: return [knot("hubs-column", holders: 3, tails: 0.4, bombs: 1)]
        case 90: return [hubWeb("hubs-riddle", clips: 3...4, holders: 3, bars: 4, tails: 0.85)]
        case 91: return [knot("hubs-field", holders: 3, bars: 4, tails: 0.4)]
        case 92: return [hubWeb("hubs-tall", clips: 3...4, holders: 3, tails: 0.85)]
        case 93: return [maze(cols: 11, rows: 20, bars: 26, freeLimit: 3)]
        case 94: return [knot("hubs-tall", holders: 3, tails: 0.4, bombs: 2)]
        case 95: return [cages(across: 3, down: 4, count: 6, border: 0, bars: 16, freeLimit: 3)]
        case 96: return [hubWeb("hubs-gaps", clips: 3...4, holders: 3, bars: 4, tails: 0.85)]
        case 97: return [knot("hubs-field", holders: 3, tails: 0.4)]
        case 98: return [knot("hubs-tall", holders: 3, bars: 2, uBars: 2)]
        case 99: return [knot("hubs-field", holders: 3, bombs: 1)]
        case 100: return [knot("hubs-tall", holders: 3, tails: 0.4)]
        default: return [knot("hubs-nine", holders: 2)]
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

    /// Four rings inside each other. The closed outer ring grips the next one in, which grips the
    /// next, down to the smallest: free the middle first and work outwards. Each ring's clip sits
    /// well away from the clip that holds it, so its gap has room one step from its own clip.
    static func bullseye(lockRange: ClosedRange<Int>, rng: inout SplitMix64) -> Motif? {
        let radii = [112.0, 88, 64, 40]
        var draft = LevelDraft(name: "Bullseye", template: "bullseye")
        draft.pieces.append(.closedRing("c0", at: .zero, radius: radii[0]))
        for i in 1..<radii.count { draft.pieces.append(.ring("c\(i)", at: .zero, radius: radii[i])) }
        var degrees = Double(rng.int(in: 0...7)) * 45
        for i in 0..<(radii.count - 1) {
            let direction = Point(cos(AngleMath.radians(fromDegrees: degrees)), sin(AngleMath.radians(fromDegrees: degrees)))
            guard draft.addClip(from: "c\(i)", at: direction * radii[i], to: "c\(i + 1)") else { return nil }
            degrees = normalizedDegrees(degrees + rng.pick([135.0, 180, 225]))
        }
        for i in 1..<(radii.count - 1) {
            // Gripping and gripped: a single step, as in the lattices.
            guard let used = draft.planGap(for: "c\(i)", lockSteps: rng.bool() ? 1 : -1), abs(used) == 1 else { return nil }
        }
        guard draft.planGap(for: "c\(radii.count - 1)", lockSteps: rng.lockSteps(in: lockRange)) != nil else { return nil }
        return Motif(name: draft.name, template: draft.template, pieces: draft.pieces)
    }

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
