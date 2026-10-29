//
//  Picture.swift
//  RotateRings
//
//  Pictures for milestone levels (LEVEL-DESIGN.md §15, Step 6). A picture fixes the look: rings
//  (where, how big, which are closed, which way the gap would rather face) and bars poking into
//  rings. `FreeKnot` builds the puzzle on it: rings that nearly touch are snapped a stem apart on
//  the 45° lattice and may be clipped together, and the seed picks the ranking, which of those
//  pairs are clipped, the gaps, tails and bombs. The picture fixes the look; the seed picks the
//  puzzle.
//
//  The pictures themselves are JSON files in LevelForge/pictures/, compiled into `PictureLibrary`
//  by LevelForge/pictures.py. Coordinates are board units from the board's centre, y up.
//

import Foundation

struct Picture: Codable, Equatable {
    struct Ring: Codable, Equatable {
        var x: Double
        var y: Double
        var r: Double
        /// Always a closed ring (it only holds).
        var closed: Bool?
        /// Where the gap would rather face, in degrees, when the wiring allows it.
        var gap: Double?
        /// The part's colour (`ForgeRules.colors`); a picture keeps its colours.
        var color: String?
    }

    /// A bar drawing a line. With `ring`: a sliding bar poking into that ring's gap along `degrees`
    /// from its centre, `length` long, or reaching to ring `stop`, whose arc then keeps it from
    /// sliding out until that ring has gone. With `rings` (two, side by side across `degrees`): a
    /// U-bar whose arms sit in both rings' gaps, its crossbar `length` beyond them.
    struct Bar: Codable, Equatable {
        var ring: Int?
        var rings: [Int]?
        var degrees: Double
        var length: Double?
        var stop: Int?
        var color: String?
    }

    var name: String
    var title: String
    var rings: [Ring]
    var bars: [Bar]?
    /// "large" for a picture drawn on the larger board.
    var board: String?
    /// Most clips one open ring carries (2 when absent): a ring between three single neighbours
    /// needs 3.
    var clips: Int?

    var boardSize: BoardSize { board == "large" ? .large : .standard }
}
