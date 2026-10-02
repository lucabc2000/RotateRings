//
//  ReviewPrompt.swift
//  RotateRings
//
//  When to ask the player for an App Store review: after a few milestone levels, the first time
//  each is completed. The system has the last word (it shows the prompt at most three times a year
//  and not at all if the player turned review requests off), so this only picks good moments.
//

import Foundation

@MainActor
final class ReviewPrompt {
    /// Completing these levels for the first time asks for a review. Early enough that most players
    /// who enjoy the game get asked, spread out so nobody is asked twice in a short while.
    static let milestones = [10, 25, 40]

    private static let askedThroughKey = "reviewAskedThroughLevel"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether completing `level` is a moment to ask. True once per milestone, and never for a
    /// milestone at or below one that has already been used, so replaying levels does not ask again.
    func shouldAsk(afterCompleting level: Int) -> Bool {
        guard Self.milestones.contains(level), level > defaults.integer(forKey: Self.askedThroughKey) else { return false }
        defaults.set(level, forKey: Self.askedThroughKey)
        return true
    }
}
