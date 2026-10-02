//
//  BoosterTests.swift
//  RotateRingsTests
//
//  The booster supply: what a new player starts with, spending, and the rewards for progress.
//

import Foundation
import Testing
@testable import RotateRings

@MainActor
struct BoosterTests {

    /// An inventory on its own empty defaults suite, so tests never touch the player's supply.
    private func makeInventory(suite: String = "BoosterTests.\(UUID().uuidString)") -> (BoosterInventory, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (BoosterInventory(defaults: defaults), defaults)
    }

    @Test func newPlayerStartsWithOneOfEach() {
        let (inventory, _) = makeInventory()
        for booster in Booster.allCases {
            #expect(inventory.count(of: booster) == 1)
        }
    }

    @Test func spendingStopsAtZero() {
        let (inventory, _) = makeInventory()
        #expect(inventory.spend(.laser))
        #expect(inventory.count(of: .laser) == 0)
        #expect(!inventory.spend(.laser))
        #expect(inventory.count(of: .laser) == 0)
        #expect(inventory.count(of: .lightning) == 1)
    }

    @Test func everyFifthLevelRewardsOneBoosterInTurns() {
        #expect(BoosterInventory.reward(forLevel: 4) == nil)
        #expect(BoosterInventory.reward(forLevel: 5) == .lightning)
        #expect(BoosterInventory.reward(forLevel: 6) == nil)
        #expect(BoosterInventory.reward(forLevel: 10) == .laser)
        #expect(BoosterInventory.reward(forLevel: 15) == .lightning)
        let rewards = (1...50).compactMap(BoosterInventory.reward(forLevel:))
        #expect(rewards.count == 10)
        #expect(rewards.filter { $0 == .lightning }.count == 5)
    }

    @Test func rewardIsPaidOnceAndNotOnReplay() {
        let (inventory, _) = makeInventory()
        #expect(inventory.collectReward(forCompleting: 4) == nil)
        #expect(inventory.collectReward(forCompleting: 5) == .lightning)
        #expect(inventory.count(of: .lightning) == 2)
        #expect(inventory.collectReward(forCompleting: 5) == nil)
        #expect(inventory.collectReward(forCompleting: 3) == nil)
        #expect(inventory.count(of: .lightning) == 2)
    }

    @Test func supplySurvivesARelaunch() {
        let suite = "BoosterTests.\(UUID().uuidString)"
        let (inventory, defaults) = makeInventory(suite: suite)
        inventory.spend(.lightning)
        inventory.collectReward(forCompleting: 10)
        let relaunched = BoosterInventory(defaults: defaults)
        #expect(relaunched.count(of: .lightning) == 0)
        #expect(relaunched.count(of: .laser) == 2)
        #expect(relaunched.rewardedThroughLevel == 10)
        #expect(relaunched.collectReward(forCompleting: 10) == nil)
    }
}
