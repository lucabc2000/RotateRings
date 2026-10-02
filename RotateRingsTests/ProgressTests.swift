//
//  ProgressTests.swift
//  RotateRingsTests
//
//  The campaign level the player is at is remembered between launches.
//

import Foundation
import Testing
@testable import RotateRings

private let appBundle = Bundle(for: GameScene.self)

@MainActor
struct ProgressTests {

    /// Empty defaults of its own per test, so nothing touches the player's saved game.
    private func makeDefaults() -> UserDefaults {
        let suite = "ProgressTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func launch(_ defaults: UserDefaults) -> GameViewModel {
        GameViewModel(bundle: appBundle, defaults: defaults, boosters: BoosterInventory(defaults: defaults))
    }

    @Test func firstLaunchStartsAtLevelOne() {
        #expect(launch(makeDefaults()).levelNumber == 1)
    }

    @Test func relaunchOpensTheLevelThePlayerWasAt() {
        let defaults = makeDefaults()
        launch(defaults).loadLevel(5)
        #expect(launch(defaults).levelNumber == 5)
    }

    @Test func relaunchAfterCompletingALevelOpensTheNextOne() {
        let defaults = makeDefaults()
        let model = launch(defaults)
        model.loadLevel(5)
        model.scene?.onLevelComplete?()
        #expect(model.isLevelComplete)
        #expect(model.levelNumber == 5)
        #expect(launch(defaults).levelNumber == 6)
    }

    @Test func restartKeepsTheLevel() {
        let defaults = makeDefaults()
        let model = launch(defaults)
        model.loadLevel(7)
        model.restart()
        #expect(launch(defaults).levelNumber == 7)
    }

    @Test func completingTheLastLevelFinishesTheCampaign() {
        let defaults = makeDefaults()
        let model = launch(defaults)
        model.loadLevel(model.levelCount)
        #expect(!model.isCampaignFinished)
        model.scene?.onLevelComplete?()
        #expect(model.isCampaignFinished)

        // Still finished after a relaunch, with no board to play.
        let relaunched = launch(defaults)
        #expect(relaunched.isCampaignFinished)
        #expect(relaunched.scene == nil)
        #expect(relaunched.levelNumber == relaunched.levelCount)
    }

    @Test func startingOverGoesBackToLevelOneForGood() {
        let defaults = makeDefaults()
        let model = launch(defaults)
        model.loadLevel(model.levelCount)
        model.scene?.onLevelComplete?()
        model.startOver()
        #expect(!model.isCampaignFinished)
        #expect(model.levelNumber == 1)
        #expect(model.scene != nil)
        let relaunched = launch(defaults)
        #expect(!relaunched.isCampaignFinished)
        #expect(relaunched.levelNumber == 1)
    }

    @Test func completingAnEarlierLevelDoesNotFinishTheCampaign() {
        let defaults = makeDefaults()
        let model = launch(defaults)
        model.loadLevel(model.levelCount - 1)
        model.scene?.onLevelComplete?()
        #expect(!model.isCampaignFinished)
        #expect(launch(defaults).levelNumber == model.levelCount)
    }

    @Test func startLevelArgumentWinsOverTheSavedLevel() {
        let defaults = makeDefaults()
        defaults.set(12, forKey: "campaignLevel")
        defaults.set(3, forKey: "startLevel")
        #expect(GameViewModel.launchLevel(in: defaults) == 3)
    }
}
