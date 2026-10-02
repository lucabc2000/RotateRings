//
//  LevelSwaps.swift
//  RotateRings
//
//  Debug only. Remembers which runner-up the reviewer wants for a level, plays it in place of the
//  generated level, and exports the choice as `level-selection.json` for the generator.
//

#if DEBUG
import Foundation
import Observation

@MainActor
@Observable
final class LevelSwaps {
    static let shared = LevelSwaps()
    private static let key = "levelSwaps"

    /// Level number → candidate id.
    private(set) var swaps: [Int: String]

    private init() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        swaps = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    func candidateID(for level: Int) -> String? {
        swaps[level]
    }

    func set(_ candidateID: String?, for level: Int) {
        swaps[level] = candidateID
        save()
    }

    func resetAll() {
        swaps = [:]
        save()
    }

    private func save() {
        let raw = Dictionary(uniqueKeysWithValues: swaps.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(raw, forKey: Self.key)
    }

    /// `level-selection.json` pinning every level to what the reviewer sees now: the generated
    /// candidate, or the swapped runner-up. Rerunning the generator with this file keeps all of it.
    func exportSelection(report: LevelReport) -> String {
        var pins: [String: LevelSelection.Pin] = [:]
        for level in report.levels {
            let candidate = swaps[level.number].flatMap { id in level.runnerUps.first { $0.id == id } } ?? level.chosen
            pins[String(level.number)] = LevelSelection.Pin(seed: candidate.seed, template: candidate.template)
        }
        let selection = LevelSelection(version: LevelReport.currentVersion, pins: pins)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(selection), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
#endif
