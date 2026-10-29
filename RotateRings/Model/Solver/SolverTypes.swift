//
//  SolverTypes.swift
//  RotateRings
//
//  Inputs and outputs of `LevelSolver`. All Codable so the generator can write them into the level
//  report and the app can show them in the Level Browser.
//

import Foundation

/// Tunables for `LevelSolver`. Every limit counts work, never time, so a level solves the same way
/// on any machine and with any number of parallel jobs. (Reports written before October 2026 also
/// carry a `timeCap`; decoding ignores it.)
struct SolverConfig: Codable, Equatable, Sendable {
    /// Exact search stops expanding once this many distinct states exist; the rest is estimated.
    /// 30,000 is about what the old four-second limit reached on 30-ring boards (12–42k), and above
    /// every board that has ever been solved exactly (at most 15k).
    var stateCap = 30_000
    /// Expansion budget of the best-first search that finds a solution when the exact search gave up.
    var boundedExpansions = 4_000

    init() {}
}

/// One player action: a drag of `steps` grid steps on a turning piece, or a push of a sliding bar
/// in one direction until it stops.
struct SolverMove: Codable, Equatable, Sendable {
    let piece: Piece.ID
    /// Turning pieces: signed step count, positive counterclockwise. Sliding bars: +1 along the hub
    /// axis, -1 against it.
    let steps: Int
    /// The same move expressed as the delta `Board.move(_:by:)` takes (radians or distance).
    let delta: Double
    /// Pieces that left the board because of this move.
    let removed: [Piece.ID]
}

struct SolverMetrics: Codable, Equatable, Sendable {
    /// Fewest drags that complete the level. An upper bound when `isEstimate` is true.
    var minMoves: Int
    /// Distinct states the exact search visited (including the start).
    var reachableStates: Int
    /// Reachable states from which the level can still be completed.
    var solvableStates: Int
    /// Reachable states from which the level can no longer be completed.
    var deadEndStates: Int
    /// Moves that take a solvable state into an unsolvable one.
    var deadEndMoves: Int
    /// All moves available from solvable states.
    var totalMoves: Int
    /// `deadEndMoves / totalMoves`. When `isEstimate` is true it is a lower bound, measured on the
    /// explored part of the move graph.
    var deadEndRate: Double
    /// Mean number of distinct moves available per non-final state.
    var branching: Double
    /// True when every reachable state was visited, which makes all counts exact.
    var fullyExplored: Bool
    /// True when the state cap was hit and the numbers come from a bounded search.
    var isEstimate: Bool
    /// Unused since dead ends are measured on the explored graph; kept so older reports still decode.
    var playouts: Int?
    /// Seconds spent solving. Printed by the tool, never written to a file (see `CodingKeys`), so
    /// that reruns produce identical reports.
    var elapsed: Double = 0
    /// Share of the pieces on the board that can make progress (release a clip or leave), summed
    /// over the steps of the solution. Low means the player has to hunt for the few pieces that are
    /// free. Filled in by the generator; nil in older reports.
    var freedom: Double? = nil
    /// Moves of the solution that take nothing off the board: they only prepare a later move, such
    /// as turning a ring onto one hub's clip while another ring still holds that hub. A level where
    /// every drag removes a piece has none, and plays easy however few pieces are free.
    /// Filled in by the generator; nil in older reports.
    var setupMoves: Int? = nil

    private enum CodingKeys: String, CodingKey {
        case minMoves, reachableStates, solvableStates, deadEndStates, deadEndMoves, totalMoves, deadEndRate
        case branching, fullyExplored, isEstimate, playouts, freedom, setupMoves
    }
}

struct SolverResult: Equatable, Sendable {
    var isSolvable: Bool
    var metrics: SolverMetrics
    /// A complete solution, when one was found.
    var solution: [SolverMove]?
}

extension Board {
    /// Replays a solver solution. Returns false as soon as a move is not accepted or the board is not
    /// empty at the end.
    mutating func replay(_ solution: [SolverMove]) -> Bool {
        for move in solution {
            guard case .moved = self.move(move.piece, by: move.delta) else { return false }
        }
        return isComplete
    }
}
