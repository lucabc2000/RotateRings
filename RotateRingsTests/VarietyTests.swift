//
//  VarietyTests.swift
//  RotateRingsTests
//
//  The board kinds of LEVEL-DESIGN.md §15: mirrored boards are symmetric, silhouettes hold what they
//  should, small boards are small, and every milestone picture builds.
//

import Foundation
import Testing
@testable import RotateRings

struct VarietyTests {

    /// Every piece has a mirror image about the board's vertical centre line: same kind and size, and
    /// a ring's gap at the mirrored angle.
    private func isMirrored(_ draft: LevelDraft) -> Bool {
        draft.pieces.allSatisfy { piece in
            draft.pieces.contains { other in
                other.kind == piece.kind && abs(other.position.x - (draft.board.width - piece.position.x)) < 0.5
                    && abs(other.position.y - piece.position.y) < 0.5 && other.radius == piece.radius
                    && (piece.gapCenterDegrees.map { gap in
                        other.gapCenterDegrees.map { degreeDifference($0, 180 - gap) < 0.5 } ?? false
                    } ?? true)
            }
        }
    }

    private func drafts(_ template: LevelTemplate, seeds: Int) -> [LevelDraft] {
        (1...seeds).compactMap { seed in
            var rng = SplitMix64(seed: UInt64(seed))
            return template.build(150, &rng)
        }
    }

    @Test func mirroredKnotsAreSymmetric() {
        let built = drafts(Compositions.knot("hubs-field", holders: 3, bars: 2, tails: 0.4, mirror: true), seeds: 12)
        #expect(!built.isEmpty)
        for draft in built { #expect(isMirrored(draft)) }
    }

    @Test func mirroredFreeKnotsAreSymmetric() {
        let built = drafts(Compositions.freeKnot(rings: 18...22, holders: 3, tails: 0.4, mirror: true), seeds: 30)
        #expect(!built.isEmpty)
        for draft in built { #expect(isMirrored(draft)) }
    }

    @Test func silhouettesHoldWhatTheyShould() throws {
        let circle = try #require(Silhouette.all["circle"]), donut = try #require(Silhouette.all["donut"])
        #expect(circle.contains(.zero, unit: 150))
        #expect(!circle.contains(Point(160, 0), unit: 150))
        #expect(!donut.contains(.zero, unit: 150))
        #expect(donut.contains(Point(100, 0), unit: 150))
        #expect(Silhouette.all.values.filter(\.isSymmetric).count == 5)
    }

    @Test func smallDesignsUseTheSmallBoard() {
        let built = drafts(Compositions.hubWeb("hubs-mini", clips: 2...3, holders: 3, tails: 0.85, small: true), seeds: 4)
        #expect(!built.isEmpty)
        for draft in built {
            #expect(draft.board == .small)
            #expect((8...12).contains(draft.pieces.count))
        }
    }

    @Test func everyRewardLevelHasAPictureThatBuilds() {
        #expect(PictureLibrary.all.count == 9)
        #expect(Set(PictureLibrary.milestones.keys) == [20, 40, 60, 80, 120, 140, 160, 180])
        for (level, name) in PictureLibrary.milestones {
            #expect(!drafts(Compositions.picture(name), seeds: 24).isEmpty, "level \(level): \(name) builds no board")
        }
    }
}
