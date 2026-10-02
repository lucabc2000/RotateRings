//
//  LevelTemplate.swift
//  RotateRings
//
//  Templates turn motifs into whole levels: a single motif centred on the board for the tutorial,
//  or a vertical stack of motifs for the combination levels.
//

import Foundation

/// A named recipe that produces a level draft from a seed.
struct LevelTemplate {
    let id: String
    /// Piece kinds the template can contain.
    let kinds: Set<PieceKind>
    let build: (_ level: Int, _ rng: inout SplitMix64) -> LevelDraft?

    /// Diagnostics sink for the command-line tool; nil in the app.
    nonisolated(unsafe) static var debug: ((String) -> Void)?

    /// One motif in the middle of the board.
    static func single(_ id: String, kinds: Set<PieceKind>, motif: @escaping (_ rng: inout SplitMix64) -> Motif?) -> LevelTemplate {
        LevelTemplate(id: id, kinds: kinds) { _, rng in
            guard let motif = motif(&rng) else { return nil }
            var draft = LevelDraft(name: motif.name, template: id, pieces: motif.placed(at: ForgeRules.center))
            draft.renumberIDs()
            return draft
        }
    }

    /// Several motifs arranged in rows. A row holds one motif centred, or two narrow motifs side by
    /// side. Rows are spread evenly over the board height. Fails when they do not fit.
    static func stack(_ id: String, name: String, kinds: Set<PieceKind>, spacing: Double = 24, motifs: @escaping (_ rng: inout SplitMix64) -> [Motif]?) -> LevelTemplate {
        LevelTemplate(id: id, kinds: kinds) { _, rng in
            // A seed gets a few tries at a motif set that fits.
            for _ in 0..<8 {
                guard let motifs = motifs(&rng), !motifs.isEmpty else {
                    debug?("\(id): a motif failed to build")
                    continue
                }
                if let pieces = layout(motifs, spacing: spacing, rng: &rng) {
                    var draft = LevelDraft(name: name, template: id, pieces: pieces)
                    draft.renumberIDs()
                    return draft
                }
                debug?("\(id): no fit for " + motifs.map { "\($0.template) \(Int($0.width))×\(Int($0.height))" }.joined(separator: ", "))
            }
            return nil
        }
    }

    /// Arranges motifs in rows (narrow ones in pairs) spread evenly over the board. Nil if they do not fit.
    private static func layout(_ motifs: [Motif], spacing: Double, rng: inout SplitMix64) -> [DraftPiece]? {
            let usableWidth = ForgeRules.boardWidth - 2 * ForgeRules.margin
            let usableHeight = ForgeRules.boardHeight - 2 * ForgeRules.margin

            // Two motifs share a row whenever they fit side by side; widest first so big motifs get
            // paired with the narrow ones.
            var remaining = motifs.sorted { $0.width > $1.width }
            var rows: [[Motif]] = []
            while !remaining.isEmpty {
                let first = remaining.removeFirst()
                if let partner = remaining.firstIndex(where: { first.width + $0.width + spacing <= usableWidth }) {
                    let second = remaining.remove(at: partner)
                    rows.append(rng.bool() ? [first, second] : [second, first])
                } else {
                    rows.append([first])
                }
            }
            rows.shuffle(using: &rng)

            let rowHeights = rows.map { row in row.map(\.height).max() ?? 0 }
            let leftover = usableHeight - rowHeights.reduce(0, +)
            let slot = leftover / Double(rows.count + 1)
            guard slot >= spacing else { return nil }

            var pieces: [DraftPiece] = []
            var top = ForgeRules.boardHeight - ForgeRules.margin - slot
            var motifIndex = 0
            for (row, height) in zip(rows, rowHeights) {
                let centerY = top - height / 2
                let centers: [Point]
                if row.count == 2 {
                    let half = spacing / 2
                    centers = [Point(ForgeRules.center.x - half - row[0].width / 2, centerY),
                               Point(ForgeRules.center.x + half + row[1].width / 2, centerY)]
                } else {
                    centers = [Point(ForgeRules.center.x, centerY)]
                }
                for (motif, center) in zip(row, centers) {
                    for piece in motif.placed(at: center, anchored: row.count == 1) {
                        var piece = piece
                        piece.id = "m\(motifIndex)_" + piece.id
                        piece.clips = piece.clips.map { clip in
                            var clip = clip
                            clip.grips = clip.grips.map { "m\(motifIndex)_" + $0 }
                            return clip
                        }
                        pieces.append(piece)
                    }
                    motifIndex += 1
                }
                top -= height + slot
            }
            return pieces
    }
}

/// Motif builders by name, with the lock-step range as the main difficulty knob.
enum MotifCatalog {
    typealias Builder = (_ lockRange: ClosedRange<Int>, _ rng: inout SplitMix64) -> Motif?

    static let builders: [String: Builder] = [
        "ringChain2": { lock, rng in Motifs.ringChain(count: 2, lockRange: lock, rng: &rng) },
        "ringChain3": { lock, rng in Motifs.ringChain(count: 3, radius: 40, lockRange: lock, rng: &rng) },
        "ringChain4": { lock, rng in Motifs.ringChain(count: 4, radius: 40, lockRange: lock, rng: &rng) },
        "ringCorner": { lock, rng in Motifs.ringCorner(lockRange: lock, rng: &rng) },
        "anchorStar2": { lock, rng in Motifs.anchorStar(count: 2, lockRange: lock, rng: &rng) },
        "anchorStar3": { lock, rng in Motifs.anchorStar(count: 3, lockRange: lock, rng: &rng) },
        "anchorStar4": { lock, rng in Motifs.anchorStar(count: 4, lockRange: lock, rng: &rng) },
        "concentric": { lock, rng in Motifs.concentric(withSatellite: false, lockRange: lock, rng: &rng) },
        "concentricSatellite": { lock, rng in Motifs.concentric(withSatellite: true, lockRange: lock, rng: &rng) },
        "barLatch": { lock, rng in Motifs.barLatch(locks: 1, lockRange: lock, rng: &rng) },
        "barLatch2": { lock, rng in Motifs.barLatch(locks: 2, lockRange: lock, rng: &rng) },
        "slideLatch": { lock, rng in Motifs.slideLatch(locks: 1, lockRange: lock, rng: &rng) },
        "slideLatch2": { lock, rng in Motifs.slideLatch(locks: 2, lockRange: lock, rng: &rng) },
        "elbowSlide": { lock, rng in Motifs.elbowSlide(locks: 1, lockRange: lock, rng: &rng) },
        "elbowSlide2": { lock, rng in Motifs.elbowSlide(locks: 2, lockRange: lock, rng: &rng) },
        "slideGate": { lock, rng in Motifs.slideGate(lockRange: lock, rng: &rng) },
        "elbowLatch": { lock, rng in Motifs.elbowLatch(lockRange: lock, rng: &rng) },
        "tailGate": { lock, rng in Motifs.tailGate(lockRange: lock, rng: &rng) },
        "tailClip": { lock, rng in Motifs.tailClip(tails: 1, withAnchor: true, lockRange: lock, rng: &rng) },
        "tailClip2": { lock, rng in Motifs.tailClip(tails: 2, withAnchor: true, lockRange: lock, rng: &rng) },
        "flower": { lock, rng in Motifs.flower(lockRange: lock, rng: &rng) },
        "concentricTriple": { lock, rng in Motifs.concentricTriple(satellites: 0, lockRange: lock, rng: &rng) },
        "orbit": { lock, rng in Motifs.concentricTriple(satellites: 2, lockRange: lock, rng: &rng) },
        "lattice2x3": { lock, rng in Motifs.lattice(rows: 3, cols: 2, crossClips: 1, lockRange: lock, rng: &rng) },
        "lattice3x3": { lock, rng in Motifs.lattice(rows: 3, cols: 3, fill: 0.9, crossClips: 1, lockRange: lock, rng: &rng) },
        "lattice2x4": { lock, rng in Motifs.lattice(rows: 4, cols: 2, crossClips: 1, lockRange: lock, rng: &rng) },
        "lattice3x4": { lock, rng in Motifs.lattice(rows: 4, cols: 3, fill: 0.9, crossClips: 2, lockRange: lock, rng: &rng) },
        "lattice4x4": { lock, rng in Motifs.lattice(rows: 4, cols: 4, fill: 0.85, crossClips: 2, lockRange: lock, rng: &rng) },
        "lattice3x5": { lock, rng in Motifs.lattice(rows: 5, cols: 3, fill: 0.9, crossClips: 2, lockRange: lock, rng: &rng) },
        "lattice3x6": { lock, rng in Motifs.lattice(rows: 6, cols: 3, fill: 0.9, crossClips: 3, lockRange: lock, rng: &rng) },
        "lattice4x5": { lock, rng in Motifs.lattice(rows: 5, cols: 4, fill: 0.85, crossClips: 3, lockRange: lock, rng: &rng) },
        "lattice4x6": { lock, rng in Motifs.lattice(rows: 6, cols: 4, fill: 0.9, crossClips: 3, lockRange: lock, rng: &rng) },
        "snake4x6": { lock, rng in Motifs.lattice(rows: 6, cols: 4, fill: 1, crossClips: 4, anchorChance: 0, lockRange: lock, rng: &rng) },
    ]

    static let kinds: [String: Set<PieceKind>] = [
        "ringChain2": [.cRing], "ringChain3": [.cRing], "ringChain4": [.cRing], "ringCorner": [.cRing],
        "anchorStar2": [.closedRing, .cRing], "anchorStar3": [.closedRing, .cRing], "anchorStar4": [.closedRing, .cRing],
        "concentric": [.closedRing, .cRing], "concentricSatellite": [.closedRing, .cRing],
        "barLatch": [.latchBar, .cRing], "barLatch2": [.latchBar, .cRing],
        "slideLatch": [.slideBar, .cRing], "slideLatch2": [.slideBar, .cRing],
        "elbowSlide": [.lBar, .cRing], "elbowSlide2": [.lBar, .cRing],
        "slideGate": [.slideBar, .cRing],
        "elbowLatch": [.latchBar, .cRing],
        "tailGate": [.tailRing, .cRing], "tailClip": [.tailRing, .cRing], "tailClip2": [.tailRing, .cRing],
        "flower": [.closedRing, .cRing], "concentricTriple": [.closedRing, .cRing], "orbit": [.closedRing, .cRing],
        "lattice2x3": [.cRing, .closedRing], "lattice3x3": [.cRing, .closedRing], "lattice2x4": [.cRing, .closedRing],
        "lattice3x4": [.cRing, .closedRing], "lattice4x4": [.cRing, .closedRing], "lattice3x5": [.cRing, .closedRing], "lattice3x6": [.cRing, .closedRing],
        "lattice4x5": [.cRing, .closedRing], "lattice4x6": [.cRing, .closedRing], "snake4x6": [.cRing],
    ]

    /// Motifs short enough to share the board with one other.
    static let compact = ["ringChain2", "ringChain3", "ringCorner", "anchorStar2", "anchorStar3", "concentric", "elbowLatch", "slideLatch", "elbowSlide", "tailGate", "tailClip"]
    /// Motifs small enough for three to share the board (narrow ones pair up in a row).
    static let small = ["ringChain2", "ringChain2", "concentric", "concentric", "anchorStar2", "ringCorner", "elbowLatch", "slideLatch", "elbowSlide", "tailClip"]
    /// Motifs that take most of the height.
    static let tall = ["barLatch", "barLatch2", "slideGate", "ringChain4", "concentricSatellite", "tailClip2"]

    static func single(_ name: String, lockRange: ClosedRange<Int>) -> LevelTemplate {
        let builder = builders[name]!
        return LevelTemplate.single(name, kinds: kinds[name]!) { rng in builder(lockRange, &rng) }
    }

    /// A stack of `count` motifs drawn from `pool`, each built with `lockRange`. The first name in
    /// `required`, if any, is always included.
    static func stack(count: Int, pool: [String], required: [String] = [], lockRange: ClosedRange<Int>, idSuffix: String) -> LevelTemplate {
        let allKinds = pool.reduce(into: Set<PieceKind>()) { $0.formUnion(kinds[$1] ?? []) }
        return LevelTemplate.stack("stack\(count)-\(idSuffix)", name: "Medley", kinds: allKinds) { rng in
            var names = required
            while names.count < count { names.append(rng.pick(pool)) }
            names.shuffle(using: &rng)
            var motifs: [Motif] = []
            for name in names {
                guard let builder = builders[name], let motif = builder(lockRange, &rng) else { return nil }
                motifs.append(motif)
            }
            return motifs
        }
    }
}
