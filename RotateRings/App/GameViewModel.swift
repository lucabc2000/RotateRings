//
//  GameViewModel.swift
//  RotateRings
//

import Foundation
import Observation
import SpriteKit
import SwiftUI

/// UserDefaults keys for the player's place in the campaign.
private enum ProgressKey {
    /// The campaign level the player is at. One past the last level means the campaign is finished,
    /// so a player who finished it lands on the first new level once an update adds more.
    static let level = "campaignLevel"
    /// Development override, given as the launch argument `-startLevel N`.
    static let startLevel = "startLevel"
}

/// Owns the current level, builds the scene for it and tracks completion for the SwiftUI shell.
/// The campaign level the player is at is remembered between launches; progress within a level is not.
@MainActor
@Observable
final class GameViewModel {
    private let bundle: Bundle
    private let defaults: UserDefaults

    private(set) var levelNumber = 1
    private(set) var levelName = ""
    private(set) var levelCount: Int
    private(set) var scene: GameScene?
    /// False until the current scene has drawn its first frame; the board stays hidden before that.
    private(set) var isSceneReady = false
    private(set) var errorMessage: String?
    var isLevelComplete = false
    /// True once the last level has been completed: there is nothing left to play until new levels
    /// arrive or the player starts over. Survives relaunches.
    private(set) var isCampaignFinished = false
    /// True while the laser waits for the player to pick a piece on the board.
    private(set) var isLaserArmed = false
    /// The booster earned by completing the current level, shown on the completion card.
    private(set) var earnedBooster: Booster?

    private let boosters: BoosterInventory
    private let reviews: ReviewPrompt
    /// Goes up by one each time a completed level is a good moment to ask for a review; the view
    /// watches it and makes the request.
    private(set) var reviewRequests = 0

    /// Where the board goes inside the full-screen game view: the area the header and the booster
    /// bar leave free, in the game view's coordinates. Handed to every scene.
    var boardFrame: CGRect? {
        didSet { scene?.boardFrame = boardFrame }
    }

    /// Full-screen flash layer driven by the scene's effects.
    private(set) var flashColor: UIColor = .white
    private(set) var flashOpacity: Double = 0
    private var flashTask: Task<Void, Never>?

    var hasNextLevel: Bool { levelNumber < levelCount }

    /// Fades the full-screen layer to the flash's colour and peak opacity, holds, then fades it out.
    func flashScreen(_ flash: ScreenFlash) {
        flashTask?.cancel()
        withAnimation(.easeOut(duration: flash.attack)) {
            flashColor = flash.color
            flashOpacity = flash.peakOpacity
        }
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(flash.attack + flash.hold))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeIn(duration: flash.release)) {
                self.flashOpacity = 0
            }
        }
    }

    // MARK: Boosters

    /// Boosters left to use. Levels opened from the Level Browser do not touch the player's supply.
    func boosterCount(_ booster: Booster) -> Int {
        isPreviewing ? 1 : boosters.count(of: booster)
    }

    /// Lightning: strikes a random piece. Costs one lightning once it has struck.
    func useLightning() {
        guard let scene, !isLevelComplete, boosterCount(.lightning) > 0 else { return }
        isLaserArmed = false
        scene.isLaserArmed = false
        if scene.destroyRandomPiece(), !isPreviewing {
            boosters.spend(.lightning)
        }
    }

    /// Laser: arms the scene so the next piece the player touches is vaporised. Tapping again disarms.
    /// Costs one laser when it fires, not when it is armed.
    func toggleLaser() {
        guard let scene, !isLevelComplete, isLaserArmed || boosterCount(.laser) > 0 else { return }
        isLaserArmed.toggle()
        scene.isLaserArmed = isLaserArmed
        SoundPlayer.shared.play(isLaserArmed ? .laserArm : .laserDisarm)
    }

    /// Level to open at launch: the one the player was at when the game was last open, or level 1.
    /// Overridable for development with the launch argument `-startLevel N`.
    nonisolated static func launchLevel(in defaults: UserDefaults = .standard) -> Int {
        let requested = defaults.integer(forKey: ProgressKey.startLevel)
        if requested > 0 { return requested }
        let saved = defaults.integer(forKey: ProgressKey.level)
        return saved > 0 ? saved : 1
    }

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard, boosters: BoosterInventory? = nil, startingLevel: Int? = nil) {
        self.bundle = bundle
        self.defaults = defaults
        self.boosters = boosters ?? .shared
        reviews = ReviewPrompt(defaults: defaults)
        let startingLevel = startingLevel ?? Self.launchLevel(in: defaults)
        levelCount = LevelLoader.levelCount(in: bundle)
        SoundPlayer.shared.preload()
        if levelCount > 0, startingLevel > levelCount {
            // Finished before, and no new levels since: back to the end screen, with no board.
            levelNumber = levelCount
            isCampaignFinished = true
        } else {
            loadLevel(min(max(1, startingLevel), max(1, levelCount)))
        }
    }

    /// What is on the board: a campaign level, or a level file opened from the Level Browser.
    enum PlaySource: Equatable {
        case campaign
        case preview(title: String)
    }

    private(set) var source: PlaySource = .campaign

    var isPreviewing: Bool {
        if case .preview = source { return true }
        return false
    }

    func loadLevel(_ number: Int) {
        levelNumber = number
        source = .campaign
        defaults.set(number, forKey: ProgressKey.level)
        do {
            var file = try LevelLoader.load(level: number, in: bundle)
            #if DEBUG
            // A runner-up chosen in the Level Browser stands in for the level until it is regenerated.
            if let swap = LevelSwaps.shared.candidateID(for: number), let swapped = try? LevelLoader.loadCandidate(id: swap, in: bundle) {
                file = swapped
            }
            #endif
            try install(file)
        } catch {
            fail(error)
        }
    }

    /// Opens any level file, outside the campaign order. `nextLevel()` returns to the campaign.
    func play(_ file: LevelFile, title: String) {
        source = .preview(title: title)
        previewFile = file
        do {
            try install(file)
        } catch {
            fail(error)
        }
    }

    func exitPreview() {
        loadLevel(levelNumber)
    }

    private func fail(_ error: Error) {
        scene = nil
        isSceneReady = false
        levelName = ""
        errorMessage = error.localizedDescription
    }

    private func install(_ file: LevelFile) throws {
        isLevelComplete = false
        isCampaignFinished = false
        isLaserArmed = false
        earnedBooster = nil
        errorMessage = nil
        do {
            let board = try file.makeBoard()
            let newScene = GameScene(board: board, size: CGSize(width: file.board.width, height: file.board.height))
            newScene.boardFrame = boardFrame
            newScene.onLevelComplete = { [weak self] in
                guard let self else { return }
                if !self.isPreviewing {
                    self.earnedBooster = self.boosters.collectReward(forCompleting: self.levelNumber)
                    // The level is done: a relaunch from the completion card opens the next one, or
                    // the end screen after the last.
                    self.defaults.set(self.levelNumber + 1, forKey: ProgressKey.level)
                    self.isCampaignFinished = !self.hasNextLevel
                    if self.reviews.shouldAsk(afterCompleting: self.levelNumber) {
                        self.reviewRequests += 1
                    }
                }
                self.isLevelComplete = true
                self.isLaserArmed = false
            }
            newScene.onLaserConsumed = { [weak self] in
                guard let self else { return }
                self.isLaserArmed = false
                if !self.isPreviewing {
                    self.boosters.spend(.laser)
                }
            }
            newScene.onScreenFlash = { [weak self] flash in
                self?.flashScreen(flash)
            }
            newScene.onFirstFrame = { [weak self, weak newScene] in
                // Ignore a late callback from a scene that has already been replaced.
                guard let self, let newScene, self.scene === newScene else { return }
                self.isSceneReady = true
            }
            flashTask?.cancel()
            flashOpacity = 0
            levelName = file.name
            isSceneReady = false
            scene = newScene
        }
    }

    func restart() {
        SoundPlayer.shared.play(.button)
        if case .preview(let title) = source, let previewFile {
            // Replay the same preview board.
            play(previewFile, title: title)
        } else {
            loadLevel(levelNumber)
        }
    }

    func nextLevel() {
        SoundPlayer.shared.play(.button)
        if isPreviewing {
            exitPreview()
        } else if hasNextLevel {
            loadLevel(levelNumber + 1)
        }
    }

    /// From the end screen: back to level 1. Boosters and their rewards are kept as they are, so
    /// playing through again does not pay out a second time.
    func startOver() {
        SoundPlayer.shared.play(.button)
        loadLevel(1)
    }

    /// The file behind the current preview, kept so restart can reload it.
    private var previewFile: LevelFile?
}
