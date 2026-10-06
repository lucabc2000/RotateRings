//
//  LevelTests.swift
//  RotateRingsTests
//
//  Level format decoding, plus checks that every bundled level matches the generator's report:
//  it loads, its recorded solution completes it, and the tutorial levels keep their exact metrics.
//

import Foundation
import Testing
@testable import RotateRings

private let appBundle = Bundle(for: GameScene.self)
private let levelNumbers = Array(1...max(1, LevelLoader.levelCount(in: appBundle)))

struct LevelTests {

    @Test func bundleContainsAllGeneratedLevels() throws {
        let report = try LevelLoader.loadReport(in: appBundle)
        let count = LevelLoader.levelCount(in: appBundle)
        #expect(count == report.levels.count)
        #expect(report.levels.map(\.number) == Array(1...count))
    }

    @Test(arguments: levelNumbers)
    func levelLoadsAndBuildsBoard(number: Int) throws {
        let file = try LevelLoader.load(level: number, in: appBundle)
        #expect(file.id == number)
        #expect(file.board.width > 0 && file.board.height > 0)
        var board = try file.makeBoard()
        #expect(board.pieces.count == file.pieces.count)
        // Every piece in a well formed level is held by something at the start: a connection, or
        // contact with another piece (free bars). Nothing may leave the board on load.
        let droppedOnLoad = board.removeUnconnectedPieces()
        #expect(droppedOnLoad.isEmpty, "level \(number) drops \(droppedOnLoad) on load")
    }

    @Test(arguments: levelNumbers)
    func recordedSolutionCompletesLevel(number: Int) throws {
        let report = try LevelLoader.loadReport(in: appBundle)
        let entry = try #require(report.levels.first { $0.number == number })
        var board = try LevelLoader.load(level: number, in: appBundle).makeBoard()
        let completed = board.replay(entry.chosen.solution)
        #expect(completed, "level \(number) solution from the report does not complete the level")
        #expect(entry.chosen.solution.count == entry.chosen.metrics.minMoves)
    }

    @Test(arguments: levelNumbers.filter { $0 <= 10 })
    func tutorialLevelMetricsMatchReport(number: Int) throws {
        let report = try LevelLoader.loadReport(in: appBundle)
        let entry = try #require(report.levels.first { $0.number == number })
        let board = try LevelLoader.load(level: number, in: appBundle).makeBoard()
        let result = LevelSolver(board: board, config: report.solverConfig).solve()
        #expect(result.metrics.fullyExplored)
        #expect(result.metrics.minMoves == entry.chosen.metrics.minMoves)
        #expect(result.metrics.deadEndMoves == entry.chosen.metrics.deadEndMoves)
        if number <= 5 {
            #expect(result.metrics.deadEndMoves == 0)
        }
    }

    @Test func candidatesFileContainsEveryRunnerUp() throws {
        let report = try LevelLoader.loadReport(in: appBundle)
        let store = try LevelLoader.loadCandidates(in: appBundle)
        for level in report.levels {
            for runnerUp in level.runnerUps {
                #expect(store.candidates[runnerUp.id] != nil, "missing candidate file for \(runnerUp.id)")
            }
        }
    }

    @Test func missingLevelThrows() {
        #expect(throws: LevelError.fileNotFound(level: 999)) {
            try LevelLoader.load(level: 999, in: appBundle)
        }
    }

    @Test func decodesShapesAndDefaults() throws {
        let json = """
        {
          "id": 7, "name": "T", "board": { "width": 100, "height": 200 },
          "pieces": [
            { "id": "bar", "position": [10, 20],
              "shapes": [ { "segment": { "from": [-10, 0], "to": [30, 0] } } ],
              "clips": [ { "stemStart": [30, 0], "stemEnd": [50, 0], "grips": "ring" } ] },
            { "id": "ring", "color": "sky", "position": [110, 20], "rotation": 90,
              "shapes": [ { "arc": { "center": [0, 0], "radius": 50, "start": 40, "sweep": 280 } } ] }
          ]
        }
        """
        let file = try LevelLoader.decode(Data(json.utf8))
        #expect(file.pieces[0].color == nil)
        let board = try file.makeBoard()
        let ring = try #require(board.piece("ring"))
        #expect(ring.color == "sky")
        #expect(ring.rotation.isApproximately(.pi / 2))
        #expect(ring.ringArc?.radius == 50)
        let bar = try #require(board.piece("bar"))
        // A latch bar turns (in principle) and has no hub; only sliding pieces have one.
        #expect(bar.motion == .rotation)
        #expect(!bar.hasHub)
        #expect(bar.ringArc == nil)
        #expect(board.connections == [Connection(owner: "bar", clipIndex: 0, ring: "ring")])
    }

    @Test func decodesSlidingPieceWithHubAxisAndRejectsBadOnes() throws {
        // A slide piece: position is the hub, rotation the axis, the segment on local x the arm.
        let good = """
        { "id": 1, "name": "x", "board": { "width": 1, "height": 1 },
          "pieces": [ { "id": "s", "motion": "slide", "position": [50, 50], "rotation": 90,
                        "shapes": [ { "segment": { "from": [-40, 0], "to": [60, 0] } },
                                    { "segment": { "from": [60, 0], "to": [60, 30] } } ] } ] }
        """
        let board = try LevelLoader.decode(Data(good.utf8)).makeBoard()
        let piece = try #require(board.piece("s"))
        #expect(piece.hasHub)
        #expect(piece.slideAxis.y.isApproximately(1))
        #expect(piece.axialArm == Segment(from: Point(-40, 0), to: Point(60, 0)))
        #expect(board.connections == [Connection(holderOf: "s")])

        // No segment parallel to the axis: nothing runs through a hub. (A parallel segment off the
        // axis would be an arm with its own hub, as in a U-bar.)
        let noArm = """
        { "id": 1, "name": "x", "board": { "width": 1, "height": 1 },
          "pieces": [ { "id": "s", "motion": "slide", "position": [0, 0],
                        "shapes": [ { "segment": { "from": [0, 10], "to": [60, 40] } } ] } ] }
        """
        #expect(throws: LevelError.slideBarWithoutAxialArm(piece: "s")) {
            try LevelLoader.decode(Data(noArm.utf8)).makeBoard()
        }

        // A turning bar without a clip is neither a latch nor a hub bar.
        let loose = """
        { "id": 1, "name": "x", "board": { "width": 1, "height": 1 },
          "pieces": [ { "id": "b", "position": [0, 0],
                        "shapes": [ { "segment": { "from": [-20, 0], "to": [60, 0] } } ] } ] }
        """
        #expect(throws: LevelError.turningBarWithoutClip(piece: "b")) {
            try LevelLoader.decode(Data(loose.utf8)).makeBoard()
        }
    }

    @Test func rejectsUnknownShapeKey() {
        let json = """
        { "id": 1, "name": "x", "board": { "width": 1, "height": 1 },
          "pieces": [ { "id": "p", "position": [0, 0], "shapes": [ { "blob": {} } ] } ] }
        """
        #expect(throws: DecodingError.self) {
            try LevelLoader.decode(Data(json.utf8))
        }
    }

    @Test func rejectsClipThatMissesItsRing() throws {
        let json = """
        { "id": 1, "name": "x", "board": { "width": 1, "height": 1 },
          "pieces": [
            { "id": "p", "position": [0, 0],
              "shapes": [ { "segment": { "from": [0, 0], "to": [20, 0] } } ],
              "clips": [ { "stemStart": [20, 0], "stemEnd": [40, 0], "grips": "r" } ] },
            { "id": "r", "position": [100, 0],
              "shapes": [ { "arc": { "center": [0, 0], "radius": 30, "start": 0, "sweep": 300 } } ] }
          ] }
        """
        let file = try LevelLoader.decode(Data(json.utf8))
        #expect(throws: LevelError.clipNotOnRing(piece: "p", clipIndex: 0, target: "r")) {
            try file.makeBoard()
        }
    }

    @Test func rejectsGripOnUnknownPiece() throws {
        let json = """
        { "id": 1, "name": "x", "board": { "width": 1, "height": 1 },
          "pieces": [ { "id": "p", "position": [0, 0],
                        "shapes": [ { "arc": { "center": [0,0], "radius": 10, "start": 0, "sweep": 300 } } ],
                        "clips": [ { "stemStart": [0,0], "stemEnd": [1,1], "grips": "nope" } ] } ] }
        """
        let file = try LevelLoader.decode(Data(json.utf8))
        #expect(throws: LevelError.unknownGripTarget(piece: "p", target: "nope")) {
            try file.makeBoard()
        }
    }

    @Test func roundTripsThroughCodable() throws {
        let file = try LevelLoader.load(level: 3, in: appBundle)
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(LevelFile.self, from: data)
        #expect(decoded == file)
    }
}
