//
//  GameSettings.swift
//  RotateRings
//

import Foundation
import Observation

/// Player preferences, persisted in UserDefaults. Both default to on.
@MainActor
@Observable
final class GameSettings {
    static let shared = GameSettings()

    private enum Key {
        static let sound = "soundEnabled"
        static let haptics = "hapticsEnabled"
    }

    var isSoundEnabled: Bool {
        didSet { UserDefaults.standard.set(isSoundEnabled, forKey: Key.sound) }
    }

    var isHapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(isHapticsEnabled, forKey: Key.haptics) }
    }

    private init() {
        let defaults = UserDefaults.standard
        isSoundEnabled = defaults.object(forKey: Key.sound) as? Bool ?? true
        isHapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
    }
}
