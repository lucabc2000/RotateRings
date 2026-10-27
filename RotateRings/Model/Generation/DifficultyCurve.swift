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

    /// Targets for levels 11...200, in order. 11–100 from `plan-curve.py`; 101–200 from
    /// `plan-chapter.py`, which continues the waves on a baseline of 67 to 76 (§12), then on a
    /// plateau of 68 to 75 near the heaviest designs (§13).
    static let targets: [Double] = [23, 25, 27, 36, 27, 17, 35, 29, 32, 38, 20, 35, 40, 25, 30, 42, 48, 21, 35, 45, 31, 52, 32, 39, 35, 41, 52, 30, 48, 39, 47, 52, 43, 34, 53, 32, 49, 53, 49, 61, 40, 50, 53, 47, 61, 43, 52, 53, 62, 47, 52, 59, 66, 40, 43, 54, 63, 59, 73, 52, 53, 66, 60, 61, 73, 53, 62, 70, 54, 61, 70, 73, 49, 69, 63, 69, 78, 65, 58, 71, 68, 75, 63, 79, 62, 71, 67, 72, 68, 85, 60, 64, 62, 65, 73, 76, 58, 65, 69, 76, 59, 79, 68, 71, 78, 62, 72, 65, 75, 80, 60, 72, 76, 69, 79, 64, 69, 69, 76, 66, 77, 73, 82, 67, 73, 80, 82, 62, 67, 73, 79, 79, 82, 72, 73, 77, 82, 68, 72, 82, 64, 74, 62, 68, 72, 77, 58, 71, 65, 74, 76, 61, 61, 71, 76, 72, 80, 65, 67, 69, 75, 61, 80, 76, 71, 72, 80, 69, 65, 78, 68, 78, 71, 77, 80, 67, 66, 73, 76, 76, 80, 68, 72, 73, 78, 66, 80, 69, 71, 80]

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
