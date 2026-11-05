//
//  DifficultyCurve.swift
//  RotateRings
//
//  Target difficulty per level from 11 on (scale: `DifficultyScore`). The targets rise in uneven
//  waves: a baseline that climbs from about 25 to 72, with phrases of four to seven levels laid
//  over it that build to a peak and let go again. Phrases differ in length and shape, so hard
//  levels do not fall on every fifth or tenth level, a hard level is usually followed by a
//  lighter one, and now and then there is a level well below the baseline. A light level late in
//  the game still sits far above a light level early on. See LEVEL-DESIGN.md §10.
//

import Foundation

enum DifficultyCurve {
    static let firstCurveLevel = 11
    static let lastLevel = 200
    static let tolerance = 5.0
    /// Whether `targets` are on the scale of `LevelQuality.difficulty` (the planners say so when
    /// they write them) rather than the legacy `DifficultyScore`.
    static let onQualityScale = true

    /// Targets for levels 11...200, in order. 11–100 from `plan-curve.py`; 101–200 from
    /// `plan-chapter.py`, which continues the waves on a baseline of 67 to 76 (§12), then on a
    /// plateau of 68 to 75 near the heaviest designs (§13).
    static let targets: [Double] = [10, 27, 15, 22, 5, 6, 20, 13, 16, 21, 19, 18, 22, 10, 15, 24, 29, 18, 15, 24, 14, 31, 11, 17, 19, 19, 29, 15, 24, 16, 23, 28, 31, 10, 28, 10, 22, 27, 22, 35, 13, 23, 25, 19, 33, 23, 23, 24, 32, 27, 22, 29, 35, 18, 11, 23, 31, 27, 45, 22, 20, 33, 27, 27, 46, 19, 27, 35, 18, 25, 34, 37, 23, 32, 25, 31, 46, 31, 19, 32, 28, 36, 24, 47, 21, 30, 23, 31, 27, 47, 21, 24, 33, 19, 37, 27, 34, 21, 35, 27, 33, 27, 48, 20, 31, 35, 27, 48, 48, 19, 27, 33, 23, 23, 27, 28, 37, 24, 27, 34, 37, 31, 31, 23, 31, 39, 19, 51, 52, 25, 27, 39, 30, 52, 22, 36, 25, 39, 39, 54, 33, 22, 40, 32, 55, 31, 24, 26, 39, 27, 40, 56, 35, 27, 39, 41, 57, 19, 32, 57, 36, 31, 38, 43, 58, 27, 38, 43, 59, 27, 59, 31, 43, 19, 46, 60, 37, 31, 24, 36, 61, 23, 44, 48, 62, 27, 35, 49, 42, 63]

    /// Peaks where the planner put a design whose boards are usually tier 2: the generator wants
    /// such a board there (`QualityConfig.Peaks`). Written by the planners with the targets.
    static let peaks: Set<Int> = [69, 75, 87, 94, 100, 113, 118, 119, 138, 139, 144, 150, 155, 162, 167, 170, 175, 179, 181, 186, 191, 195, 200]
    /// Small breather levels (eight to twelve pieces, after a peak): the most interesting finalist
    /// wins, in or out of the band. Written by the planners.
    static let breathers: Set<Int> = [11, 12, 15, 16, 21, 25, 28, 31, 35, 38, 43, 47, 52, 56, 60, 64, 70, 73, 77, 83, 88, 93, 97, 102, 106, 110, 115, 120, 123, 125, 129, 133, 137, 141, 145, 152, 156, 160, 164, 168, 172, 176, 180, 184, 188, 189, 192, 196]
    /// Chapter ends, where the owner picks the board from more candidates in the Level Browser.
    static let milestones: Set<Int> = [50, 100, 150, 200]

    static func target(level: Int) -> Double? {
        guard level >= firstCurveLevel, level - firstCurveLevel < targets.count else { return nil }
        return targets[level - firstCurveLevel]
    }

    /// Piece-count band for a picture level: the showpieces run to forty pieces (§16, Step 5).
    static let pictureRange = 6...40
    /// Piece-count band for a level: the opening stays small and a breather has ten pieces at most
    /// (LEVEL-DESIGN.md §16); the generator refuses candidates outside it.
    static func pieceRange(level: Int) -> ClosedRange<Int> {
        switch level {
        case ...5: return 2...5
        case 6...10: return 4...8
        case 11...15: return 6...12
        // After 120 the huge board's webs run to 41 pieces (§17).
        default: return breathers.contains(level) ? 5...10 : level > 120 ? 6...42 : 6...34
        }
    }
}
