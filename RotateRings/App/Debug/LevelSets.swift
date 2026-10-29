//
//  LevelSets.swift
//  RotateRings
//
//  Debug only. Other sets of level files to play instead of the shipped ones, e.g. a trial run of
//  the generator. Each set is a folder in the app's Documents/LevelSets with the level files and
//  the generator's report, copied there by LevelForge/install-set.sh; the Level Browser switches
//  between them. The level files in the app bundle are never touched.
//

import Foundation

extension Bundle {
    /// Where the game reads its levels: the app bundle, or in debug builds the level set chosen in
    /// the Level Browser.
    static var levels: Bundle {
        #if DEBUG
        LevelSets.bundle
        #else
        .main
        #endif
    }
}

#if DEBUG
enum LevelSets {
    private static let key = "levelSet"

    static var folder: URL {
        URL.documentsDirectory.appending(path: "LevelSets", directoryHint: .isDirectory)
    }

    /// Names of the installed sets, sorted.
    static var names: [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    /// The set being played; nil for the shipped levels (also when the chosen set was removed).
    static var current: String? {
        get { UserDefaults.standard.string(forKey: key).flatMap { names.contains($0) ? $0 : nil } }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var bundle: Bundle {
        current.flatMap { Bundle(url: folder.appending(path: $0, directoryHint: .isDirectory)) } ?? .main
    }
}
#endif
