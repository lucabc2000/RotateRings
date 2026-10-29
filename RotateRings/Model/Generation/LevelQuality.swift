//
//  LevelQuality.swift
//  RotateRings
//
//  How a level plays, beyond its size (LEVEL-DESIGN.md §14): how far ahead a player has to look,
//  how often the way forward is forced, how deep the preparation runs. Measured on the chosen level
//  and its runner-ups only, because the bots are slow on hub webs. Settings in `QualityConfig`.
//

import Foundation

struct LevelQuality: Codable, Equatable, Sendable {
    /// One bot's games on the level.
    struct Bot: Codable, Equatable, Sendable {
        var lookahead: Int
        /// Share of games cleared within the move limit.
        var winRate: Double
        /// Median over the games of blind drags per piece taken off.
        var blindRate: Double
        /// Mean blind drags per game.
        var meanBlind: Double
    }

    /// Size and foresight: tier, minMoves and setupDepth (`QualityConfig.formula`). 0 and up.
    var difficulty: Double
    /// Whether the level has a moment of insight and room to choose. 0…1.
    var interest: Double
    /// Index of the shallowest bot that plans the level, `bots.count` when none does.
    var tier: Int
    /// No bot plans the level: even the deepest one still drags blind (`tier == bots.count`). Trial
    /// and error as far as the bots can tell; kept visible because the owner has not judged these yet.
    var unplanned: Bool
    /// How much the blind-drag rate drops at that bot, scaled to 0…1. Large: one step has to be
    /// seen in advance and then the rest follows. 0 at tier 0, and 0 when unplanned (nobody finds
    /// the trick).
    var insightGap: Double
    /// Share of solution steps where exactly one piece can make progress. High: tedious.
    var forcedShare: Double
    /// Longest run of solution moves that take nothing off.
    var setupDepth: Int
    /// Share of moves, at positions along the solution, after which a small search cannot finish.
    /// Nil unless `QualityConfig.measureTraps`.
    var trapRate: Double?
    /// Whether the fixed owner-release strategy clears the level without falling back to search.
    var strategySolved: Bool
    var bots: [Bot]
}

enum QualityMeasure {
    /// Measures a solved level. `seed` seeds the bots' random drags, `solution` is the recorded one.
    static func measure(board: Board, solution: [SolverMove], minMoves: Int, seed: UInt64,
                        config: QualityConfig, solverConfig: SolverConfig) -> LevelQuality {
        let botLevel = BotLevel(board: board, config: config)
        let bots = config.lookaheads.map { lookahead -> LevelQuality.Bot in
            let games = botLevel.games(lookahead: lookahead, levelSeed: seed, minMoves: minMoves)
            return LevelQuality.Bot(lookahead: lookahead,
                                    winRate: Double(games.filter(\.won).count) / Double(games.count),
                                    blindRate: median(games.map(\.blindRate)),
                                    meanBlind: Double(games.reduce(0) { $0 + $1.blindMoves }) / Double(games.count))
        }
        let tier = bots.firstIndex { $0.blindRate <= config.plannedBlindRate } ?? bots.count
        let unplanned = tier == bots.count
        let drop = tier > 0 && !unplanned ? bots[tier - 1].blindRate - bots[tier].blindRate : 0
        let insightGap = min(1, max(0, drop) / config.insightGapScale)

        let solver = LevelSolver(board: board, config: solverConfig)
        let steps = solver.openness(along: solution)
        let forcedShare = steps.isEmpty ? 0 : Double(steps.filter { $0.free == 1 }.count) / Double(steps.count)
        let setupDepth = QualityConfig.setupDepth(of: solution)
        let trapRate = config.measureTraps ? traps(solver: solver, solution: solution, config: config) : nil

        let difficulty = config.difficulty(tier: Double(tier), minMoves: minMoves, setupDepth: setupDepth)
        let interest = config.insightWeight * insightGap + config.opennessWeight * (1 - forcedShare)
            + config.trapWeight * (trapRate ?? 0)
        return LevelQuality(difficulty: rounded(difficulty), interest: rounded(interest, places: 3),
                            tier: tier, unplanned: unplanned, insightGap: rounded(insightGap, places: 3), forcedShare: rounded(forcedShare, places: 3),
                            setupDepth: setupDepth, trapRate: trapRate.map { rounded($0, places: 3) },
                            strategySolved: LevelSolver.strategySolves(board, config: solverConfig),
                            bots: bots.map { bot in
                                var bot = bot
                                bot.blindRate = rounded(bot.blindRate, places: 3)
                                bot.meanBlind = rounded(bot.meanBlind, places: 2)
                                return bot
                            })
    }

    /// At up to `trapPositions` evenly spaced positions along the solution, the share of moves after
    /// which best-first search with `trapBudget` expansions finds no way to finish.
    private static func traps(solver: LevelSolver, solution: [SolverMove], config: QualityConfig) -> Double {
        var states = [solver.start]
        var board = solver.board(for: solver.start)
        for move in solution.dropLast() {
            guard case .moved = board.move(move.piece, by: move.delta) else { break }
            states.append(solver.encode(board))
        }
        let count = min(config.trapPositions, states.count)
        guard count > 0 else { return 0 }
        var moves = 0
        var trapped = 0
        for k in 0..<count {
            let state = states[k * states.count / count]
            for (child, _) in solver.successors(of: state) {
                moves += 1
                if solver.bestFirstSolution(from: child, budget: config.trapBudget) == nil { trapped += 1 }
            }
        }
        return moves == 0 ? 0 : Double(trapped) / Double(moves)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    private static func rounded(_ value: Double, places: Int = 1) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }
}
