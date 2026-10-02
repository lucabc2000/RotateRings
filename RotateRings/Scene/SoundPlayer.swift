//
//  SoundPlayer.swift
//  RotateRings
//
//  The game's sound effects. Each `Sound` names a clip in the Sounds folder; to change a sound,
//  copy a different clip into that folder and point the case at its file name.
//

import AVFoundation

/// One effect per game moment. The raw value is the file name (without extension) in the Sounds folder.
enum Sound: String, CaseIterable {
    /// Finger lands on a piece: a mouse click.
    case grab = "Mouse_Click-005"
    /// A dragged piece is pressed against an obstruction: a low pop that drops in pitch.
    case bump = "Casual_Click_Pop_UI_8"
    /// A piece is released and stays on the board: one plain pop.
    case settle = "Casual_Click_Pop_UI_1"
    /// One or more freed pieces fly off the board: five quick pops rising in pitch.
    case flyOff = "Casual_Click_Pop_UI_39"
    /// The last piece has left the board: a positive collect chime. (The file name really has `_-`.)
    case levelComplete = "Positive_Button_Collect_-037"
    /// The lightning bolt hits its target: a deep rumbling explosion.
    case lightningStrike = "Big_Explosion-003"
    /// The laser booster is armed: a one-second rising power-up.
    case laserArm = "Power_UP-001"
    /// The laser booster is disarmed without firing: a one-second falling power-down.
    case laserDisarm = "Power_DOWN-006"
    /// The laser reticle locks onto a piece: a short rising synth beep.
    case laserLock = "Synth_Button-022"
    /// The laser beam fires and the piece dissolves: a firework whistle and bang.
    case laserFire = "Explosion_Firework-001"
    /// Restart and next-level buttons: a short synth button tap.
    case button = "Synth_Button-019"

    /// Relative loudness, so frequent sounds stay in the background and rare ones stand out.
    var volume: Float {
        switch self {
        // The mouse click is recorded far quieter than the other clips, so it plays at full volume.
        case .grab: 1
        case .bump: 0.7
        case .settle: 0.6
        case .flyOff: 0.8
        case .levelComplete: 1
        case .lightningStrike: 1
        case .laserArm, .laserDisarm: 0.6
        case .laserLock: 0.7
        case .laserFire: 0.9
        case .button: 0.5
        }
    }
}

/// Preloads every effect once and plays them on demand.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    /// The clips and the queue they live on. An AVAudioPlayer activates the audio session whenever it
    /// builds its playback queue: in `prepareToPlay`, and again in `play` once a clip has played to
    /// its end, because finishing tears the queue down. Activating can block, so the players are
    /// created and played only on this queue, never on the main thread. AVAudioPlayer is not
    /// Sendable; confining it to one serial queue is what makes sharing the deck safe.
    private final class Deck: @unchecked Sendable {
        let queue = DispatchQueue(label: "RotateRings.SoundPlayer", qos: .userInitiated)
        private var players: [Sound: AVAudioPlayer] = [:]

        /// Configures the audio session and primes every clip. Call on `queue`.
        func load() {
            let session = AVAudioSession.sharedInstance()
            // Ambient: obeys the silent switch and mixes with whatever the player is already listening to.
            try? session.setCategory(.ambient, mode: .default)
            try? session.setActive(true)

            for sound in Sound.allCases {
                // Clips may be dropped in as WAV or CAF; the first one found wins.
                let url = ["wav", "caf"].lazy
                    .compactMap { Bundle.main.url(forResource: sound.rawValue, withExtension: $0) }
                    .first
                guard let url, let player = try? AVAudioPlayer(contentsOf: url) else {
                    assertionFailure("Missing sound file \(sound.rawValue)")
                    continue
                }
                player.volume = sound.volume
                player.prepareToPlay()
                players[sound] = player
            }
        }

        /// Plays the clip from the start. Call on `queue`.
        func play(_ sound: Sound) {
            guard let player = players[sound] else { return }
            player.currentTime = 0
            player.play()
        }
    }

    private enum LoadState {
        case idle, loading, ready
    }

    private let deck = Deck()
    /// Plays before the clips are ready are dropped, which only affects the first fraction of a
    /// second after launch.
    private var state = LoadState.idle

    private init() {}

    /// Starts loading the clips so the first play has no delay. Safe to call more than once.
    func preload() {
        guard state == .idle else { return }
        state = .loading
        deck.queue.async { [deck] in
            deck.load()
            Task { @MainActor in SoundPlayer.shared.state = .ready }
        }
    }

    /// Plays the effect from the start, cutting off an earlier play of the same effect.
    /// Silent while sound is switched off in settings.
    func play(_ sound: Sound) {
        preload()
        guard GameSettings.shared.isSoundEnabled, state == .ready else { return }
        deck.queue.async { [deck] in deck.play(sound) }
    }
}
