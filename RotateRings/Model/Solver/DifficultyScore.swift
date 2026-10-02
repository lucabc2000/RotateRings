//
//  DifficultyScore.swift
//  RotateRings
//
//  Difficulty of a level on a 0–100 scale, computed from solver metrics and the piece inventory.
//
//  Formula (every weight and scale below is a named constant):
//
//      score = 100 × ( minMovesWeight   × min(1, minMoves / minMovesScale)
//                    + deadEndWeight    × min(1, deadEndRate / deadEndScale)
//                    + branchingWeight  × min(1, (branching − 1) / branchingScale)
//                    + pieceCountWeight × min(1, (pieceCount − 2) / pieceCountScale)
//                    + varietyWeight    × min(1, distinctKinds / kindCount) )
//
//  The weights sum to 1. Each term saturates at its scale so one extreme metric cannot dominate.
//  When the metrics are an estimate the score is the same number; the generator widens its target
//  tolerance by `estimateUncertainty` and the browser marks the value with "≈".
//

import Foundation

enum DifficultyWeights {
    static let minMovesWeight = 0.35
    static let deadEndWeight = 0.25
    static let branchingWeight = 0.15
    static let pieceCountWeight = 0.15
    static let varietyWeight = 0.10

    /// Min moves at which the move term saturates.
    static let minMovesScale = 30.0
    /// Dead-end rate (share of moves from solvable states that lead into a dead end) at which the
    /// dead-end term saturates.
    static let deadEndScale = 0.35
    /// Branching above 1 at which the branching term saturates.
    static let branchingScale = 16.0
    /// Pieces above 2 at which the piece-count term saturates.
    static let pieceCountScale = 24.0
    /// Number of piece kinds in the game.
    static let kindCount = 6.0

    /// Extra tolerance, in score points, allowed when a level's metrics are estimates.
    static let estimateUncertainty = 8.0

    /// The formula as text, written into the generation report.
    static let formula = """
    100 * (0.35*min(1,minMoves/30) + 0.25*min(1,deadEndRate/0.35) + 0.15*min(1,(branching-1)/16) \
    + 0.15*min(1,(pieces-2)/24) + 0.10*min(1,kinds/6))
    """
}

enum DifficultyScore {
    static func score(metrics: SolverMetrics, pieceCount: Int, distinctKinds: Int) -> Double {
        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
        let moves = clamp(Double(metrics.minMoves) / DifficultyWeights.minMovesScale)
        let deadEnds = clamp(metrics.deadEndRate / DifficultyWeights.deadEndScale)
        let branching = clamp((metrics.branching - 1) / DifficultyWeights.branchingScale)
        let pieces = clamp(Double(pieceCount - 2) / DifficultyWeights.pieceCountScale)
        let variety = clamp(Double(distinctKinds) / DifficultyWeights.kindCount)
        let total = DifficultyWeights.minMovesWeight * moves
            + DifficultyWeights.deadEndWeight * deadEnds
            + DifficultyWeights.branchingWeight * branching
            + DifficultyWeights.pieceCountWeight * pieces
            + DifficultyWeights.varietyWeight * variety
        return (100 * total * 10).rounded() / 10
    }
}
