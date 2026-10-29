//
//  QualityConfig.swift
//  RotateRings
//
//  Every setting of the quality measurements (LEVEL-DESIGN.md §14) in one place: the bot players,
//  and the weights and thresholds of the scores built on them. Limits count work, never time, so
//  the numbers are the same on any machine.
//

import Foundation

struct QualityConfig: Codable, Equatable, Sendable {
    /// The bots, by lookahead. A bot with lookahead k looks k + 1 drags ahead for a piece it can take
    /// off; lookahead 0 only takes what comes off right away. (A 4-deep bot was tried and never did
    /// better than the 3-deep one.)
    var lookaheads = [0, 1, 2]
    /// Games each bot plays on a level.
    var runs = 20
    /// A game is lost after `moveLimitFactor × minMoves + moveLimitExtra` drags.
    var moveLimitFactor = 3
    var moveLimitExtra = 20
    /// Most positions one lookahead may expand; when it runs out, the bot found nothing and drags at
    /// random. Positions already worked out in an earlier game on the same level cost nothing.
    var lookaheadBudget = 400

    // MARK: Tier and insight

    /// A bot plans a level (rather than trying things) when its median game makes at most this many
    /// blind drags per piece taken off. `tier` is the shallowest such bot, `lookaheads.count` if none.
    var plannedBlindRate = 0.05
    /// `insightGap` is the drop in blind drags per piece from the next shallower bot to the tier's
    /// bot, divided by this and capped at 1; 0 when no bot plans the level (`unplanned`).
    var insightGapScale = 1.0

    // MARK: Choosing

    /// Curve levels are chosen by interest among the finalists within this many points of the
    /// target, on the scale of `DifficultyCurve.targets` (`difficulty` once the targets are on it,
    /// the legacy score before).
    var band = 6.0
    /// Candidates measured per level: the closest to the target. The search stops once this many
    /// are within the band (or the budget runs out); the winner's rivals become the runner-ups.
    var finalists = 4

    /// Peaks that want a board only the 2-deep bot plans, and milestone levels
    /// (`DifficultyCurve.peaks`, `DifficultyCurve.milestones`).
    struct Peaks: Codable, Equatable, Sendable {
        /// Tier a peak's board should reach, planned (not `unplanned`). Finalists that reach it win
        /// over those that do not, in or out of the band.
        var tier = 2
        /// Candidates measured on top of the finalists at a peak where none of them reaches `tier`.
        var extraFinalists = 4
        /// Candidates measured at a milestone; all of them stay as runner-ups for the owner to pick.
        var milestoneFinalists = 8
    }
    /// Optional so that reports written before it existed still read; nil means the defaults.
    var peaks: Peaks? = Peaks()

    // MARK: Scores

    /// interest = insightWeight · insightGap + opennessWeight · (1 − forcedShare) + trapWeight · trapRate
    var insightWeight = 0.6
    var opennessWeight = 0.4
    var trapWeight = 0.0

    /// difficulty = 100 · (tierWeight · tier / lookaheads.count + movesWeight · minMoves / movesScale
    ///                     + setupWeight · setupDepth / setupDepthScale), with no cap at the top.
    var tierWeight = 0.4
    var movesWeight = 0.4
    var setupWeight = 0.2
    var movesScale = 60.0
    var setupDepthScale = 8.0

    // MARK: Traps (optional, slower)

    /// Whether to measure `trapRate`.
    var measureTraps = false
    /// Positions along the solution where traps are counted.
    var trapPositions = 8
    /// Expansions the best-first search gets to finish after a move before that move counts as a trap.
    var trapBudget = 300

    init() {}

    func moveLimit(minMoves: Int) -> Int {
        moveLimitFactor * minMoves + moveLimitExtra
    }

    /// The difficulty formula. `tier` may be fractional: the generator predicts a candidate's
    /// difficulty from its design's usual tier before any bot has played it.
    func difficulty(tier: Double, minMoves: Int, setupDepth: Int) -> Double {
        100 * (tierWeight * tier / Double(max(1, lookaheads.count)) + movesWeight * Double(minMoves) / movesScale
               + setupWeight * Double(setupDepth) / setupDepthScale)
    }

    /// The longest run of solution moves that take nothing off.
    static func setupDepth(of solution: [SolverMove]) -> Int {
        var deepest = 0
        var run = 0
        for move in solution {
            run = move.removed.isEmpty ? run + 1 : 0
            deepest = max(deepest, run)
        }
        return deepest
    }

    /// The formulas as text, written into the generation report.
    var formula: String {
        "difficulty = 100 * (\(tierWeight)*tier/\(lookaheads.count) + \(movesWeight)*minMoves/\(movesScale) + \(setupWeight)*setupDepth/\(setupDepthScale)); "
            + "interest = \(insightWeight)*insightGap + \(opennessWeight)*(1-forcedShare) + \(trapWeight)*trapRate"
    }
}
