//
//  LevelReport.swift
//  RotateRings
//
//  The files the generator writes next to the level JSON, read back by the Level Browser:
//  - `levels-report.json`: metrics, difficulty, solution and runner-ups for every level;
//  - `levels-candidates.json`: the runner-up level files, keyed by candidate id;
//  - `level-selection.json`: the user's pins, so a rerun keeps swapped candidates.
//

import Foundation

struct LevelReport: Codable, Equatable, Sendable {
    static let currentVersion = 1

    /// One generated level, chosen or runner-up.
    struct Candidate: Codable, Equatable, Sendable {
        /// `level07-s12345`; also the key in `CandidateStore`.
        var id: String
        var seed: UInt64
        var template: String
        var pieceCount: Int
        /// Distinct `PieceKind` raw values present, sorted.
        var kinds: [String]
        var metrics: SolverMetrics
        var difficulty: Double
        var solution: [SolverMove]
    }

    struct Level: Codable, Equatable, Sendable {
        var number: Int
        var name: String
        var chosen: Candidate
        /// True when the chosen candidate came from `level-selection.json` rather than the selection rule.
        var pinned: Bool
        /// Curve target for levels 16–50; nil for tutorial levels.
        var targetDifficulty: Double?
        var runnerUps: [Candidate]
    }

    var version: Int
    var generatedAt: Date
    var masterSeed: UInt64
    var solverConfig: SolverConfig
    var difficultyFormula: String
    var levels: [Level]

    static func candidateID(level: Int, seed: UInt64) -> String {
        String(format: "level%02d-s%llu", level, seed)
    }
}

/// Runner-up level files, so the browser can play them without them being numbered levels.
struct CandidateStore: Codable, Equatable, Sendable {
    var version: Int
    var candidates: [String: LevelFile]
}

/// Which candidate the user wants for a level. Written by the browser's export, read by the generator.
struct LevelSelection: Codable, Equatable, Sendable {
    struct Pin: Codable, Equatable, Sendable {
        var seed: UInt64
        var template: String
    }

    var version: Int
    /// Level number (as a string, JSON keys) → pin.
    var pins: [String: Pin]

    func pin(for level: Int) -> Pin? {
        pins[String(level)]
    }
}

enum LevelResources {
    static let report = "levels-report"
    static let candidates = "levels-candidates"
    static let selection = "level-selection"
}
