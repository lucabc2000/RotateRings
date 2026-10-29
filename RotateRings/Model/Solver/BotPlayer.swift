//
//  BotPlayer.swift
//  RotateRings
//
//  Players of fixed skill, for measuring how much thought a level takes (LEVEL-DESIGN.md §14). A bot
//  with lookahead k looks k + 1 drags ahead: when some sequence of that many drags takes a piece off
//  the board, it plays the first drag of the shortest one; otherwise it drags something at random.
//  How often each bot clears a level within a move limit is the level's bot profile: a level that
//  only the far-sighted bots clear has a step that has to be seen in advance.
//
//  Rules are never re-implemented here. The bot plays its drags on a real `Board` with
//  `Board.move`, the call that replays a solver solution; the lookahead searches with
//  `LevelSolver.successors`, which goes through `Board.obstruction` and `Board.applyFreeMove`. Each
//  independent part of the board (`LevelSolver.components`) is searched on its own.
//
//  Everything is deterministic: random drags come from `SplitMix64` seeded from the level seed, the
//  bot and the game, and every limit counts positions, not seconds.
//

import Foundation

/// A level prepared for bots: one solver per independent part of the board, and the positions the
/// bots have already worked out, shared by every game on the level. The caches change how fast a
/// profile is measured, never its result.
final class BotLevel {
    let start: Board
    let config: QualityConfig
    private let parts: [LevelSolver]
    private var successorCache: [[Exact: [(state: LevelSolver.State, move: SolverMove)]]]
    /// Per depth, per part: the plan found from a position (nil inside when there is none).
    private var plans: [Int: [[Exact: Plan?]]] = [:]
    /// Drags the board refused although the solver offered them. Should stay 0; anything else is a
    /// disagreement between solver and board like the one `Failure.replayFails` guards against.
    private(set) var refusedMoves = 0
    private static let cacheLimit = 40_000

    /// A state keyed by its exact bar offsets too, so a cached answer is only reused for the very
    /// board it was worked out on.
    private struct Exact: Hashable {
        let state: LevelSolver.State
        static func == (a: Exact, b: Exact) -> Bool { a.state.isExactly(b.state) }
        func hash(into hasher: inout Hasher) { hasher.combine(state) }
    }

    struct Plan {
        let move: SolverMove
        /// Drags until a piece comes off, this one included.
        let length: Int
    }

    init(board: Board, config: QualityConfig) {
        var board = board
        board.removeUnconnectedPieces()
        start = board
        self.config = config
        parts = LevelSolver.componentBoards(of: board).map { LevelSolver(board: $0) }
        successorCache = Array(repeating: [:], count: parts.count)
    }

    private func successors(part p: Int, of state: LevelSolver.State) -> [(state: LevelSolver.State, move: SolverMove)] {
        if let cached = successorCache[p][Exact(state: state)] { return cached }
        let result = parts[p].successors(of: state)
        if successorCache[p].count < Self.cacheLimit { successorCache[p][Exact(state: state)] = result }
        return result
    }

    private static func remaining(_ state: LevelSolver.State) -> Int {
        state.values.reduce(0) { $0 + ($1 == LevelSolver.removed ? 0 : 1) }
    }

    /// The first drag of the shortest sequence of at most `depth` drags in part `p` that takes a piece
    /// off the board, breadth first in the solver's move order. Nil when there is none, or none
    /// within the lookahead budget.
    private func plan(part p: Int, from origin: LevelSolver.State, depth: Int) -> Plan? {
        if let cached = plans[depth]?[p][Exact(state: origin)] { return cached }
        let pieces = Self.remaining(origin)
        var seen: Set<LevelSolver.State> = [origin]
        var frontier: [(state: LevelSolver.State, first: SolverMove?)] = [(origin, nil)]
        var expansions = 0
        var found: Plan?
        search: for level in 1...depth {
            var next: [(state: LevelSolver.State, first: SolverMove?)] = []
            for (state, first) in frontier {
                guard expansions < config.lookaheadBudget else { break search }
                expansions += 1
                for (child, move) in successors(part: p, of: state) where seen.insert(child).inserted {
                    let opening = first ?? move
                    if Self.remaining(child) < pieces {
                        found = Plan(move: opening, length: level)
                        break search
                    }
                    if level < depth { next.append((child, opening)) }
                }
            }
            frontier = next
        }
        if plans[depth] == nil { plans[depth] = Array(repeating: [:], count: parts.count) }
        plans[depth]![p][Exact(state: origin)] = .some(found)
        return found
    }

    /// One game by a bot.
    struct Game {
        var won: Bool
        /// Drags played, all of them when the game was lost.
        var moves: Int
        /// Drags made at random because the lookahead found no piece to take off.
        var blindMoves: Int
        /// Pieces taken off the board, all of them when the game was won.
        var removed: Int

        /// Blind drags per piece taken off: how much of the game was trial and error, independent
        /// of the size of the board.
        var blindRate: Double { Double(blindMoves) / Double(max(1, removed)) }
    }

    /// One game by a bot with `lookahead`, lost after `maxMoves` drags.
    func play(lookahead: Int, rng: inout SplitMix64, maxMoves: Int) -> Game {
        var board = start
        var game = Game(won: false, moves: 0, blindMoves: 0, removed: 0)
        func end(won: Bool) -> Game {
            game.won = won
            game.removed = start.pieces.count - board.pieces.count
            return game
        }
        while !board.isComplete {
            guard game.moves < maxMoves else { return end(won: false) }
            let states = parts.map { $0.encode(board) }
            var best: Plan?
            for (p, state) in states.enumerated() where Self.remaining(state) > 0 {
                if let plan = plan(part: p, from: state, depth: lookahead + 1), plan.length < (best?.length ?? .max) {
                    best = plan
                }
            }
            var options = states.enumerated().flatMap { p, state in successors(part: p, of: state).map(\.move) }
            var planned = best?.move
            if planned == nil { game.blindMoves += 1 }
            // The board has the last word: a drag it refuses is not available. Count it (it should
            // never happen, see `refusedMoves`) and choose again.
            while true {
                let move: SolverMove
                if let next = planned {
                    move = next
                    planned = nil
                } else {
                    guard !options.isEmpty else { return end(won: false) }
                    move = options.remove(at: rng.int(in: 0...(options.count - 1)))
                }
                if case .moved = board.move(move.piece, by: move.delta) { break }
                refusedMoves += 1
                options.removeAll { $0 == move }
            }
            game.moves += 1
        }
        return end(won: true)
    }

    /// `config.runs` games by the bot with `lookahead`, each with its own random drags.
    func games(lookahead: Int, levelSeed: UInt64, minMoves: Int) -> [Game] {
        let limit = config.moveLimit(minMoves: minMoves)
        return (0..<config.runs).map { run in
            var rng = SplitMix64(seed: levelSeed).derived(UInt64(lookahead) &+ 1).derived(UInt64(run) &+ 1)
            return play(lookahead: lookahead, rng: &rng, maxMoves: limit)
        }
    }

    /// Share of games each bot of `config.lookaheads` clears, in that order.
    func profile(levelSeed: UInt64, minMoves: Int) -> [Double] {
        config.lookaheads.map { lookahead in
            let games = games(lookahead: lookahead, levelSeed: levelSeed, minMoves: minMoves)
            return Double(games.filter(\.won).count) / Double(games.count)
        }
    }
}
