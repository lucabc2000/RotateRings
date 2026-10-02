//
//  DifficultyCurve.swift
//  RotateRings
//
//  Target difficulty per level for 16–50: a gradual rise with a sawtooth. Every fifth level is a
//  showcase bump and the level after it is a breather.
//
//      base(n) = 20 + 1.7 * (n - 16)
//      offset by n mod 5:  1 → 0 (breather after the showcase), 2 → +5, 3 → −6 (breather),
//                          4 → +1, 0 → +10 (showcase)
//

import Foundation

enum DifficultyCurve {
    static let firstCurveLevel = 16
    static let lastLevel = 50
    static let baseStart = 20.0
    static let basePerLevel = 1.7
    static let tolerance = 6.0

    static func isShowcase(_ level: Int) -> Bool {
        level >= firstCurveLevel && level % 5 == 0
    }

    static func target(level: Int) -> Double? {
        guard level >= firstCurveLevel else { return nil }
        let base = baseStart + basePerLevel * Double(level - firstCurveLevel)
        let offset: Double
        switch level % 5 {
        case 1: offset = 0
        case 2: offset = 5
        case 3: offset = -6
        case 4: offset = 1
        default: offset = 10
        }
        return min(100, max(0, base + offset))
    }

    /// Piece-count band for a level.
    static func pieceRange(level: Int) -> ClosedRange<Int> {
        switch level {
        case ...5: return 2...5
        case 6...10: return 4...8
        case 11...15: return 6...10
        case 16...25: return 8...18
        case 26...40: return 12...28
        default: return 14...30
        }
    }
}
