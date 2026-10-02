//
//  BoardTests.swift
//  RotateRingsTests
//
//  Rule tests: rotation, clip holding, gap release, removal and blocking.
//

import Foundation
import Testing
@testable import RotateRings

// `clockwiseStep` and the `Make` helpers live in TestFixtures.swift.
private func deg(_ degrees: Double) -> Double { AngleMath.radians(fromDegrees: degrees) }

struct BoardTests {

    private func twoRingBoard() -> Board { Make.twoRingBoard() }

    @Test func connectionsAreDerivedFromClips() {
        let board = twoRingBoard()
        #expect(board.connections == [Connection(owner: "a", clipIndex: 0, ring: "b")])
        #expect(board.connections(for: "b").count == 1)
        #expect(!board.isComplete)
    }

    /// A clip that slipped off grips again when the ring turns back under it.
    @Test func turningBackUnderAReleasedClipGripsItAgain() {
        // x is gripped by a (at x's 90°) and b (at x's 0°); a also grips e, so a stays when x frees it.
        let x = Make.ring("x", at: .zero, gapCenterDegrees: 135)
        let a = Make.ring("a", at: Point(0, 120), gapCenterDegrees: 90, clips: [
            Make.downClip(grips: "x"),
            Clip(stemStart: Point(50, 0), stemEnd: Point(70, 0), grips: "e"),
        ])
        let e = Make.ring("e", at: Point(120, 120), gapCenterDegrees: 270)
        let b = Make.ring("b", at: Point(120, 0), gapCenterDegrees: 0, clips: [Make.leftClip(grips: "x")])
        var board = Board(pieces: [x, a, e, b])
        let aOnX = Connection(owner: "a", clipIndex: 0, ring: "x")
        #expect(board.connections.contains(aOnX))

        // Gap from 135° to 90°: a's clip slips off, x stays because b still holds it.
        guard case .moved(let release) = board.rotate("x", by: clockwiseStep) else { Issue.record("x should turn"); return }
        #expect(release.brokenConnections == [aOnX])
        #expect(!board.connections.contains(aOnX))
        #expect(board.piece("x") != nil)

        // Turning back puts the arc under the clip again and the grip is restored.
        guard case .moved(let regrip) = board.rotate("x", by: -clockwiseStep) else { Issue.record("x should turn back"); return }
        #expect(regrip.brokenConnections.isEmpty)
        #expect(board.connections.contains(aOnX))
        // a is an owner again, so it is pinned again.
        guard case .blocked = board.rotate("a", by: clockwiseStep) else { Issue.record("a should be pinned again"); return }
    }

    @Test func gripOnMissingPieceIsLoose() {
        let a = Make.ring("a", at: .zero, gapCenterDegrees: 0, clips: [Make.downClip(grips: "ghost")])
        var board = Board(pieces: [a])
        #expect(board.connections.isEmpty)
        #expect(board.removeUnconnectedPieces() == ["a"])
        #expect(board.isComplete)
    }

    @Test func rotatingRingUntilGapReachesClipBreaksConnection() throws {
        var board = twoRingBoard()

        // First clockwise step: gap moves from 180° to 135°. Still connected.
        let first = board.rotate("b", by: clockwiseStep)
        guard case .moved(let r1) = first else { Issue.record("expected rotation, got \(first)"); return }
        #expect(r1.brokenConnections.isEmpty)
        #expect(r1.removedPieceIDs.isEmpty)
        #expect(r1.to.isApproximately(clockwiseStep))
        #expect(board.connections.count == 1)

        // Second step: gap reaches 90°, where a's clip sits. The clip slips off, both pieces are free.
        let second = board.rotate("b", by: clockwiseStep)
        guard case .moved(let r2) = second else { Issue.record("expected rotation, got \(second)"); return }
        #expect(r2.brokenConnections == [Connection(owner: "a", clipIndex: 0, ring: "b")])
        #expect(Set(r2.removedPieceIDs) == ["a", "b"])
        #expect(board.isComplete)
        #expect(board.rotate("a", bySteps: -1) == .ignored)
    }

    @Test func heldRingIsNotBlockedByTheClipHoldingIt() {
        let board = twoRingBoard()
        // a's clip crosses b's arc, but that pair is excluded while connected.
        #expect(board.blockingReason(for: board.piece("b")!, at: deg(-20)) == nil)
        #expect(board.obstruction(for: "b", movingBy: clockwiseStep) == nil)
    }

    @Test func clipOwnerIsHeldByTheRingItGrips() {
        var board = twoRingBoard()
        let outcome = board.rotate("a", by: clockwiseStep)
        guard case .blocked(let blocked) = outcome else { Issue.record("expected block, got \(outcome)"); return }
        #expect(blocked.reason == .heldByClip(Connection(owner: "a", clipIndex: 0, ring: "b")))
        #expect(blocked.stop.isApproximately(blocked.from))
        #expect(board.piece("a")?.rotation == 0)
    }

    @Test func clipOwnerPivotingAtRingCenterIsStillPinnedUntilTheRingFreesIt() {
        // Spoke pivoting at the ring's center, clip at the ring's radius pointing right (0°). Gap at 270°.
        let ring = Make.ring("ring", at: .zero, radius: 60, gapCenterDegrees: 270)
        let spoke = Piece(id: "spoke", position: .zero,
                          shapes: [.segment(Segment(from: Point(-25, 0), to: Point(40, 0)))],
                          clips: [Clip(stemStart: Point(40, 0), stemEnd: Point(60, 0), grips: "ring")])
        var board = Board(pieces: [ring, spoke])
        let connection = Connection(owner: "spoke", clipIndex: 0, ring: "ring")
        #expect(board.connections == [connection])

        // Sharing the ring's center does not let the owner turn: it is held like any other clip owner.
        let attempt = board.rotate("spoke", by: clockwiseStep)
        guard case .blocked(let blocked) = attempt else { Issue.record("expected block, got \(attempt)"); return }
        #expect(blocked.reason == .heldByClip(connection))
        #expect(blocked.stop.isApproximately(blocked.from))

        // The ring turns its gap from 270° up to the clip at 0°; the clip slips off and both leave.
        let first = board.rotate("ring", by: deg(45))
        guard case .moved(let r1) = first else { Issue.record("expected rotation, got \(first)"); return }
        #expect(r1.brokenConnections.isEmpty)
        let second = board.rotate("ring", by: deg(45))
        guard case .moved(let r2) = second else { Issue.record("expected rotation, got \(second)"); return }
        #expect(r2.brokenConnections == [connection])
        #expect(Set(r2.removedPieceIDs) == ["ring", "spoke"])
        #expect(board.isComplete)
    }

    @Test func clipOnClosedRingNeverReleases() {
        let inner = Make.closedRing("inner", at: .zero, radius: 40)
        let outer = Make.closedRing("outer", at: .zero, radius: 65,
                                    clips: [Clip(stemStart: Point(0, 65), stemEnd: Point(0, 40), grips: "inner")])
        var board = Board(pieces: [inner, outer])
        // The outer ring owns the clip, so it is pinned; the gripped inner ring spins a full turn
        // without ever offering a gap.
        guard case .blocked(let pinned) = board.rotate("outer", by: clockwiseStep) else { Issue.record("outer should be pinned"); return }
        #expect(pinned.reason == .heldByClip(Connection(owner: "outer", clipIndex: 0, ring: "inner")))
        for _ in 0..<8 {
            let outcome = board.rotate("inner", by: clockwiseStep)
            guard case .moved(let r) = outcome else { Issue.record("expected rotation, got \(outcome)"); return }
            #expect(r.brokenConnections.isEmpty)
        }
        #expect(board.connections.count == 1)
        #expect(board.pieces.count == 2)
    }

    @Test func closedOuterRingIsFreedByInnerRingsGap() {
        let inner = Make.ring("inner", at: .zero, radius: 40, gapCenterDegrees: 0)
        let outer = Make.closedRing("outer", at: .zero, radius: 65,
                                    clips: [Clip(stemStart: Point(0, 65), stemEnd: Point(0, 40), grips: "inner")])
        var board = Board(pieces: [inner, outer])
        // The outer ring owns the clip, so it is pinned even though it shares the inner ring's center.
        guard case .blocked = board.rotate("outer", by: clockwiseStep) else { Issue.record("outer should be pinned"); return }
        // Clip is at 90°, gap at 0°: a quarter turn of the inner ring brings its gap to the clip.
        let outcome = board.rotate("inner", by: deg(90))
        guard case .moved(let r) = outcome else { Issue.record("expected rotation, got \(outcome)"); return }
        #expect(r.brokenConnections.count == 1)
        #expect(board.isComplete)
    }

    @Test func rotationIsBlockedByCollisionAndStopsEarly() {
        // Ring with its gap at the bottom; a bar pokes up through the gap into the ring.
        // The bar is anchored by a far away ring so it stays on the board.
        let ring = Make.ring("ring", at: .zero, radius: 60, gapCenterDegrees: 270)
        let bar = Piece(id: "bar", position: Point(0, -170),
                        shapes: [.segment(Segment(from: Point(0, -40), to: Point(0, 115)))],
                        clips: [Clip(stemStart: Point(0, -40), stemEnd: Point(0, -60), grips: "anchor")])
        let anchor = Make.ring("anchor", at: Point(0, -280), gapCenterDegrees: 180)
        let holder = Make.ring("holder", at: Point(0, 130), gapCenterDegrees: 90, clips: [Make.downClip(grips: "ring")])
        var board = Board(pieces: [ring, bar, anchor, holder])
        #expect(board.connections.count == 2)

        let outcome = board.rotate("ring", by: clockwiseStep)
        guard case .blocked(let blocked) = outcome else { Issue.record("expected block, got \(outcome)"); return }
        #expect(blocked.reason == .collision(with: "bar"))
        // The arc end starts 40° away from the bar (gap is 80° wide); it travels part of the way, then stops.
        #expect(blocked.stop < blocked.from)
        #expect(blocked.stop > clockwiseStep)
        #expect(board.piece("ring")?.rotation == 0)
    }

    @Test func releasedClipIsASleeveTheArcPassesThrough() {
        // b is gripped by a (top) and by c (right). After b frees a, a's clip stays on b's circle as a
        // sleeve: b can keep turning through it, and turning back grips it again.
        let a = Make.ring("a", at: Point(0, 120), gapCenterDegrees: 90, clips: [
            Make.downClip(grips: "b"),
            Clip(stemStart: Point(-50, 0), stemEnd: Point(-70, 0), grips: "e"),
        ])
        let e = Make.ring("e", at: Point(-120, 120), gapCenterDegrees: 180)
        let b = Make.ring("b", at: .zero, gapCenterDegrees: 135)
        let c = Make.ring("c", at: Point(120, 0), gapCenterDegrees: 0, clips: [Clip(stemStart: Point(-50, 0), stemEnd: Point(-70, 0), grips: "b")])
        var board = Board(pieces: [a, e, b, c])
        #expect(board.connections.count == 3)

        // Gap 135° → 90°: frees a's first clip. a stays (still clipped to e), b stays (c grips it).
        let first = board.rotate("b", by: clockwiseStep)
        guard case .moved(let r1) = first else { Issue.record("expected rotation, got \(first)"); return }
        #expect(r1.brokenConnections == [Connection(owner: "a", clipIndex: 0, ring: "b")])
        #expect(r1.removedPieceIDs.isEmpty)

        // The next step slides b's arc back under a's clip: not a collision, and a grips b again.
        let second = board.rotate("b", by: clockwiseStep)
        guard case .moved(let r2) = second else { Issue.record("expected rotation, got \(second)"); return }
        #expect(r2.brokenConnections.isEmpty)
        #expect(board.connections.contains(Connection(owner: "a", clipIndex: 0, ring: "b")))
    }

    @Test func stepRotationUsesConfiguredStep() {
        var board = twoRingBoard()
        guard case .moved(let r) = board.rotate("b", bySteps: -1) else { Issue.record("expected rotation"); return }
        #expect((r.to - r.from).isApproximately(-GameRules.rotationStep))
    }

    // MARK: Sliding bars

    /// Vertical bar (200 long) in a holder at the origin, reaching up through the gap of a ring above it.
    /// The ring is held on the board by a clip from a far away ring.
    private func slidingBoard() -> Board {
        let bar = Piece(id: "bar", motion: .slide, position: .zero, rotation: deg(90),
                        shapes: [.segment(Segment(from: Point(-100, 0), to: Point(100, 0)))])
        let ring = Make.ring("ring", at: Point(0, 140), radius: 60, gapCenterDegrees: 270)
        // The lock's grip point (x = 60) sits on the ring's circle (radius 60 around x = 0).
        let lock = Make.ring("lock", at: Point(130, 140), gapCenterDegrees: 0,
                             clips: [Clip(stemStart: Point(-50, 0), stemEnd: Point(-70, 0), grips: "ring")])
        return Board(pieces: [bar, ring, lock])
    }

    @Test func slidingBarIsHeldByItsHolder() {
        let board = slidingBoard()
        #expect(board.connections.contains(Connection(holderOf: "bar")))
        #expect(Board.isInHolder(board.piece("bar")!))
        #expect(board.piece("bar")!.slideAxis.x.isApproximately(0))
        #expect(board.piece("bar")!.slideAxis.y.isApproximately(1))
        // A held bar is not pinned: the holder lets it slide.
        #expect(board.clipHoldViolation(for: board.piece("bar")!) == nil)
    }

    @Test func barSlidesUntilItHitsTheRingArc() {
        var board = slidingBoard()
        // Upper end at y = 100, the inside of the ring's arc at y = 200: about 90 of travel before contact.
        guard case .blocked(let blocked) = board.slide("bar", by: 150) else { Issue.record("expected block"); return }
        #expect(blocked.reason == .collision(with: "ring"))
        #expect(blocked.stop > 80 && blocked.stop < 95)
        #expect(board.piece("bar")!.offset == 0)
    }

    @Test func barLeavesWhenSlidFullyOutOfTheHolder() {
        var board = slidingBoard()
        // Down 50: the bar's upper end (now at y = 50) still covers the holder.
        guard case .moved(let partial) = board.slide("bar", by: -50) else { Issue.record("expected slide"); return }
        #expect(partial.brokenConnections.isEmpty)
        #expect(board.piece("bar")!.translation.y.isApproximately(-50))
        // Down to -120: the upper end (y = -20) has cleared the 36 long holder, so the bar is free and leaves.
        guard case .moved(let out) = board.slide("bar", by: -70) else { Issue.record("expected slide"); return }
        #expect(out.brokenConnections == [Connection(holderOf: "bar")])
        #expect(out.removedPieceIDs == ["bar"])
        #expect(board.pieces.map(\.id) == ["ring", "lock"])
    }

    @Test func slidingOutAndBackBeforeReleasingKeepsTheHold() {
        var board = slidingBoard()
        _ = board.drag("bar", by: -130)
        #expect(!Board.isInHolder(board.piece("bar")!))
        _ = board.drag("bar", by: 130)
        let settled = board.settle("bar")
        #expect(settled?.brokenConnections.isEmpty == true)
        #expect(board.connections.contains(Connection(holderOf: "bar")))
    }

    @Test func ringCannotTurnIntoTheBarInItsGap() {
        var board = slidingBoard()
        guard case .blocked(let blocked) = board.rotate("ring", bySteps: -1) else { Issue.record("expected block"); return }
        #expect(blocked.reason == .collision(with: "bar"))
    }

    @Test func slidingBarWithAClipIsPinned() {
        let bar = Piece(id: "bar", motion: .slide, position: .zero, rotation: deg(90),
                        shapes: [.segment(Segment(from: Point(-100, 0), to: Point(100, 0)))],
                        clips: [Clip(stemStart: Point(100, 0), stemEnd: Point(120, 0), grips: "ring")])
        let ring = Make.ring("ring", at: Point(0, 170), gapCenterDegrees: 180)
        var board = Board(pieces: [bar, ring])
        guard case .blocked(let blocked) = board.slide("bar", by: -20) else { Issue.record("expected block"); return }
        #expect(blocked.reason == .heldByClip(Connection(owner: "bar", clipIndex: 0, ring: "ring")))
        #expect(blocked.stop == 0)
    }

    @Test func slideBarIsNotHeldWhenItStartsOutsideItsHolder() {
        let bar = Piece(id: "bar", motion: .slide, position: .zero,
                        shapes: [.segment(Segment(from: Point(40, 0), to: Point(140, 0)))])
        var board = Board(pieces: [bar])
        #expect(board.connections.isEmpty)
        #expect(board.removeUnconnectedPieces() == ["bar"])
    }

    // MARK: Pushing bars (slide until blocked or free)

    /// A push away from the ring: nothing is in the way, so the bar slides until its arm has left the
    /// hub, and then it is free and leaves.
    @Test func straightBarPushedTheClearWaySlidesOutAndLeaves() {
        var board = slidingBoard()
        let stop = board.slideStop("bar", direction: -1)
        #expect(stop?.exits == true)
        #expect(stop?.reason == nil)
        // Upper end at +100 must clear the hub's half length (18) plus a hair.
        #expect(stop!.delta.isApproximately(-119))

        let outcome = board.slideToStop("bar", direction: -1)
        guard case .moved(let result) = outcome else { Issue.record("expected the bar to slide out, got \(outcome)"); return }
        #expect(result.to.isApproximately(-119))
        #expect(result.brokenConnections == [Connection(holderOf: "bar")])
        #expect(result.removedPieceIDs == ["bar"])
        #expect(board.pieces.map(\.id) == ["ring", "lock"])
    }

    /// An L-bar's leg cannot pass its hub: pushed leg first it stops when the leg reaches the hub,
    /// pushed the other way it slides out.
    @Test func lBarIsBlockedByItsOwnLegAtTheHub() {
        // Horizontal axis. Arm from -60 to 60, leg of 40 going up from the +60 end.
        let elbow = Piece(id: "elbow", motion: .slide, position: .zero, shapes: [
            .segment(Segment(from: Point(-60, 0), to: Point(60, 0))),
            .segment(Segment(from: Point(60, 0), to: Point(60, 40))),
        ])
        var board = Board(pieces: [elbow])
        #expect(board.connections == [Connection(holderOf: "elbow")])

        // Leg first (toward -x): the leg stops `hubClearance` short of the hub center.
        let toward = board.slideStop("elbow", direction: -1)
        #expect(toward?.exits == false)
        #expect(toward?.reason == .hub)
        #expect(toward!.delta < -40 && toward!.delta > -(60 - GameRules.hubClearance + 0.5))
        guard case .moved(let blocked) = board.slideToStop("elbow", direction: -1) else { Issue.record("expected a partial slide"); return }
        #expect(blocked.removedPieceIDs.isEmpty)
        #expect(board.piece("elbow") != nil)
        // Pressed against the hub it cannot go any further.
        guard case .blocked(let stuck) = board.slideToStop("elbow", direction: -1) else { Issue.record("expected a block at the hub"); return }
        #expect(stuck.reason == .hub)

        // The other way the straight arm runs out of the hub and the bar leaves.
        let away = board.slideStop("elbow", direction: 1)
        #expect(away?.exits == true)
        guard case .moved(let out) = board.slideToStop("elbow", direction: 1) else { Issue.record("expected the elbow to slide out"); return }
        #expect(out.removedPieceIDs == ["elbow"])
        #expect(board.isComplete)
    }

    /// A bar pushed into another piece stops at the collision; once that piece is gone the same
    /// push takes it out of the hub.
    @Test func barBlockedByAnotherPieceIsFreedWhenThatPieceIsRemoved() {
        var board = slidingBoard()
        // Up: the bar's upper end runs into the inside of the ring's arc.
        let first = board.slideStop("bar", direction: 1)
        #expect(first?.exits == false)
        #expect(first?.reason == .collision(with: "ring"))
        guard case .moved(let partial) = board.slideToStop("bar", direction: 1) else { Issue.record("expected a partial slide"); return }
        #expect(partial.to > 80 && partial.to < 95)
        #expect(partial.removedPieceIDs.isEmpty)
        #expect(board.connections.contains(Connection(holderOf: "bar")))

        // Pushing again does nothing: it is already against the arc.
        guard case .blocked(let stuck) = board.slideToStop("bar", direction: 1) else { Issue.record("expected a block"); return }
        #expect(stuck.reason == .collision(with: "ring"))

        // Remove the ring (its lock loses its grip and leaves too); now the way up is clear.
        let destroyed = board.destroy("ring")
        #expect(destroyed?.freedPieceIDs == ["lock"])
        let second = board.slideStop("bar", direction: 1)
        #expect(second?.exits == true)
        guard case .moved(let out) = board.slideToStop("bar", direction: 1) else { Issue.record("expected the bar to slide out"); return }
        #expect(out.removedPieceIDs == ["bar"])
        #expect(board.isComplete)
    }

    // MARK: Destroying (power-ups)

    @Test func destroyingARingFreesWhateverItHeld() {
        // a and d both grip b; b grips c. Blowing up b leaves a and d without connections.
        let a = Make.ring("a", at: Point(0, 120), gapCenterDegrees: 90, clips: [Make.downClip(grips: "b")])
        let b = Make.ring("b", at: .zero, gapCenterDegrees: 135, clips: [Make.downClip(grips: "c")])
        let c = Make.ring("c", at: Point(0, -120), gapCenterDegrees: 180)
        let d = Make.ring("d", at: Point(120, 0), gapCenterDegrees: 0, clips: [Clip(stemStart: Point(-50, 0), stemEnd: Point(-70, 0), grips: "b")])
        var board = Board(pieces: [a, b, c, d])
        #expect(board.connections.count == 3)

        let result = board.destroy("b")
        #expect(result?.destroyedPieceID == "b")
        #expect(Set(result?.freedPieceIDs ?? []) == ["a", "c", "d"])
        #expect(board.isComplete)
        #expect(board.connections.isEmpty)
    }

    @Test func destroyingAClipOwnerLeavesTheRingIfOthersHoldIt() {
        let a = Make.ring("a", at: Point(0, 120), gapCenterDegrees: 90, clips: [Make.downClip(grips: "b")])
        let b = Make.ring("b", at: .zero, gapCenterDegrees: 135)
        let d = Make.ring("d", at: Point(120, 0), gapCenterDegrees: 0, clips: [Clip(stemStart: Point(-50, 0), stemEnd: Point(-70, 0), grips: "b")])
        var board = Board(pieces: [a, b, d])

        let result = board.destroy("a")
        #expect(result?.freedPieceIDs.isEmpty == true)
        #expect(Set(board.pieces.map(\.id)) == ["b", "d"])
        #expect(board.connections == [Connection(owner: "d", clipIndex: 0, ring: "b")])
    }

    @Test func destroyingAnUnknownPieceDoesNothing() {
        var board = twoRingBoard()
        #expect(board.destroy("ghost") == nil)
        #expect(board.pieces.count == 2)
    }

    // MARK: Dragging

    @Test func dragFollowsFingerAndStaysWhereReleased() {
        var board = twoRingBoard()
        for _ in 0..<8 {
            let result = board.drag("b", by: -0.1)
            #expect(result?.blockedBy == nil)
        }
        #expect(board.piece("b")!.rotation.isApproximately(-0.8))

        // Released at -0.8 rad (gap center now at ~134°): the clip at 90° is still gripped.
        let settled = board.settle("b")
        #expect(settled?.value.isApproximately(-0.8) == true)
        #expect(board.piece("b")!.rotation.isApproximately(-0.8))
        #expect(settled?.brokenConnections.isEmpty == true)
        #expect(board.connections.count == 1)

        // Drag on to -1.5 rad (gap center at ~94°): the clip now sits inside the gap and slips off.
        for _ in 0..<7 { _ = board.drag("b", by: -0.1) }
        let finish = board.settle("b")
        #expect(finish?.value.isApproximately(-1.5) == true)
        #expect(finish?.brokenConnections.count == 1)
        #expect(Set(finish?.removedPieceIDs ?? []) == ["a", "b"])
        #expect(board.isComplete)
    }

    @Test func pinnedPieceDoesNotCreepUnderSmallDrags() {
        var board = twoRingBoard()
        for _ in 0..<50 {
            let result = board.drag("a", by: -0.02)
            #expect(result?.value == 0)
            #expect(result?.blockedBy == .heldByClip(Connection(owner: "a", clipIndex: 0, ring: "b")))
        }
        #expect(board.piece("a")?.rotation == 0)
        let settled = board.settle("a")
        #expect(settled?.value == 0)
        #expect(settled?.brokenConnections.isEmpty == true)
    }

    @Test func dragStopsAtCollisionAndStaysThereWhenReleased() {
        // Same layout as the collision test: a bar pokes through the ring's gap.
        let ring = Make.ring("ring", at: .zero, radius: 60, gapCenterDegrees: 270)
        let bar = Piece(id: "bar", position: Point(0, -170),
                        shapes: [.segment(Segment(from: Point(0, -40), to: Point(0, 115)))],
                        clips: [Clip(stemStart: Point(0, -40), stemEnd: Point(0, -60), grips: "anchor")])
        let anchor = Make.ring("anchor", at: Point(0, -280), gapCenterDegrees: 180)
        let holder = Make.ring("holder", at: Point(0, 130), gapCenterDegrees: 90, clips: [Make.downClip(grips: "ring")])
        var board = Board(pieces: [ring, bar, anchor, holder])

        let dragged = board.drag("ring", by: -0.6)
        #expect(dragged?.blockedBy == .collision(with: "bar"))
        let stop = dragged!.value
        #expect(stop < 0 && stop > -0.6)
        #expect(board.piece("ring")!.rotation == stop)

        // Released against the bar, the ring simply stays there.
        let settled = board.settle("ring")
        #expect(settled?.value == stop)
        #expect(board.piece("ring")!.rotation == stop)
        #expect(board.connections.count == 2)
    }
}
