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
//    report [--dir DIR] [--levels 101-200]   Print the level table from RotateRings/Levels/levels-report.json (or
//                                          DIR's), with the quality measurements when the report has them.
//    generate [--levels 1-50] [--seed N] [--candidates N] [--state-cap N] [--jobs N] [--out DIR]
//             [--no-quality] [--trap-rate]
//                                          Generate levels into RotateRings/Levels (honouring level-selection.json),
//                                          or into DIR with --out, leaving the shipped files alone.
//                                          With --keep-seeds the levels are rebuilt from the seeds in the shipped
//                                          report instead of chosen again, e.g. after a drafting rule changed;
//                                          --keep-same-designs does so only where the level's design is unchanged.
//                                          Output depends only on the seeds and settings, not on --jobs or the
//                                          machine; run with SWIFT_DETERMINISTIC_HASHING=1 as a safety net.
//                                          The chosen level and its runner-ups get quality measurements (bots,
//                                          tier, interest; LEVEL-DESIGN.md §14) unless --no-quality; --trap-rate
//                                          adds the slower trap count.
//    diagnose <level.json>...              Play greedily and explain what blocks the pieces left over.
//    bots [--levels 1-10] [--runs N] [--budget N] [--lookaheads 0,1,2]
//                                          Bot profiles of shipped levels: how often bots of each lookahead
//                                          clear the level (LEVEL-DESIGN.md §14), with the time each took.
//    render [--levels 11-200] [--dir DIR] [--out DIR] [--candidates]
//                                          Contact sheets, one PNG per block of ten levels (default out
//                                          LevelForge/sheets, git-ignored), from the shipped levels or DIR; with
//                                          --candidates a row per level with its runner-ups.
//    designs [--seeds 8] [--only TEXT] [--missing] [--retry-below N] [--out FILE]
//                                          Measure every design of Compositions.catalogue over a few seeds (bots
//                                          included) into LevelForge/design-quality.json for the planners.
//    compose <template>... [--count N] [--out DIR] [--no-solve]
//                                          Build curve designs by template id for a few seeds, solve them and
//                                          write them to DIR (default /tmp) for a look. No id lists the ids.
//
//  LEVEL-DESIGN.md next to this file explains how levels are made and what makes them fun.
//
//  Run from Xcode or `xcodebuild -scheme LevelForge build` (or `swiftc -O LevelForge/*.swift` plus
//  every file under RotateRings/Model); paths are resolved from the repository
//  root, which is derived from this file's location, so no working directory setup is needed.
//

import Foundation

// MARK: - Paths

/// `<repo>/LevelForge/main.swift` → `<repo>`.
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let levelsDirectory = repoRoot.appendingPathComponent("RotateRings/Levels", isDirectory: true)

func levelURL(_ number: Int, in directory: URL = levelsDirectory) -> URL {
    directory.appendingPathComponent("level\(number).json")
}

func sideFileURL(_ resource: String, in directory: URL = levelsDirectory) -> URL {
    directory.appendingPathComponent("\(resource).json")
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
    let directory = arguments.options["dir"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? levelsDirectory
    let report = try read(LevelReport.self, from: sideFileURL(LevelResources.report, in: directory))
    let wanted = Set(arguments.levelRange("levels", default: 1...LevelGenerator.levelCount))
    print("Seed \(report.masterSeed)  levels \(report.levels.count)")
    if let formula = report.qualityFormula { print(formula) }
    // Quality columns: difficulty, tier (u: unplanned), insight gap, forced share, setup depth,
    // interest, whether the owner strategy clears it (S), and per bot the median blind drags per
    // piece taken off. Flag oob: chosen by interest but no finalist was within the band.
    print(String(format: "%5@ %-20@ %6@ %6@ %6@ %7@ %4@", "level", "template", "pieces", "moves", "target", "legacy", "flag")
          + "   diff tier  gap  forced setup interest S  blind/piece by bot")
    for level in report.levels where wanted.contains(level.number) {
        let c = level.chosen
        let target = level.targetDifficulty.map { String(format: "%.0f", $0) } ?? "-"
        let flag = (c.metrics.isEstimate ? "≈" : "") + (level.pinned ? " pin" : "") + (level.outOfBand == true ? " oob" : "")
        var line = String(format: "%5d %-20@ %6d %6d %6@ %7.1f %4@", level.number, String(c.template.prefix(20)), c.pieceCount, c.metrics.minMoves, target, c.difficulty, flag)
        if let q = c.quality {
            line += String(format: "  %5.1f  %d%@  %4.2f   %4.2f  %3d    %5.3f   %@  ", q.difficulty, q.tier, q.unplanned ? "u" : " ", q.insightGap, q.forcedShare, q.setupDepth, q.interest, q.strategySolved ? "S" : "-")
            line += q.bots.map { String(format: "%5.2f", $0.blindRate) }.joined(separator: " ")
            if let trap = q.trapRate { line += String(format: "  trap %.2f", trap) }
        }
        print(line)
    }
}

func generateCommand(_ arguments: Arguments) throws {
    var config = GeneratorConfig()
    if let seed = arguments.uint64("seed") { config.masterSeed = seed }
    if let count = arguments.int("candidates") { config.tutorialCandidates = count }
    if let cap = arguments.int("state-cap") { config.solver.stateCap = cap }
    if let jobs = arguments.int("jobs") { config.jobs = max(1, jobs) }
    if arguments.options["no-quality"] != nil { config.quality = nil }
    if arguments.options["trap-rate"] != nil { config.quality?.measureTraps = true }
    // Each design's usual tier, for predicting difficulty before the bots play (`LevelGenerator.score`).
    struct DesignTiers: Decodable { var template: String; var tiers: [Int] }
    if let data = try? Data(contentsOf: repoRoot.appendingPathComponent("LevelForge/design-quality.json")),
       let designs = try? JSONDecoder().decode([String: DesignTiers].self, from: data) {
        var sums: [String: (tier: Double, boards: Double)] = [:]
        for design in designs.values {
            let boards = Double(design.tiers.reduce(0, +))
            guard boards > 0 else { continue }
            let tier = design.tiers.enumerated().reduce(0.0) { $0 + Double($1.offset * $1.element) }
            sums[design.template, default: (0, 0)].tier += tier
            sums[design.template, default: (0, 0)].boards += boards
        }
        config.expectedTier = sums.mapValues { $0.tier / $0.boards }
    }
    let levels = arguments.levelRange("levels", default: 1...LevelGenerator.levelCount)
    // With --out everything is written to that folder; the shipped levels are only read (for
    // --keep-seeds and the pins).
    let outDirectory = arguments.options["out"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? levelsDirectory
    try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)

    let selectionURL = sideFileURL(LevelResources.selection)
    if FileManager.default.fileExists(atPath: selectionURL.path) {
        let selection = try read(LevelSelection.self, from: selectionURL)
        for (key, pin) in selection.pins {
            if let number = Int(key) { config.pins[number] = pin.seed }
        }
        print("Loaded \(selection.pins.count) pin(s) from level-selection.json")
    }

    // Keep previously generated levels that are not being regenerated.
    let reportURL = sideFileURL(LevelResources.report, in: outDirectory)
    var existingLevels: [Int: LevelReport.Level] = [:]
    var existingCandidates: [String: LevelFile] = [:]
    if FileManager.default.fileExists(atPath: reportURL.path), let old = try? read(LevelReport.self, from: reportURL) {
        for level in old.levels { existingLevels[level.number] = level }
    }
    var shippedLevels: [Int: LevelReport.Level] = [:]
    if let shipped = try? read(LevelReport.self, from: sideFileURL(LevelResources.report)) {
        for level in shipped.levels { shippedLevels[level.number] = level }
    }
    let candidatesURL = sideFileURL(LevelResources.candidates, in: outDirectory)
    if FileManager.default.fileExists(atPath: candidatesURL.path), let old = try? read(CandidateStore.self, from: candidatesURL) {
        existingCandidates = old.candidates
    }

    let started = Date()
    var failed: [Int] = []
    for number in levels {
        let levelStarted = Date()
        let generated: GeneratedLevel?
        // --keep-same-designs: rebuild from the shipped seeds only where the plan kept the design.
        let sameDesign = arguments.options["keep-same-designs"] != nil && shippedLevels[number].map { entry in
            TutorialPlan.goal(for: number).templates.contains { $0.id == entry.chosen.template }
        } == true
        if arguments.options["keep-seeds"] != nil || sameDesign, let entry = shippedLevels[number] {
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
        try write(generated.chosen.file, to: levelURL(number, in: outDirectory))
        existingLevels[number] = generated.reportEntry
        for id in existingCandidates.keys where id.hasPrefix(String(format: "level%02d-", number)) {
            existingCandidates.removeValue(forKey: id)
        }
        for runnerUp in generated.runnerUps {
            existingCandidates[runnerUp.id] = runnerUp.file
        }
        let c = generated.chosen
        let quality = (c.quality.map { String(format: "  quality %.1f / %.2f tier %d", $0.difficulty, $0.interest, $0.tier) } ?? "")
            + (generated.outOfBand == true ? "  OUT OF BAND" : "")
        print(String(format: "level %2d  %-22@ %-18@ pieces %2d  difficulty %5.1f%@  %@%@  level took %.0fs", number, String(c.file.name.prefix(22)), c.template, c.file.pieces.count, c.difficulty, c.metrics.isEstimate ? "≈" : " ", formatMetrics(c.metrics), quality, Date().timeIntervalSince(levelStarted)))

        // Write the side files after every level, so an interrupted run loses nothing.
        let report = LevelReport(
            version: LevelReport.currentVersion,
            masterSeed: config.masterSeed,
            solverConfig: config.solver,
            difficultyFormula: DifficultyWeights.formula,
            qualityConfig: config.quality,
            qualityFormula: config.quality?.formula,
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
    if let cap = arguments.int("state-cap") { config.stateCap = cap }
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

/// Bot profiles of shipped levels, with the time per bot.
func botsCommand(_ arguments: Arguments) throws {
    let report = try read(LevelReport.self, from: sideFileURL(LevelResources.report))
    var config = QualityConfig()
    if let runs = arguments.int("runs") { config.runs = runs }
    if let budget = arguments.int("budget") { config.lookaheadBudget = budget }
    if let list = arguments.options["lookaheads"] { config.lookaheads = list.split(separator: ",").compactMap { Int($0) } }
    print("runs \(config.runs)  lookahead budget \(config.lookaheadBudget)  move limit \(config.moveLimitFactor)×minMoves+\(config.moveLimitExtra)")
    // Per bot: share of games won, median length of the games won, mean blind drags (no piece to
    // take off within the lookahead), and the share won within tighter limits (1.5× and 1.2× the
    // recorded solution, plus 2), read off the same games.
    print("level  pieces  moves   " + config.lookaheads.map { "k=\($0): won  len  blind  1.5× 1.2×  time   " }.joined() + "total")
    let started = Date()
    for number in arguments.levelRange("levels", default: 1...10) {
        guard let entry = report.levels.first(where: { $0.number == number }) else { continue }
        let board = try LevelLoader.decode(Data(contentsOf: levelURL(number))).makeBoard()
        let minMoves = entry.chosen.metrics.minMoves
        let levelStarted = Date()
        var columns: [String] = []
        for lookahead in config.lookaheads {
            let botStarted = Date()
            // A fresh level per bot, so each time is the bot's own (no positions cached by another).
            let bot = BotLevel(board: board, config: config)
            let games = bot.games(lookahead: lookahead, levelSeed: entry.chosen.seed, minMoves: minMoves)
            let won = games.filter(\.won)
            let lengths = won.map(\.moves).sorted()
            func within(_ factor: Double) -> Double {
                Double(won.filter { Double($0.moves) <= factor * Double(minMoves) + 2 }.count) / Double(games.count)
            }
            columns.append(String(format: "  %4.2f %4@ %5.1f  %4.2f %4.2f %5.1fs", Double(won.count) / Double(games.count),
                                  lengths.isEmpty ? "-" : "\(lengths[lengths.count / 2])",
                                  Double(games.map(\.blindMoves).reduce(0, +)) / Double(games.count), within(1.5), within(1.2),
                                  Date().timeIntervalSince(botStarted))
                           + (bot.refusedMoves > 0 ? " R\(bot.refusedMoves)" : "   "))
        }
        print(String(format: "%5d  %6d  %5d ", number, entry.chosen.pieceCount, minMoves) + columns.joined() + String(format: "  %5.1fs", Date().timeIntervalSince(levelStarted)))
    }
    print(String(format: "all levels: %.0fs", Date().timeIntervalSince(started)))
}

/// Contact sheets: one PNG per block of ten levels (`ContactSheet`, Render.swift).
func renderCommand(_ arguments: Arguments) throws {
    let directory = arguments.options["dir"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? levelsDirectory
    let out = arguments.options["out"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? repoRoot.appendingPathComponent("LevelForge/sheets", isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let report = try? read(LevelReport.self, from: sideFileURL(LevelResources.report, in: directory))
    let store = try? read(CandidateStore.self, from: sideFileURL(LevelResources.candidates, in: directory))
    let withCandidates = arguments.options["candidates"] != nil
    let entries = Dictionary(uniqueKeysWithValues: (report?.levels ?? []).map { ($0.number, $0) })

    func caption(_ number: Int, _ file: LevelFile, _ candidate: LevelReport.Candidate?, _ target: Double?) -> [String] {
        var lines = ["\(number)  \(file.name)  (\(file.pieces.count))"]
        lines.append(candidate.map { "\(Look.of(template: $0.template).rawValue) · " + String($0.template.prefix(28)) } ?? "")
        // The target sits next to the score it is on.
        let onQuality = DifficultyCurve.onQualityScale
        func versus(_ value: Double, _ scale: Bool) -> String { String(format: "%.0f", value) + (scale ? target.map { String(format: "/%.0f", $0) } ?? "" : "") }
        var scores = candidate.map { "legacy " + versus($0.difficulty, !onQuality) } ?? ""
        if let q = candidate?.quality {
            scores += "  diff " + versus(q.difficulty, onQuality) + String(format: "  int %.2f  T%d%@", q.interest, q.tier, q.unplanned ? "u" : "")
        }
        lines.append(scores)
        return lines
    }

    let levels = arguments.levelRange("levels", default: 11...LevelGenerator.levelCount)
    let blocks = Dictionary(grouping: levels) { ($0 - 1) / 10 }
    for block in blocks.keys.sorted() {
        var rows: [[ContactSheet.Cell]] = []
        var cells: [ContactSheet.Cell] = []
        for number in blocks[block]!.sorted() {
            guard let file = try? LevelLoader.decode(Data(contentsOf: levelURL(number, in: directory))) else { continue }
            let entry = entries[number]
            let chosen = ContactSheet.Cell(file: file, caption: caption(number, file, entry?.chosen, entry?.targetDifficulty))
            if withCandidates {
                var row = [chosen]
                for runnerUp in entry?.runnerUps ?? [] {
                    guard let candidateFile = store?.candidates[runnerUp.id] else { continue }
                    row.append(ContactSheet.Cell(file: candidateFile, caption: caption(number, candidateFile, runnerUp, entry?.targetDifficulty).enumerated().map { $0.offset == 0 ? "  runner-up \(runnerUp.seed % 100_000)" : $0.element }))
                }
                rows.append(row)
            } else {
                cells.append(chosen)
            }
        }
        if !withCandidates {
            rows = stride(from: 0, to: cells.count, by: ContactSheet.columns).map { Array(cells[$0..<min($0 + ContactSheet.columns, cells.count)]) }
        }
        guard !rows.isEmpty else { continue }
        let first = block * 10 + 1
        let name = String(format: "sheet-%03d-%03d%@.png", first, first + 9, withCandidates ? "-candidates" : "")
        try ContactSheet.write(rows: rows, title: "Levels \(first)–\(first + 9)  (\(directory.lastPathComponent))", to: out.appendingPathComponent(name))
        print("wrote \(out.appendingPathComponent(name).path)")
    }
}

/// What each design of `Compositions.catalogue` usually gives: a few seeds of each through the
/// whole pipeline, with the quality measurements, averaged into `LevelForge/design-quality.json`
/// for the planners (LEVEL-DESIGN.md §15). Deterministic: seeds come from `--seed` and the design.
func designsCommand(_ arguments: Arguments) throws {
    struct Summary: Codable {
        var template: String
        var look: Look
        var locks: Int
        var seeds: Int
        var valid: Int
        var legacy: Double
        var difficulty: Double
        var interest: Double
        /// Boards per tier, 0…3 (3: unplanned).
        var tiers: [Int]
        var unplannedShare: Double
        var pieces: Double
        var seconds: Double
    }
    let url = arguments.options["out"].map { URL(fileURLWithPath: $0) } ?? repoRoot.appendingPathComponent("LevelForge/design-quality.json")
    var existing: [String: Summary] = (try? JSONDecoder().decode([String: Summary].self, from: Data(contentsOf: url))) ?? [:]
    let seeds = arguments.int("seeds") ?? 8
    let master = arguments.uint64("seed") ?? 20_261_028
    let level = arguments.int("level") ?? 150
    var designs = Compositions.catalogue
    if let only = arguments.options["only"] { designs = designs.filter { $0.expr.contains(only) } }
    if arguments.options["missing"] != nil { designs = designs.filter { existing[$0.expr] == nil } }
    // Designs whose seeds are often unsolvable need more of them for a fair average.
    if let below = arguments.int("retry-below") { designs = designs.filter { (existing[$0.expr]?.valid ?? 0) < below } }
    print("measuring \(designs.count) design(s), \(seeds) seed(s) each")
    let jobs = designs.count * seeds
    struct Sample { var legacy: Double; var quality: LevelQuality; var pieces: Int; var seconds: Double }
    var samples = [Sample?](repeating: nil, count: jobs)
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: jobs) { j in
        let design = designs[j / seeds]
        let started = Date()
        // FNV-1a of the expression, so a design keeps its seeds when the catalogue changes around it.
        let key = design.expr.utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
        var seedRNG = SplitMix64(seed: master ^ key).derived(UInt64(j % seeds) &+ 1)
        let seed = seedRNG.next() | 1
        var draftRNG = SplitMix64(seed: seed)
        guard var draft = design.template.build(level, &draftRNG) else { return }
        draft.assignColors(rng: &draftRNG)
        guard let board = try? draft.validate(number: level) else { return }
        let solver = LevelSolver(board: board)
        var result = solver.solve()
        guard let solution = result.solution else { return }
        var replay = board
        guard replay.replay(solution) else { return }
        result.metrics.freedom = solver.freedom(along: solution)
        result.metrics.setupMoves = solution.filter { $0.removed.isEmpty }.count
        let file = draft.levelFile(number: level)
        let legacy = DifficultyScore.score(metrics: result.metrics, pieceCount: file.pieces.count, distinctKinds: PieceKind.kinds(in: file).count)
        let quality = QualityMeasure.measure(board: board, solution: solution, minMoves: result.metrics.minMoves, seed: seed,
                                             config: QualityConfig(), solverConfig: SolverConfig())
        let sample = Sample(legacy: legacy, quality: quality, pieces: file.pieces.count, seconds: Date().timeIntervalSince(started))
        lock.lock()
        samples[j] = sample
        lock.unlock()
    }
    func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10 }
    for (d, design) in designs.enumerated() {
        let valid = samples[(d * seeds)..<((d + 1) * seeds)].compactMap { $0 }
        let tiers = (0...3).map { t in valid.filter { $0.quality.tier == t }.count }
        existing[design.expr] = Summary(template: design.template.id, look: Look.of(template: design.template.id), locks: design.locks,
                                        seeds: seeds, valid: valid.count, legacy: mean(valid.map(\.legacy)),
                                        difficulty: mean(valid.map(\.quality.difficulty)),
                                        interest: (mean(valid.map { $0.quality.interest * 100 }) / 100),
                                        tiers: tiers, unplannedShare: valid.isEmpty ? 0 : Double(valid.filter(\.quality.unplanned).count) / Double(valid.count),
                                        pieces: mean(valid.map { Double($0.pieces) }), seconds: mean(valid.map(\.seconds)))
        let s = existing[design.expr]!
        print(String(format: "%-90@ %d/%d  diff %5.1f  int %.2f  tiers %@  legacy %.0f", design.expr, s.valid, seeds, s.difficulty, s.interest,
                     tiers.map(String.init).joined(separator: "/"), s.legacy))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(existing).write(to: url)
    print("wrote \(url.path)")
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
if arguments.options["time-cap"] != nil {
    fail("--time-cap is gone: limits now count work, not seconds, so results never depend on the machine. Use --state-cap N (default \(SolverConfig().stateCap)).")
}
do {
    switch arguments.command {
    case "solve": try solveCommand(arguments)
    case "report": try reportCommand(arguments)
    case "generate": try generateCommand(arguments)
    case "probe": try probeCommand(arguments)
    case "motif": try motifCommand(arguments)
    case "compose": try composeCommand(arguments)
    case "diagnose": try diagnoseCommand(arguments)
    case "bots": try botsCommand(arguments)
    case "render": try renderCommand(arguments)
    case "designs": try designsCommand(arguments)
    default:
        print("usage: LevelForge solve <level.json>... | report | generate [--levels 1-50] [--seed N] [--candidates N] [--state-cap N] [--jobs N] [--out DIR] | compose <template>... [--count N] [--out DIR]")
    }
} catch {
    fail("error: \(error.localizedDescription)")
}
