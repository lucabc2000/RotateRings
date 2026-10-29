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
    static let targets: [Double] = [10, 11, 13, 22, 12, 10, 20, 13, 16, 21, 10, 18, 22, 10, 11, 24, 29, 10, 15, 24, 11, 31, 11, 17, 14, 19, 29, 10, 24, 16, 23, 28, 18, 10, 28, 10, 23, 27, 22, 35, 13, 23, 25, 19, 33, 15, 23, 24, 32, 18, 22, 29, 35, 10, 11, 23, 31, 27, 40, 19, 20, 33, 26, 27, 38, 19, 27, 35, 18, 25, 34, 37, 12, 32, 25, 31, 40, 27, 19, 32, 28, 36, 23, 39, 21, 30, 25, 31, 27, 40, 21, 25, 33, 19, 37, 25, 34, 21, 35, 30, 33, 27, 40, 20, 27, 35, 27, 39, 40, 20, 31, 35, 26, 45, 23, 31, 20, 34, 34, 37, 47, 26, 35, 27, 40, 44, 18, 21, 34, 36, 34, 48, 29, 37, 33, 35, 46, 31, 30, 44, 28, 33, 42, 21, 32, 37, 31, 44, 24, 31, 29, 36, 42, 26, 32, 35, 41, 26, 43, 33, 42, 31, 47, 27, 35, 38, 47, 28, 34, 42, 50, 26, 32, 39, 47, 27, 35, 43, 27, 43, 34, 38, 47, 28, 48, 43, 39, 40, 36, 50]

    static func target(level: Int) -> Double? {
        guard level >= firstCurveLevel, level - firstCurveLevel < targets.count else { return nil }
        return targets[level - firstCurveLevel]
    }

    /// Piece-count band for a level.
    static func pieceRange(level: Int) -> ClosedRange<Int> {
        switch level {
        case ...5: return 2...5
        case 6...10: return 4...8
        default: return 6...34
        }
    }
}
