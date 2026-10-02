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

    @Test func slidingBarAppearsInTheSlideGateSolution() throws {
        // Level 6 introduces the sliding bar (ids starting with "s").
        let board = try LevelLoader.load(level: 6, in: appBundle).makeBoard()
        let result = LevelSolver(board: board).solve()
        let moves = try #require(result.solution)
        #expect(moves.contains { $0.piece.hasPrefix("s") })
        #expect(moves.count <= 5)
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
        func metrics(moves: Int, deadEndRate: Double, branching: Double) -> SolverMetrics {
            SolverMetrics(minMoves: moves, reachableStates: 0, solvableStates: 0, deadEndStates: 0, deadEndMoves: 0,
                          totalMoves: 0, deadEndRate: deadEndRate, branching: branching, fullyExplored: true,
                          isEstimate: false, playouts: nil, elapsed: 0)
        }
        let easy = DifficultyScore.score(metrics: metrics(moves: 1, deadEndRate: 0, branching: 1), pieceCount: 2, distinctKinds: 1)
        let hard = DifficultyScore.score(metrics: metrics(moves: 30, deadEndRate: 0.5, branching: 20), pieceCount: 26, distinctKinds: 6)
        #expect(easy >= 0 && easy < 5)
        #expect(hard == 100)
        let mid = DifficultyScore.score(metrics: metrics(moves: 15, deadEndRate: 0, branching: 1), pieceCount: 2, distinctKinds: 1)
        #expect(mid > easy && mid < hard)
    }
}
