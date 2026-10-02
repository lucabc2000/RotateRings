//
//  LevelLoader.swift
//  RotateRings
//
//  Loads `levelN.json` files from a bundle.
//

import Foundation

enum LevelLoader {
    static func url(forLevel number: Int, in bundle: Bundle) -> URL? {
        bundle.url(forResource: "level\(number)", withExtension: "json")
    }

    /// Number of consecutive levels starting at 1 that exist in the bundle.
    static func levelCount(in bundle: Bundle) -> Int {
        var count = 0
        while url(forLevel: count + 1, in: bundle) != nil {
            count += 1
        }
        return count
    }

    static func load(level number: Int, in bundle: Bundle) throws -> LevelFile {
        guard let url = url(forLevel: number, in: bundle) else {
            throw LevelError.fileNotFound(level: number)
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> LevelFile {
        try JSONDecoder().decode(LevelFile.self, from: data)
    }

    // MARK: Generator side files

    /// A decoder matching the encoder the generator uses (ISO 8601 dates).
    static var sideFileDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func loadReport(in bundle: Bundle) throws -> LevelReport {
        try loadResource(LevelResources.report, as: LevelReport.self, in: bundle)
    }

    static func loadCandidates(in bundle: Bundle) throws -> CandidateStore {
        try loadResource(LevelResources.candidates, as: CandidateStore.self, in: bundle)
    }

    /// A runner-up level by its candidate id (see `LevelReport.candidateID`).
    static func loadCandidate(id: String, in bundle: Bundle) throws -> LevelFile {
        guard let file = try loadCandidates(in: bundle).candidates[id] else {
            throw LevelError.resourceNotFound("candidate \(id)")
        }
        return file
    }

    private static func loadResource<T: Decodable>(_ name: String, as type: T.Type, in bundle: Bundle) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LevelError.resourceNotFound("\(name).json")
        }
        return try sideFileDecoder.decode(T.self, from: Data(contentsOf: url))
    }
}
