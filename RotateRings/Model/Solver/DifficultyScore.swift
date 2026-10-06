//
//  DifficultyScore.swift
//  RotateRings
//
//  Difficulty of a level on a 0–100 scale, from what the solver measured. An estimate of how hard
//  a level plays, used to place levels on the curve; it has disagreed with the owner's own play
//  before, so treat it as a guide.
//
//      score = 100 × ( piecesWeight  × (pieces − 6) / 22
//                    + movesWeight   × (minMoves − 6) / 34
//                    + freedomWeight × (0.5 − freedom) / 0.4
//                    + setupWeight   × setupMoves / 12 )        each term clamped to 0…1
//
//  Pieces and moves are size. Freedom is the share of pieces that can do something useful at a
//  time: the lower, the harder it is to find the next move. Setup moves are drags that remove
//  nothing and only prepare a later one.
//

import Foundation

enum DifficultyWeights {
    static let piecesWeight = 0.35
    static let movesWeight = 0.25
    static let freedomWeight = 0.25
    static let setupWeight = 0.15

    /// Extra tolerance, in score points, allowed when a level's metrics are estimates. Nearly every
    /// level past the tutorial is an estimate, so this no longer separates candidates.
    static let estimateUncertainty = 0.0

    /// The formula as text, written into the generation report.
    static let formula = """
    100 * (0.35*clamp((pieces-6)/22) + 0.25*clamp((minMoves-6)/34) + 0.25*clamp((0.5-freedom)/0.4) \
    + 0.15*clamp(setupMoves/12))
    """
}

enum DifficultyScore {
    static func score(metrics: SolverMetrics, pieceCount: Int, distinctKinds: Int) -> Double {
        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
        let pieces = clamp(Double(pieceCount - 6) / 22)
        let moves = clamp(Double(metrics.minMoves - 6) / 34)
        let freedom = clamp((0.5 - (metrics.freedom ?? 0.5)) / 0.4)
        let setup = clamp(Double(metrics.setupMoves ?? 0) / 12)
        let total = DifficultyWeights.piecesWeight * pieces + DifficultyWeights.movesWeight * moves
            + DifficultyWeights.freedomWeight * freedom + DifficultyWeights.setupWeight * setup
        return (100 * total * 10).rounded() / 10
    }
}
