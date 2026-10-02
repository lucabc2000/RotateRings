//
//  ReviewPromptTests.swift
//  RotateRingsTests
//
//  When the game asks for an App Store review.
//

import Foundation
import Testing
@testable import RotateRings

private let appBundle = Bundle(for: GameScene.self)

@MainActor
struct ReviewPromptTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "ReviewPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func asksOnlyAtMilestones() {
        let prompt = ReviewPrompt(defaults: makeDefaults())
        let asked = (1...50).filter { prompt.shouldAsk(afterCompleting: $0) }
        #expect(asked == ReviewPrompt.milestones)
    }

    @Test func asksOncePerMilestoneEvenAcrossLaunches() {
        let defaults = makeDefaults()
        #expect(ReviewPrompt(defaults: defaults).shouldAsk(afterCompleting: 10))
        #expect(!ReviewPrompt(defaults: defaults).shouldAsk(afterCompleting: 10))
        #expect(ReviewPrompt(defaults: defaults).shouldAsk(afterCompleting: 25))
        // Replaying an earlier milestone after a later one does not ask again.
        #expect(!ReviewPrompt(defaults: defaults).shouldAsk(afterCompleting: 10))
    }

    @Test func completingAMilestoneLevelRaisesARequest() {
        let defaults = makeDefaults()
        let model = GameViewModel(bundle: appBundle, defaults: defaults, boosters: BoosterInventory(defaults: defaults))
        model.loadLevel(9)
        model.scene?.onLevelComplete?()
        #expect(model.reviewRequests == 0)
        model.loadLevel(10)
        model.scene?.onLevelComplete?()
        #expect(model.reviewRequests == 1)
        // Replaying the level does not ask again.
        model.loadLevel(10)
        model.scene?.onLevelComplete?()
        #expect(model.reviewRequests == 1)
    }
}
