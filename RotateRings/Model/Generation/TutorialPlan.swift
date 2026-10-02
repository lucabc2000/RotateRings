//
//  TutorialPlan.swift
//  RotateRings
//
//  What each of the first fifteen levels must teach and the constraints its candidates must meet.
//  Levels 16–50 take their designs from `Compositions`.
//

import Foundation

struct LevelGoal {
    let level: Int
    let templates: [LevelTemplate]
    /// The piece kind this level introduces; the candidate must feature it (see `LevelGenerator`).
    let newKind: PieceKind?
    let pieceRange: ClosedRange<Int>
    let targetMinMoves: Int
    /// Most moves from solvable states that may lead into a dead end.
    let maxDeadEndMoves: Int
    /// Level 1 only: the first solution move is a single step that removes a piece.
    let firstMoveFrees: Bool
    /// Curve target for levels 16+.
    let targetDifficulty: Double?
    /// Hard levels pick the candidate with the fewest free pieces instead of the one closest to
    /// the curve.
    var isHard = false

    var isTutorial: Bool { level <= 15 }
}

enum TutorialPlan {
    static func goal(for level: Int) -> LevelGoal {
        switch level {
        case 1:
            return LevelGoal(level: 1, templates: [MotifCatalog.single("ringChain2", lockRange: 1...1)],
                             newKind: .cRing, pieceRange: 2...3, targetMinMoves: 1, maxDeadEndMoves: 0, firstMoveFrees: true, targetDifficulty: nil)
        case 2:
            return LevelGoal(level: 2, templates: [MotifCatalog.single("ringChain3", lockRange: 1...2), MotifCatalog.single("ringCorner", lockRange: 1...2)],
                             newKind: .cRing, pieceRange: 2...3, targetMinMoves: 2, maxDeadEndMoves: 0, firstMoveFrees: false, targetDifficulty: nil)
        case 3:
            return LevelGoal(level: 3, templates: [MotifCatalog.single("anchorStar2", lockRange: 1...2), MotifCatalog.single("concentric", lockRange: 1...2)],
                             newKind: .closedRing, pieceRange: 2...5, targetMinMoves: 2, maxDeadEndMoves: 0, firstMoveFrees: false, targetDifficulty: nil)
        case 4:
            return LevelGoal(level: 4, templates: [MotifCatalog.single("anchorStar3", lockRange: 1...3), MotifCatalog.single("anchorStar4", lockRange: 1...2), MotifCatalog.single("concentricSatellite", lockRange: 1...3)],
                             newKind: .closedRing, pieceRange: 3...5, targetMinMoves: 3, maxDeadEndMoves: 0, firstMoveFrees: false, targetDifficulty: nil)
        case 5:
            // The sliding bar: slide it out of its hub, then the ring it was blocking can turn.
            return LevelGoal(level: 5, templates: [MotifCatalog.single("slideLatch", lockRange: 1...2), MotifCatalog.single("slideLatch", lockRange: 1...2), MotifCatalog.single("slideLatch2", lockRange: 1...2)],
                             newKind: .slideBar, pieceRange: 3...5, targetMinMoves: 2, maxDeadEndMoves: 0, firstMoveFrees: false, targetDifficulty: nil)
        case 6:
            return LevelGoal(level: 6, templates: [MotifCatalog.single("slideGate", lockRange: 1...2), MotifCatalog.single("slideLatch2", lockRange: 2...2)],
                             newKind: .slideBar, pieceRange: 4...6, targetMinMoves: 3, maxDeadEndMoves: 3, firstMoveFrees: false, targetDifficulty: nil)
        case 7:
            // The L-bar: its leg cannot pass the hub, so it only slides out one way.
            return LevelGoal(level: 7, templates: [MotifCatalog.single("elbowSlide", lockRange: 1...2), MotifCatalog.single("elbowSlide", lockRange: 1...2), MotifCatalog.single("elbowSlide2", lockRange: 1...2)],
                             newKind: .lBar, pieceRange: 3...6, targetMinMoves: 2, maxDeadEndMoves: 3, firstMoveFrees: false, targetDifficulty: nil)
        case 8:
            return LevelGoal(level: 8, templates: [
                MotifCatalog.stack(count: 2, pool: ["ringChain2", "anchorStar2", "slideLatch", "concentric"], required: ["elbowSlide"], lockRange: 1...3, idSuffix: "hook"),
                MotifCatalog.stack(count: 2, pool: ["ringChain2", "anchorStar2", "concentric"], required: ["elbowSlide2"], lockRange: 1...3, idSuffix: "elbow"),
            ], newKind: .lBar, pieceRange: 6...8, targetMinMoves: 4, maxDeadEndMoves: 3, firstMoveFrees: false, targetDifficulty: nil)
        case 9:
            return LevelGoal(level: 9, templates: [MotifCatalog.single("tailGate", lockRange: 1...2)],
                             newKind: .tailRing, pieceRange: 4...6, targetMinMoves: 2, maxDeadEndMoves: 3, firstMoveFrees: false, targetDifficulty: nil)
        case 10:
            return LevelGoal(level: 10, templates: [MotifCatalog.single("tailClip2", lockRange: 1...3)],
                             newKind: .tailRing, pieceRange: 4...8, targetMinMoves: 2, maxDeadEndMoves: 3, firstMoveFrees: false, targetDifficulty: nil)
        case 11...15:
            let count = level <= 12 ? 2 : 3
            let pool = count == 2 ? MotifCatalog.compact : MotifCatalog.small
            let lock = level <= 13 ? 1...2 : 1...3
            return LevelGoal(level: level, templates: [
                MotifCatalog.stack(count: count, pool: pool, lockRange: lock, idSuffix: "mix"),
                MotifCatalog.stack(count: count, pool: pool, required: [rotatingPick(level)], lockRange: lock, idSuffix: "feature"),
            ], newKind: nil, pieceRange: 6...10, targetMinMoves: 3 + (level - 11), maxDeadEndMoves: level >= 14 ? 5 : 3, firstMoveFrees: false, targetDifficulty: nil)
        default:
            return LevelGoal(level: level, templates: Compositions.templates(level: level), newKind: nil,
                             pieceRange: DifficultyCurve.pieceRange(level: level), targetMinMoves: 0, maxDeadEndMoves: .max,
                             firstMoveFrees: false, targetDifficulty: DifficultyCurve.target(level: level),
                             isHard: Compositions.hardLevels.contains(level))
        }
    }

    /// Levels 11–15 each put one of the taught motifs centre stage.
    private static func rotatingPick(_ level: Int) -> String {
        ["elbowLatch", "tailGate", "elbowSlide", "tailClip", "slideLatch"][(level - 11) % 5]
    }
}
