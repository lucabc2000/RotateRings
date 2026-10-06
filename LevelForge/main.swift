//
//  main.swift
//  LevelForge
//
//  Command-line level generator for RotateRings. Compiles the app's Model sources (including the
//  solver and generator) directly; new files under RotateRings/Model are picked up automatically
//  through the shared synchronized folder, everything else in the app folder is excluded.
//
//  Commands
//    solve <level.json>...                 Solve the given level files and print their metrics.
//    report                                Print the level table from RotateRings/Levels/levels-report.json.
//    generate [--levels 1-50] [--seed N] [--candidates N] [--state-cap N] [--time-cap S] [--jobs N]
//                                          Generate levels into RotateRings/Levels (honouring level-selection.json).
//                                          With --keep-seeds the levels are rebuilt from the seeds in the report
//                                          instead of chosen again, e.g. after a drafting rule changed.
//    diagnose <level.json>...              Play greedily and explain what blocks the pieces left over.
//    compose <template>... [--count N] [--out DIR] [--no-solve]
//                                          Build curve designs by template id for a few seeds, solve them and
//                                          write them to DIR (default /tmp) for a look. No id lists the ids.
//
//  LEVEL-DESIGN.md next to this file explains how levels are made and what makes them fun.
//
//  Run from Xcode or `xcodebuild -scheme LevelForge build`; paths are resolved from the repository
//  root, which is derived from this file's location, so no working directory setup is needed.
//

import Foundation

// MARK: - Paths

/// `<repo>/LevelForge/main.swift` → `<repo>`.
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let levelsDirectory = repoRoot.appendingPathComponent("RotateRings/Levels", isDirectory: true)

func levelURL(_ number: Int) -> URL {
    levelsDirectory.appendingPathComponent("level\(number).json")
}

func sideFileURL(_ resource: String) -> URL {
    levelsDirectory.appendingPathComponent("\(resource).json")
}

// MARK: - JSON

let prettyEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()

func write<T: Encodable>(_ value: T, to url: URL) throws {
    let data = try prettyEncoder.encode(value)
    try data.write(to: url, options: .atomic)
}

func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    try LevelLoader.sideFileDecoder.decode(T.self, from: Data(contentsOf: url))
}

// MARK: - Arguments

struct Arguments {
    var command: String
    var positional: [String] = []
    var options: [String: String] = [:]

    init(_ raw: [String]) {
        var raw = raw
        command = raw.isEmpty ? "help" : raw.removeFirst()
        var index = 0
        while index < raw.count {
            let item = raw[index]
            if item.hasPrefix("--") {
                let key = String(item.dropFirst(2))
                if index + 1 < raw.count, !raw[index + 1].hasPrefix("--") {
                    options[key] = raw[index + 1]
                    index += 2
                } else {
                    options[key] = "true"
                    index += 1
                }
            } else {
                positional.append(item)
                index += 1
            }
        }
    }

    func int(_ key: String) -> Int? { options[key].flatMap { Int($0) } }
    func double(_ key: String) -> Double? { options[key].flatMap { Double($0) } }
    func uint64(_ key: String) -> UInt64? { options[key].flatMap { UInt64($0) } }

    /// `--levels 1-50`, `--levels 7`, or `--levels 1-15,20`.
    func levelRange(_ key: String, default range: ClosedRange<Int>) -> [Int] {
        guard let raw = options[key] else { return Array(range) }
        var result: [Int] = []
        for part in raw.split(separator: ",") {
            let bounds = part.split(separator: "-").compactMap { Int($0) }
            if bounds.count == 2 { result += Array(bounds[0]...bounds[1]) } else if bounds.count == 1 { result.append(bounds[0]) }
        }
        return result
    }
}

// MARK: - Output helpers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func formatMetrics(_ metrics: SolverMetrics) -> String {
    let flag = metrics.isEstimate ? " ≈" : ""
    let freedom = (metrics.freedom.map { String(format: "  freedom %.0f%%", $0 * 100) } ?? "")
        + (metrics.setupMoves.map { "  setup \($0)" } ?? "")
    return "moves \(metrics.minMoves)\(flag)\(freedom)  states \(metrics.reachableStates)  dead-end moves \(metrics.deadEndMoves)/\(metrics.totalMoves) (\(String(format: "%.0f%%", metrics.deadEndRate * 100)))  branching \(String(format: "%.1f", metrics.branching))  \(String(format: "%.2fs", metrics.elapsed))"
}

// MARK: - Commands

func solveCommand(_ arguments: Arguments) throws {
    guard !arguments.positional.isEmpty else { fail("solve: give at least one level file") }
    var config = SolverConfig()
    if let cap = arguments.int("state-cap") { config.stateCap = cap }
    if let cap = arguments.double("time-cap") { config.timeCap = cap }
    for path in arguments.positional {
        let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let file = try LevelLoader.decode(Data(contentsOf: url))
        let board = try file.makeBoard()
        let solver = LevelSolver(board: board, config: config)
        var result = solver.solve()
        result.metrics.freedom = result.solution.map { solver.freedom(along: $0) }
        let kinds = PieceKind.kinds(in: file)
        let difficulty = DifficultyScore.score(metrics: result.metrics, pieceCount: file.pieces.count, distinctKinds: kinds.count)
        print("\(url.lastPathComponent)  \(file.name)  pieces \(file.pieces.count)  kinds \(kinds.map(\.rawValue).joined(separator: ","))")
        print("  \(result.isSolvable ? "solvable" : "UNSOLVABLE")  difficulty \(difficulty)  \(formatMetrics(result.metrics))")
        if let solution = result.solution {
            print("  solution: " + solution.map { "\($0.piece) \($0.steps > 0 ? "+" : "")\($0.steps)" }.joined(separator: ", "))
        }
    }
}

func reportCommand(_ arguments: Arguments) throws {
    let report = try read(LevelReport.self, from: sideFileURL(LevelResources.report))
    print("Generated \(report.generatedAt)  seed \(report.masterSeed)  levels \(report.levels.count)")
    print(String(format: "%5@ %-24@ %-20@ %6@ %6@ %6@ %7@ %4@", "level", "name", "template", "pieces", "moves", "target", "actual", "flag"))
    for level in report.levels {
        let c = level.chosen
        let target = level.targetDifficulty.map { String(format: "%.0f", $0) } ?? "-"
        let flag = (c.metrics.isEstimate ? "≈" : "") + (level.pinned ? " pin" : "")
        print(String(format: "%5d %-24@ %-20@ %6d %6d %6@ %7.1f %4@", level.number, String(level.name.prefix(24)), String(c.template.prefix(20)), c.pieceCount, c.metrics.minMoves, target, c.difficulty, flag))
    }
}

func generateCommand(_ arguments: Arguments) throws {
    var config = GeneratorConfig()
    if let seed = arguments.uint64("seed") { config.masterSeed = seed }
    if let count = arguments.int("candidates") { config.tutorialCandidates = count }
    if let cap = arguments.int("state-cap") { config.solver.stateCap = cap }
    if let cap = arguments.double("time-cap") { config.solver.timeCap = cap }
    if let jobs = arguments.int("jobs") { config.jobs = max(1, jobs) }
    let levels = arguments.levelRange("levels", default: 1...LevelGenerator.levelCount)

    let selectionURL = sideFileURL(LevelResources.selection)
    if FileManager.default.fileExists(atPath: selectionURL.path) {
        let selection = try read(LevelSelection.self, from: selectionURL)
        for (key, pin) in selection.pins {
            if let number = Int(key) { config.pins[number] = pin.seed }
        }
        print("Loaded \(selection.pins.count) pin(s) from level-selection.json")
    }

    // Keep previously generated levels that are not being regenerated.
    let reportURL = sideFileURL(LevelResources.report)
    var existingLevels: [Int: LevelReport.Level] = [:]
    var existingCandidates: [String: LevelFile] = [:]
    if FileManager.default.fileExists(atPath: reportURL.path), let old = try? read(LevelReport.self, from: reportURL) {
        for level in old.levels { existingLevels[level.number] = level }
    }
    let candidatesURL = sideFileURL(LevelResources.candidates)
    if FileManager.default.fileExists(atPath: candidatesURL.path), let old = try? read(CandidateStore.self, from: candidatesURL) {
        existingCandidates = old.candidates
    }

    let started = Date()
    var failed: [Int] = []
    for number in levels {
        let levelStarted = Date()
        let generated: GeneratedLevel?
        if arguments.options["keep-seeds"] != nil, let entry = existingLevels[number] {
            generated = LevelGenerator.rebuild(entry, config: config)
        } else {
            generated = LevelGenerator.generate(level: number, config: config) { message in
                print("  level \(number): \(message) (\(String(format: "%.0fs", Date().timeIntervalSince(levelStarted))))")
            }
        }
        guard let generated else {
            print("level \(number): NO VALID CANDIDATE, keeping the previous file if any")
            failed.append(number)
            continue
        }
        try write(generated.chosen.file, to: levelURL(number))
        existingLevels[number] = generated.reportEntry
        for id in existingCandidates.keys where id.hasPrefix(String(format: "level%02d-", number)) {
            existingCandidates.removeValue(forKey: id)
        }
        for runnerUp in generated.runnerUps {
            existingCandidates[runnerUp.id] = runnerUp.file
        }
        let c = generated.chosen
        print(String(format: "level %2d  %-22@ %-18@ pieces %2d  difficulty %5.1f%@  %@", number, String(c.file.name.prefix(22)), c.template, c.file.pieces.count, c.difficulty, c.metrics.isEstimate ? "≈" : " ", formatMetrics(c.metrics)))

        // Write the side files after every level, so an interrupted run loses nothing.
        let report = LevelReport(
            version: LevelReport.currentVersion,
            generatedAt: Date(),
            masterSeed: config.masterSeed,
            solverConfig: config.solver,
            difficultyFormula: DifficultyWeights.formula,
            levels: existingLevels.keys.sorted().compactMap { existingLevels[$0] }
        )
        try write(report, to: reportURL)
        try write(CandidateStore(version: LevelReport.currentVersion, candidates: existingCandidates), to: candidatesURL)
    }
    print(String(format: "Wrote %d level(s), report and %d candidate(s) in %.0fs", levels.count - failed.count, existingCandidates.count, Date().timeIntervalSince(started)))
    if !failed.isEmpty {
        fail("no valid candidate for level(s) \(failed.map(String.init).joined(separator: ", "))")
    }
}

/// Explains why each seed of a level does or does not produce a candidate.
func probeCommand(_ arguments: Arguments) throws {
    var config = GeneratorConfig()
    if let seed = arguments.uint64("seed") { config.masterSeed = seed }
    let count = arguments.int("count") ?? 8
    if arguments.options["verbose"] != nil {
        LevelTemplate.debug = { print("    \($0)") }
    }
    for level in arguments.levelRange("levels", default: 1...1) {
        print("level \(level):")
        for index in 0..<count {
            let seed = LevelGenerator.candidateSeed(master: config.masterSeed, level: level, index: index)
            do {
                let candidate = try LevelGenerator.attempt(level: level, seed: seed, config: config)
                print("  seed \(seed): OK \(candidate.template) pieces \(candidate.file.pieces.count) difficulty \(candidate.difficulty) \(formatMetrics(candidate.metrics))")
            } catch {
                print("  seed \(seed): \(error)")
            }
        }
    }
}

/// Builds one motif by name for a few seeds and reports drafting, validation and solving in detail.
func motifCommand(_ arguments: Arguments) throws {
    guard let name = arguments.positional.first, let builder = MotifCatalog.builders[name] else {
        fail("motif: give a motif name: \(MotifCatalog.builders.keys.sorted().joined(separator: ", "))")
    }
    let count = arguments.int("count") ?? 3
    let lock = 1...(arguments.int("lock") ?? 2)
    for index in 0..<count {
        let seed = arguments.uint64("seed").map { $0 &+ UInt64(index) } ?? LevelGenerator.candidateSeed(master: 1, level: 99, index: index)
        var rng = SplitMix64(seed: seed)
        guard let motif = builder(lock, &rng) else {
            print("seed \(seed): motif builder returned nil")
            continue
        }
        var draft = LevelDraft(name: motif.name, template: name, pieces: motif.placed(at: ForgeRules.center))
        draft.renumberIDs()
        draft.assignColors(rng: &rng)
        print("seed \(seed): \(motif.name) pieces \(draft.pieces.count) size \(Int(motif.width))×\(Int(motif.height))")
        let board: Board
        do {
            board = try draft.validate()
        } catch {
            print("  invalid: \(error)")
            continue
        }
        for piece in draft.pieces {
            let contacts = draft.contactAngles(on: piece.id).map { String(Int($0)) }.joined(separator: ",")
            let gap = piece.gapCenterDegrees.map { "gap \(Int($0))±\(Int((piece.gapDegrees ?? 0) / 2))" } ?? "closed"
            let grips = piece.clips.compactMap(\.grips).joined(separator: ",")
            print("  \(piece.id) \(piece.kind.rawValue) at (\(Int(piece.position.x)),\(Int(piece.position.y))) \(gap) contacts [\(contacts)] grips [\(grips)]")
        }
        let solver = LevelSolver(board: board)
        let first = solver.successors(of: solver.start)
        print("  moves from start: " + first.map { "\($0.move.piece)\($0.move.steps > 0 ? "+" : "")\($0.move.steps) [removed \($0.move.removed.joined(separator: ","))] bits \(String($0.state.connections, radix: 2))" }.joined(separator: " | "))
        if arguments.options["trace"] != nil {
            for candidate in first {
                var copy = board
                let outcome = copy.move(candidate.move.piece, by: candidate.move.delta)
                if case .moved(let result) = outcome, !result.brokenConnections.isEmpty || !result.removedPieceIDs.isEmpty {
                    print("  board.move \(candidate.move.piece) \(candidate.move.steps): broke \(result.brokenConnections.map { "\($0.owner)→\($0.ring)" }) removed \(result.removedPieceIDs)")
                }
            }
            print("  start connections: " + board.connections.map { "\($0.owner)→\($0.ring)" }.joined(separator: " "))
        }
        // --replay "r7+1,r8-1,r2+3": apply those moves, then report what blocks every piece.
        if let replay = arguments.options["replay"] {
            var copy = board
            for token in replay.split(separator: ",") {
                let text = String(token)
                guard let signIndex = text.lastIndex(where: { $0 == "+" || $0 == "-" }), let steps = Int(text[signIndex...]) else { continue }
                let piece = String(text[..<signIndex])
                let outcome = copy.move(piece, by: Double(steps) * GameRules.rotationStep)
                print("  replay \(text): \(outcome)")
            }
            for piece in copy.pieces {
                for direction in [1.0, -1.0] {
                    let obstruction = copy.obstruction(for: piece.id, movingBy: direction * GameRules.rotationStep)
                    print("    \(piece.id) \(direction > 0 ? "+1" : "-1"): \(obstruction.map { "\($0.reason) stop \(String(format: "%.1f°", AngleMath.degrees(fromRadians: $0.stop - piece.movement)))" } ?? "free")")
                }
            }
        }
        let result = solver.solve()
        print("  \(result.isSolvable ? "solvable" : "UNSOLVABLE")  \(formatMetrics(result.metrics))")
        if let solution = result.solution {
            print("  solution: " + solution.map { "\($0.piece) \($0.steps > 0 ? "+" : "")\($0.steps)" }.joined(separator: ", "))
        }
        let url = URL(fileURLWithPath: "/tmp/motif-\(name)-\(index).json")
        try write(draft.levelFile(number: 99), to: url)
        print("  written to \(url.path)")
    }
}

/// Builds whole-board curve designs by template id, without the curve's difficulty selection.
func composeCommand(_ arguments: Arguments) throws {
    guard !arguments.positional.isEmpty else {
        fail("compose: give a template id: \(Compositions.catalog.keys.sorted().joined(separator: ", "))")
    }
    let count = arguments.int("count") ?? 3
    let directory = URL(fileURLWithPath: arguments.options["out"] ?? "/tmp", isDirectory: true)
    if arguments.options["verbose"] != nil {
        LevelTemplate.debug = { print("    \($0)") }
    }
    var config = SolverConfig()
    if let cap = arguments.double("time-cap") { config.timeCap = cap }
    // --keep-stuck: write tangles that fail their playout check anyway, to look at them.
    Tangle.keepStuck = arguments.options["keep-stuck"] != nil
    for name in arguments.positional {
        guard let template = Compositions.catalog[name] else { fail("compose: unknown template \(name)") }
        for index in 0..<count {
            let seed = arguments.uint64("seed").map { $0 &+ UInt64(index) } ?? LevelGenerator.candidateSeed(master: 1, level: 99, index: index)
            var rng = SplitMix64(seed: seed)
            let started = Date()
            guard var draft = template.build(99, &rng) else {
                print("\(name) seed \(seed): no draft")
                continue
            }
            draft.assignColors(rng: &rng)
            let url = directory.appendingPathComponent("\(name)-\(index).json")
            try write(draft.levelFile(number: 99), to: url)
            let built = Date().timeIntervalSince(started)
            let board: Board
            do {
                board = try draft.validate()
            } catch {
                print("\(name) seed \(seed): pieces \(draft.pieces.count) INVALID: \(error)  → \(url.lastPathComponent)")
                continue
            }
            if arguments.options["no-solve"] != nil {
                print("\(name) seed \(seed): pieces \(draft.pieces.count) built in \(String(format: "%.1fs", built))  → \(url.lastPathComponent)")
                continue
            }
            let solver = LevelSolver(board: board, config: config)
            var result = solver.solve()
            result.metrics.freedom = result.solution.map { solver.freedom(along: $0) }
            result.metrics.setupMoves = result.solution.map { $0.filter { $0.removed.isEmpty }.count }
            let file = draft.levelFile(number: 99)
            let difficulty = DifficultyScore.score(metrics: result.metrics, pieceCount: file.pieces.count, distinctKinds: PieceKind.kinds(in: file).count)
            print("\(name) seed \(seed): pieces \(draft.pieces.count) built in \(String(format: "%.1fs", built))  \(result.isSolvable ? "solvable" : "UNSOLVABLE")  difficulty \(difficulty)  \(formatMetrics(result.metrics))  → \(url.lastPathComponent)")
        }
    }
}

/// Plays a level file greedily and, when that gets stuck, says what blocks each remaining piece.
func diagnoseCommand(_ arguments: Arguments) throws {
    for path in arguments.positional {
        let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let board = try LevelLoader.decode(Data(contentsOf: url)).makeBoard()
        let solver = LevelSolver(board: board)
        let stuck = solver.greedyPlayout()
        guard !stuck.isEmpty else {
            print("\(url.lastPathComponent): plays through")
            continue
        }
        print("\(url.lastPathComponent): stuck with \(stuck.joined(separator: ", "))")
        // Rebuild the stuck position by replaying the same greedy moves.
        var state = solver.start
        var position = board
        while let pick = solver.successors(of: state).first(where: { !$0.move.removed.isEmpty })
            ?? solver.successors(of: state).first(where: { $0.state.connections.nonzeroBitCount < state.connections.nonzeroBitCount }) {
            _ = position.move(pick.move.piece, by: pick.move.delta)
            state = pick.state
        }
        for piece in position.pieces {
            let held = position.connections.filter { $0.owner == piece.id && !$0.isHolder }.map(\.ring)
            var lines = ["  \(piece.id):"]
            if !held.isEmpty { lines.append("pinned by its clips on \(held.joined(separator: ", "))") }
            for direction in [1.0, -1.0] {
                let obstruction = position.obstruction(for: piece.id, movingBy: direction * GameRules.rotationStep)
                lines.append("\(direction > 0 ? "+1" : "-1"): " + (obstruction.map { "\($0.reason) after \(String(format: "%.0f°", AngleMath.degrees(fromRadians: abs($0.stop - piece.movement))))" } ?? "free"))
            }
            print(lines.joined(separator: "  "))
        }
    }
}

// MARK: - Main

// Line-buffer stdout so progress shows up when the output is redirected to a file.
setvbuf(stdout, nil, _IOLBF, 0)

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
do {
    switch arguments.command {
    case "solve": try solveCommand(arguments)
    case "report": try reportCommand(arguments)
    case "generate": try generateCommand(arguments)
    case "probe": try probeCommand(arguments)
    case "motif": try motifCommand(arguments)
    case "compose": try composeCommand(arguments)
    case "diagnose": try diagnoseCommand(arguments)
    default:
        print("usage: LevelForge solve <level.json>... | report | generate [--levels 1-50] [--seed N] [--candidates N] [--state-cap N] [--time-cap S] [--jobs N] | compose <template>... [--count N] [--out DIR]")
    }
} catch {
    fail("error: \(error.localizedDescription)")
}
