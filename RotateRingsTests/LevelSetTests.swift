//
//  LevelSetTests.swift
//  RotateRingsTests
//
//  A level set (`LevelSets`, debug builds) is a plain folder of level files that the game reads
//  like the app bundle, and switching to it leaves the shipped levels alone.
//

import Foundation
import Testing
@testable import RotateRings

private let appBundle = Bundle(for: GameScene.self)

@MainActor
struct LevelSetTests {

    /// A folder with the shipped levels 1 to `count`, the last one renamed so it can be told apart.
    private func makeSet(count: Int) throws -> Bundle {
        let folder = FileManager.default.temporaryDirectory.appending(path: "LevelSetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for number in 1...count {
            var file = try LevelLoader.load(level: number, in: appBundle)
            if number == count { file.name = "From the set" }
            let data = try JSONEncoder().encode(file)
            try data.write(to: folder.appending(path: "level\(number).json"))
        }
        return try #require(Bundle(url: folder))
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "LevelSetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aFolderOfLevelFilesPlaysLikeTheBundle() throws {
        let set = try makeSet(count: 3)
        #expect(LevelLoader.levelCount(in: set) == 3)
        #expect(try LevelLoader.load(level: 3, in: set).name == "From the set")
    }

    @Test func switchingSetsKeepsTheLevelNumber() throws {
        let defaults = makeDefaults()
        let model = GameViewModel(bundle: appBundle, defaults: defaults, boosters: BoosterInventory(defaults: defaults))
        let shippedCount = model.levelCount
        model.loadLevel(3)
        model.switchLevels(to: try makeSet(count: 3))
        #expect(model.levelNumber == 3)
        #expect(model.levelCount == 3)
        #expect(model.levelName == "From the set")
        model.switchLevels(to: appBundle)
        #expect(model.levelCount == shippedCount)
        #expect(model.levelName != "From the set")
    }
}
