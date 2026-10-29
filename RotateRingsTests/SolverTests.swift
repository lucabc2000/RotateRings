//
//  SolverTests.swift
//  RotateRingsTests
//
//  The solver must agree with the board rules and report the metrics the generator relies on.
//

import Foundation
import Testing
@testable import RotateRings

private let appBundle = Bundle(for: GameScene.self)

struct SolverTests {

    @Test func twoRingsAreSolvedInOneDragWithNoDeadEnds() {
        let board = Make.twoRingBoard()
        let result = LevelSolver(board: board).solve()
        #expect(result.isSolvable)
        #expect(result.metrics.fullyExplored)
        #expect(!result.metrics.isEstimate)
        // b turns its gap from 180° to 90° in one drag of two steps; a's clip slips off and both leave.
        #expect(result.metrics.minMoves == 1)
        #expect(result.solution?.first?.piece == "b")
        #expect(abs(result.solution?.first?.steps ?? 0) == 2)
        // b has eight positions; one of them is the goal itself, so eight states in total.
        #expect(result.metrics.reachableStates == 8)
        #expect(result.metrics.deadEndMoves == 0)
        #expect(result.metrics.deadEndStates == 0)
        var replay = board
        let replayed = replay.replay(result.solution ?? [])
        #expect(replayed)
    }

    /// Ring X is gripped by A (above, at X's 90°) and B (right, at X's 0°). A also grips E, to the
    /// right of A. B has a tail that reaches into E's gap, so E cannot turn until B has left.
    ///
    /// Clips are sleeves: after X frees A's clip, X can still turn through it (and would grip it
    /// again on the way back), so there is no trap here. Every order of moves can still finish.
    private func sleeveBoard() -> Board {
        let x = Make.ring("x", at: .zero, gapCenterDegrees: 135)
        let a = Make.ring("a", at: Point(0, 120), gapCenterDegrees: 90, clips: [
            Make.downClip(grips: "x"),
            Clip(stemStart: Point(50, 0), stemEnd: Point(70, 0), grips: "e"),
        ])
        let e = Make.ring("e", at: Point(120, 120), gapCenterDegrees: 270)
        let b = Piece(id: "b", position: Point(120, 0), shapes: [
            .arc(Arc(center: .zero, radius: 50, start: AngleMath.radians(fromDegrees: 40), sweep: AngleMath.radians(fromDegrees: 280))),
            .segment(Segment(from: Point(0, 50), to: Point(0, 75))),
        ], clips: [Make.leftClip(grips: "x")])
        return Board(pieces: [x, a, e, b])
    }

    @Test func sleevesLeaveNoDeadEndsAndStatesCanRegainConnections() {
        let board = sleeveBoard()
        #expect(board.connections.count == 3)
        let result = LevelSolver(board: board).solve()
        #expect(result.isSolvable)
        #expect(result.metrics.fullyExplored)
        #expect(result.metrics.minMoves == 3)
        #expect(result.metrics.deadEndMoves == 0)
        #expect(result.metrics.deadEndStates == 0)
        var replay = board
        let replayed = replay.replay(result.solution ?? [])
        #expect(replayed)
    }

    @Test func closedRingGrippedByClosedRingIsUnsolvable() {
        let inner = Make.closedRing("inner", at: .zero, radius: 40)
        let outer = Make.closedRing("outer", at: .zero, radius: 65,
                                    clips: [Clip(stemStart: Point(0, 65), stemEnd: Point(0, 40), grips: "inner")])
        let result = LevelSolver(board: Board(pieces: [inner, outer])).solve()
        #expect(!result.isSolvable)
        #expect(result.metrics.fullyExplored)
        // The inner ring is rotation invariant and the outer ring is pinned, so nothing ever moves.
        #expect(result.metrics.reachableStates == 1)
        #expect(result.solution == nil)
    }

    @Test(arguments: [1, 2, 3])
    func bundledLevelsAreSolvedExactly(number: Int) throws {
        let board = try LevelLoader.load(level: number, in: appBundle).makeBoard()
        let result = LevelSolver(board: board).solve()
        #expect(result.isSolvable)
        #expect(result.metrics.fullyExplored)
        #expect(result.metrics.minMoves >= 1 && result.metrics.minMoves <= 6)
        var replay = board
        let replayed = replay.replay(result.solution ?? [])
        #expect(replayed)
    }

    /// Even the bot without foresight clears the first levels, and a profile repeats exactly.
    @Test(arguments: [1, 5, 8])
    func botsClearTutorialLevelsReproducibly(number: Int) throws {
        let board = try LevelLoader.load(level: number, in: appBundle).makeBoard()
        var config = QualityConfig()
        config.runs = 5
        let profile = BotLevel(board: board, config: config).profile(levelSeed: 42, minMoves: 4)
        #expect(profile == Array(repeating: 1, count: config.lookaheads.count))
        #expect(BotLevel(board: board, config: config).profile(levelSeed: 42, minMoves: 4) == profile)
    }

    @Test func slidingBarAppearsInTheSlideGateSolution() throws {
        // Level 6 introduces the sliding bar (ids starting with "s").
        let board = try LevelLoader.load(level: 6, in: appBundle).makeBoard()
        let result = LevelSolver(board: board).solve()
        let moves = try #require(result.solution)
        #expect(moves.contains { $0.piece.hasPrefix("s") })
        #expect(moves.count <= 5)
    }

    /// Every drag the solver offers must be one the real board accepts, landing exactly where the
    /// solver says. Walks real boards, never rebuilt from solver states, breadth first on levels with
    /// sliding bars, where a push stops at whatever spot the board's sampling finds. Levels with
    /// sliding bars; 29, 83 and 149 have the most of them (19–22).
    @Test(arguments: [6, 16, 29, 66, 83, 93, 149, 178])
    func solverMovesAreAcceptedByTheBoard(number: Int) throws {
        var start = try LevelLoader.load(level: number, in: appBundle).makeBoard()
        start.removeUnconnectedPieces()
        #expect(start.pieces.contains { $0.motion == .slide })
        let solver = LevelSolver(board: start)
        var queue = [start]
        var seen: Set<LevelSolver.State> = [solver.encode(start)]
        var head = 0
        while head < queue.count && head < 150 {
            let real = queue[head]
            head += 1
            for (next, move) in solver.successors(of: solver.encode(real)) {
                var board = real
                guard case .moved = board.move(move.piece, by: move.delta) else {
                    Issue.record("level \(number): the board refuses \(move.piece) by \(move.delta)")
                    continue
                }
                let landed = solver.encode(board)
                #expect(landed.isExactly(next), "level \(number): \(move.piece) by \(move.delta) lands elsewhere")
                if seen.insert(landed).inserted { queue.append(board) }
            }
        }
    }

    @Test func stateCapFallsBackToAnEstimateWithASolution() throws {
        let board = try LevelLoader.load(level: 1, in: appBundle).makeBoard()
        var config = SolverConfig()
        config.stateCap = 3
        let result = LevelSolver(board: board, config: config).solve()
        #expect(result.isSolvable)
        #expect(result.metrics.isEstimate)
        #expect(!result.metrics.fullyExplored)
        var replay = board
        let replayed = replay.replay(result.solution ?? [])
        #expect(replayed)
    }

    @Test func difficultyScoreIsBoundedAndMonotonic() {
        func metrics(moves: Int, freedom: Double, setup: Int) -> SolverMetrics {
            var result = SolverMetrics(minMoves: moves, reachableStates: 0, solvableStates: 0, deadEndStates: 0, deadEndMoves: 0,
                                       totalMoves: 0, deadEndRate: 0, branching: 1, fullyExplored: true,
                                       isEstimate: false, playouts: nil, elapsed: 0)
            result.freedom = freedom
            result.setupMoves = setup
            return result
        }
        let easy = DifficultyScore.score(metrics: metrics(moves: 1, freedom: 0.6, setup: 0), pieceCount: 2, distinctKinds: 1)
        let hard = DifficultyScore.score(metrics: metrics(moves: 40, freedom: 0.1, setup: 12), pieceCount: 28, distinctKinds: 6)
        #expect(easy == 0)
        #expect(hard == 100)
        let mid = DifficultyScore.score(metrics: metrics(moves: 20, freedom: 0.3, setup: 4), pieceCount: 15, distinctKinds: 3)
        #expect(mid > easy && mid < hard)
    }
}
