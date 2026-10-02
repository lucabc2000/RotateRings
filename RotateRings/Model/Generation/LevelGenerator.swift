//
//  LevelGenerator.swift
//  RotateRings
//
//  Produces candidates for a level from seeds, solves and scores them, and picks the best one.
//  Everything is deterministic: the same master seed and pins give the same files.
//

import Foundation

struct GeneratorConfig {
    var masterSeed: UInt64 = 20_261_002
    /// Candidates tried per tutorial level.
    var tutorialCandidates = 8
    /// Most candidates tried per curve level before settling for the closest.
    var maxCandidates = 16
    var solver = SolverConfig()
    /// Parallel candidate evaluations.
    var jobs = 4
    /// Level number → candidate seed the user chose in the Level Browser.
    var pins: [Int: UInt64] = [:]

    init() {}
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}

/// One generated and solved level.
struct Candidate {
    let level: Int
    let seed: UInt64
    let template: String
    let file: LevelFile
    let kinds: [PieceKind]
    let metrics: SolverMetrics
    let solution: [SolverMove]
    let difficulty: Double

    var id: String { LevelReport.candidateID(level: level, seed: seed) }

    var reportCandidate: LevelReport.Candidate {
        LevelReport.Candidate(id: id, seed: seed, template: template, pieceCount: file.pieces.count,
                              kinds: kinds.map(\.rawValue), metrics: metrics, difficulty: difficulty, solution: solution)
    }
}

struct GeneratedLevel {
    let chosen: Candidate
    let runnerUps: [Candidate]
    let pinned: Bool
    let targetDifficulty: Double?

    var reportEntry: LevelReport.Level {
        LevelReport.Level(number: chosen.level, name: chosen.file.name, chosen: chosen.reportCandidate, pinned: pinned,
                          targetDifficulty: targetDifficulty, runnerUps: runnerUps.map(\.reportCandidate))
    }
}

enum LevelGenerator {
    static let levelCount = 50

    static func candidateSeed(master: UInt64, level: Int, index: Int) -> UInt64 {
        var rng = SplitMix64(seed: master).derived(UInt64(level) &* 0x9E37_79B9).derived(UInt64(index) &+ 1)
        return rng.next() | 1
    }

    /// Why a seed produced no candidate.
    enum Failure: Error, CustomStringConvertible {
        case draftFailed(template: String)
        case invalid(template: String, reason: String)
        case pieceCount(template: String, count: Int)
        case unsolvable(template: String)
        case notFullyExplored(template: String)
        case deadEnds(template: String, count: Int)
        case firstMove(template: String)
        case learningGoal(template: String)

        var description: String {
            switch self {
            case .draftFailed(let t): return "\(t): draft failed (wiring or gap planning)"
            case .invalid(let t, let reason): return "\(t): invalid: \(reason)"
            case .pieceCount(let t, let count): return "\(t): \(count) pieces, outside the range"
            case .unsolvable(let t): return "\(t): unsolvable"
            case .notFullyExplored(let t): return "\(t): solver hit its cap"
            case .deadEnds(let t, let count): return "\(t): \(count) dead-end moves"
            case .firstMove(let t): return "\(t): first move does not free a piece in one step"
            case .learningGoal(let t): return "\(t): new piece kind is not exercised"
            }
        }
    }

    /// Builds, validates, solves and scores one candidate. Nil when the draft is invalid, unsolvable,
    /// or fails the level's goal.
    static func makeCandidate(level: Int, seed: UInt64, config: GeneratorConfig) -> Candidate? {
        try? attempt(level: level, seed: seed, config: config)
    }

    static func attempt(level: Int, seed: UInt64, config: GeneratorConfig) throws -> Candidate {
        let goal = TutorialPlan.goal(for: level)
        var rng = SplitMix64(seed: seed)
        let template = rng.pick(goal.templates)
        guard var draft = template.build(level, &rng) else { throw Failure.draftFailed(template: template.id) }
        draft.assignColors(rng: &rng)
        let board: Board
        do {
            board = try draft.validate(number: level)
        } catch {
            throw Failure.invalid(template: draft.template, reason: "\(error)")
        }
        let file = draft.levelFile(number: level)
        guard goal.pieceRange.contains(file.pieces.count) else { throw Failure.pieceCount(template: draft.template, count: file.pieces.count) }

        let solver = LevelSolver(board: board, config: config.solver)
        var result = solver.solve()
        guard result.isSolvable, let solution = result.solution else { throw Failure.unsolvable(template: draft.template) }
        result.metrics.freedom = solver.freedom(along: solution)
        if goal.isTutorial {
            guard result.metrics.fullyExplored else { throw Failure.notFullyExplored(template: draft.template) }
            guard result.metrics.deadEndMoves <= goal.maxDeadEndMoves else { throw Failure.deadEnds(template: draft.template, count: result.metrics.deadEndMoves) }
            if goal.firstMoveFrees {
                guard let first = solution.first, abs(first.steps) == 1, !first.removed.isEmpty else { throw Failure.firstMove(template: draft.template) }
            }
            guard meetsLearningGoal(goal, file: file, board: board, solution: solution) else { throw Failure.learningGoal(template: draft.template) }
        }
        let kinds = PieceKind.kinds(in: file)
        let difficulty = DifficultyScore.score(metrics: result.metrics, pieceCount: file.pieces.count, distinctKinds: kinds.count)
        return Candidate(level: level, seed: seed, template: draft.template, file: file, kinds: kinds,
                         metrics: result.metrics, solution: solution, difficulty: difficulty)
    }

    /// The level must actually exercise the piece kind it introduces.
    static func meetsLearningGoal(_ goal: LevelGoal, file: LevelFile, board: Board, solution: [SolverMove]) -> Bool {
        guard let kind = goal.newKind else { return true }
        let kindOf = Dictionary(uniqueKeysWithValues: file.pieces.map { ($0.id, PieceKind.classify($0)) })
        let members = file.pieces.filter { PieceKind.classify($0) == kind }
        guard !members.isEmpty else { return false }
        switch kind {
        case .cRing, .tailRing, .slideBar, .lBar:
            // The new kind moves in the solution.
            return solution.contains { kindOf[$0.piece] == kind }
        case .closedRing:
            // The anchor holds at least two things (or holds something while being inside something).
            return members.contains { ($0.clips ?? []).count >= 2 || file.pieces.count <= 3 }
        case .latchBar:
            // The bar blocks some ring at the start: the player has to notice it before anything else works.
            let bars = Set(members.map(\.id))
            for piece in board.pieces where piece.motion == .rotation && !bars.contains(piece.id) {
                for direction in [1.0, -1.0] {
                    if let obstruction = board.obstruction(for: piece.id, movingBy: direction * GameRules.rotationStep),
                       case .collision(let blocker) = obstruction.reason, bars.contains(blocker) {
                        return true
                    }
                }
            }
            return false
        }
    }

    /// Generates the candidates for a level and picks one. `progress` receives short status lines.
    static func generate(level: Int, config: GeneratorConfig, progress: ((String) -> Void)? = nil) -> GeneratedLevel? {
        let goal = TutorialPlan.goal(for: level)
        var candidates: [Candidate] = []

        var pinned: Candidate?
        if let pinSeed = config.pins[level] {
            pinned = makeCandidate(level: level, seed: pinSeed, config: config)
            progress?(pinned == nil ? "pinned seed \(pinSeed) is no longer valid, ignoring" : "using pinned seed \(pinSeed)")
        }

        let budget = goal.isTutorial ? config.tutorialCandidates : config.maxCandidates
        var index = 0
        var attempts = 0
        let batch = goal.isTutorial ? 1 : max(1, config.jobs)
        // Try seeds in parallel batches until enough valid candidates exist; invalid drafts are cheap,
        // so allow extra attempts.
        while candidates.count < budget && attempts < budget * 6 {
            let seeds = (0..<batch).map { candidateSeed(master: config.masterSeed, level: level, index: index + $0) }
            index += batch
            attempts += batch
            var results = [Candidate?](repeating: nil, count: seeds.count)
            if batch == 1 {
                results[0] = makeCandidate(level: level, seed: seeds[0], config: config)
            } else {
                let lock = NSLock()
                DispatchQueue.concurrentPerform(iterations: seeds.count) { i in
                    let candidate = makeCandidate(level: level, seed: seeds[i], config: config)
                    lock.lock()
                    results[i] = candidate
                    lock.unlock()
                }
            }
            for candidate in results.compactMap({ $0 }) where candidate.seed != pinned?.seed {
                candidates.append(candidate)
            }
            if goal.isHard {
                // Hard levels compare a full set of candidates.
                if candidates.count >= hardCandidates { break }
            } else if !goal.isTutorial, let target = goal.targetDifficulty,
               candidates.count >= 4,
               candidates.contains(where: { abs($0.difficulty - target) <= tolerance(for: $0, target: target) }) {
                // Close enough for the curve, with runner-ups to spare.
                break
            }
        }
        progress?("\(candidates.count) valid candidate(s) from \(attempts) attempt(s)")

        candidates.sort { a, b in rank(a, goal: goal) < rank(b, goal: goal) }
        let chosen: Candidate
        if let pinned {
            chosen = pinned
        } else {
            guard let best = candidates.first else { return nil }
            chosen = best
            candidates.removeFirst()
        }
        let runnerUpCount = goal.isTutorial ? 7 : 3
        return GeneratedLevel(chosen: chosen, runnerUps: Array(candidates.prefix(runnerUpCount)), pinned: pinned != nil, targetDifficulty: goal.targetDifficulty)
    }

    /// Candidates compared for a hard level.
    private static let hardCandidates = 8

    /// Rebuilds a level and its runner-ups from the seeds recorded in the report, without choosing
    /// again: for after a drafting rule changed and the same boards should pick it up. Nil when the
    /// chosen seed no longer gives a valid level.
    static func rebuild(_ entry: LevelReport.Level, config: GeneratorConfig) -> GeneratedLevel? {
        guard let chosen = makeCandidate(level: entry.number, seed: entry.chosen.seed, config: config) else { return nil }
        let runnerUps = entry.runnerUps.compactMap { makeCandidate(level: entry.number, seed: $0.seed, config: config) }
        return GeneratedLevel(chosen: chosen, runnerUps: runnerUps, pinned: entry.pinned, targetDifficulty: entry.targetDifficulty)
    }

    private static func tolerance(for candidate: Candidate, target: Double) -> Double {
        DifficultyCurve.tolerance + (candidate.metrics.isEstimate ? DifficultyWeights.estimateUncertainty : 0)
    }

    /// Lower ranks first. Tutorial: fewest dead-end moves, closest to the target move count, fewest
    /// pieces. Hard: fewest pieces free along the solution, then most pieces. Curve: closest to the
    /// target difficulty, then exact metrics over estimates.
    private static func rank(_ candidate: Candidate, goal: LevelGoal) -> (Double, Double, Double, UInt64) {
        if goal.isHard {
            return ((candidate.metrics.freedom ?? 1).rounded(toPlaces: 2), -Double(candidate.file.pieces.count), 0, candidate.seed)
        }
        if goal.isTutorial {
            return (Double(candidate.metrics.deadEndMoves), abs(Double(candidate.metrics.minMoves - goal.targetMinMoves)), Double(candidate.file.pieces.count), candidate.seed)
        }
        // An estimated score is uncertain by about `estimateUncertainty`, so it must beat an exact
        // candidate by that much before it is preferred.
        let target = goal.targetDifficulty ?? 50
        let distance = abs(candidate.difficulty - target) + (candidate.metrics.isEstimate ? DifficultyWeights.estimateUncertainty : 0)
        return (distance, candidate.metrics.isEstimate ? 1 : 0, Double(candidate.file.pieces.count), candidate.seed)
    }
}
