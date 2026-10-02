//
//  BoosterInventory.swift
//  RotateRings
//
//  How many boosters the player owns. Boosters are scarce on purpose: one of each to start with,
//  and one more every few levels, the first time that level is completed.
//

import Foundation
import Observation

enum Booster: String, CaseIterable {
    /// Strikes a random piece.
    case lightning
    /// Vaporises the piece the player picks.
    case laser

    var title: String {
        switch self {
        case .lightning: "Lightning"
        case .laser: "Laser"
        }
    }
}

/// The player's boosters, persisted in UserDefaults.
@MainActor
@Observable
final class BoosterInventory {
    static let shared = BoosterInventory()

    /// Boosters of each kind a new player starts with.
    static let startingCount = 1
    /// Completing every this-many-th level for the first time earns one booster.
    static let rewardInterval = 5

    private enum Key {
        static func count(_ booster: Booster) -> String { "boosterCount.\(booster.rawValue)" }
        static let rewardedThrough = "boosterRewardedThroughLevel"
    }

    private let defaults: UserDefaults
    private var counts: [Booster: Int] = [:]
    /// Highest level whose reward has been handed out (or passed over), so replaying a level never
    /// pays out twice.
    private(set) var rewardedThroughLevel: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rewardedThroughLevel = defaults.integer(forKey: Key.rewardedThrough)
        for booster in Booster.allCases {
            counts[booster] = defaults.object(forKey: Key.count(booster)) as? Int ?? Self.startingCount
        }
    }

    func count(of booster: Booster) -> Int {
        counts[booster] ?? 0
    }

    /// Uses up one booster. False when the player has none left.
    @discardableResult
    func spend(_ booster: Booster) -> Bool {
        guard count(of: booster) > 0 else { return false }
        set(booster, to: count(of: booster) - 1)
        return true
    }

    /// The booster earned by completing `level`: one every `rewardInterval` levels, lightning and
    /// laser taking turns. Nil for all other levels.
    static func reward(forLevel level: Int) -> Booster? {
        guard level > 0, level % rewardInterval == 0 else { return nil }
        return (level / rewardInterval) % 2 == 1 ? .lightning : .laser
    }

    /// Hands out the reward for completing `level`, if it has one and has not been completed before.
    /// Returns the booster that was added.
    @discardableResult
    func collectReward(forCompleting level: Int) -> Booster? {
        guard level > rewardedThroughLevel else { return nil }
        rewardedThroughLevel = level
        defaults.set(level, forKey: Key.rewardedThrough)
        guard let booster = Self.reward(forLevel: level) else { return nil }
        set(booster, to: count(of: booster) + 1)
        return booster
    }

    private func set(_ booster: Booster, to count: Int) {
        counts[booster] = count
        defaults.set(count, forKey: Key.count(booster))
    }
}
