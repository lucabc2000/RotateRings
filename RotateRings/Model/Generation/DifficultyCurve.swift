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
    static let lastLevel = 100
    static let tolerance = 5.0

    /// Targets for levels 11...100, in order.
    static let targets: [Double] = [23, 25, 27, 36, 27, 17, 35, 29, 32, 38, 20, 35, 40, 25, 30, 42, 48, 21, 35, 45, 31, 52, 32, 39, 35, 41, 52, 30, 48, 39, 47, 52, 43, 34, 53, 32, 49, 53, 49, 61, 40, 50, 53, 47, 61, 43, 52, 53, 62, 47, 52, 59, 66, 40, 43, 54, 63, 59, 73, 52, 53, 66, 60, 61, 73, 53, 62, 70, 54, 61, 70, 73, 49, 69, 63, 69, 78, 65, 58, 71, 68, 75, 63, 79, 62, 71, 67, 72, 68, 85]

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
