//
//  Board.swift
//  RotateRings
//
//  The game state and all rules: moving (turning or sliding), blocking, breaking connections and
//  removing pieces.
//

import Foundation

struct Board: Equatable, Sendable {

    // MARK: Outcomes

    /// Why a move stopped early.
    enum BlockReason: Equatable, Sendable {
        /// The moving geometry would hit the given piece.
        case collision(with: Piece.ID)
        /// A ring is holding one of the moving piece's clips and would not let it leave the arc.
        case heldByClip(Connection)
        /// A bent arm or corner of a sliding bar ran into its own hub; only the axial arm passes through.
        case hub
    }

    /// Where a sliding bar ends up when pushed in one direction.
    struct SlideStop: Equatable, Sendable {
        /// Signed offset change along the axis.
        let delta: Double
        /// True when the bar's arm leaves the hub completely at the end of the move, so the bar is free.
        let exits: Bool
        /// Why it stopped, when it did not exit.
        let reason: BlockReason?
    }

    /// A completed move. Values are radians for turning pieces and distances for sliding pieces.
    struct MoveResult: Equatable, Sendable {
        let pieceID: Piece.ID
        let from: Double
        let to: Double
        let brokenConnections: [Connection]
        /// Pieces that lost their last connection and left the board, in removal order.
        let removedPieceIDs: [Piece.ID]
    }

    struct BlockedResult: Equatable, Sendable {
        let pieceID: Piece.ID
        let from: Double
        /// The furthest value reached before the obstruction (equal to `from` when it could not move at all).
        let stop: Double
        let reason: BlockReason
    }

    enum MoveOutcome: Equatable, Sendable {
        case moved(MoveResult)
        case blocked(BlockedResult)
        /// The piece does not exist (anymore).
        case ignored
    }

    /// Result of following a finger by some amount.
    struct DragResult: Equatable, Sendable {
        let pieceID: Piece.ID
        /// The rotation or slide offset the piece ended up at.
        let value: Double
        /// Set when the piece could not follow the whole delta.
        let blockedBy: BlockReason?
    }

    /// Result of letting go of a piece: connections are resolved where it was released.
    struct SettleResult: Equatable, Sendable {
        let pieceID: Piece.ID
        let value: Double
        let brokenConnections: [Connection]
        let removedPieceIDs: [Piece.ID]
    }

    // MARK: State

    private(set) var pieces: [Piece]
    private(set) var connections: [Connection]

    /// Builds a board and derives the active connections from the pieces: every clip whose square sits
    /// on its ring's arc, and every sliding piece that sits in its holder.
    init(pieces: [Piece]) {
        self.pieces = pieces
        self.connections = []
        connections = Self.potentialConnections(of: pieces).filter { isHolding($0) }
    }

    /// Restores a board from a snapshot of pieces and active connections without re-deriving them.
    /// Used by the solver, which carries connections in its state.
    init(restoring pieces: [Piece], connections: [Connection]) {
        self.pieces = pieces
        self.connections = connections
    }

    /// Every connection these pieces could ever form: each clip aimed at an existing ring, and each
    /// sliding piece's holder. Whether one is active depends on the geometry at the time.
    static func potentialConnections(of pieces: [Piece]) -> [Connection] {
        var result: [Connection] = []
        for piece in pieces {
            for (index, clip) in piece.clips.enumerated() {
                guard let target = clip.grips,
                      let ring = pieces.first(where: { $0.id == target }),
                      ring.id != piece.id,
                      ring.ringArc != nil else { continue }
                result.append(Connection(owner: piece.id, clipIndex: index, ring: ring.id))
            }
            if piece.motion == .slide {
                result.append(Connection(holderOf: piece.id))
            }
        }
        return result
    }

    var isComplete: Bool { pieces.isEmpty }

    func piece(_ id: Piece.ID) -> Piece? {
        pieces.first { $0.id == id }
    }

    func connections(for id: Piece.ID) -> [Connection] {
        connections.filter { $0.involves(id) }
    }

    // MARK: Discrete moves

    /// Rotates a piece by a whole number of steps (negative is clockwise) if the sweep is free,
    /// then resolves connections and removals. Equivalent to a drag released exactly there.
    mutating func rotate(_ id: Piece.ID, bySteps steps: Int) -> MoveOutcome {
        move(id, by: Double(steps) * GameRules.rotationStep)
    }

    /// Rotates a turning piece by `delta` radians if the full sweep is free.
    mutating func rotate(_ id: Piece.ID, by delta: Double) -> MoveOutcome {
        move(id, by: delta)
    }

    /// Slides a sliding piece by `distance` along its axis if the full path is free.
    mutating func slide(_ id: Piece.ID, by distance: Double) -> MoveOutcome {
        move(id, by: distance)
    }

    /// Moves a piece by `delta` (radians or distance, depending on its motion) if the whole path is
    /// free, then resolves connections and removals.
    mutating func move(_ id: Piece.ID, by delta: Double) -> MoveOutcome {
        guard let index = pieces.firstIndex(where: { $0.id == id }) else { return .ignored }
        let from = pieces[index].movement

        if let obstruction = obstruction(for: id, movingBy: delta) {
            return .blocked(BlockedResult(pieceID: id, from: from, stop: obstruction.stop, reason: obstruction.reason))
        }
        guard let result = applyFreeMove(id, by: delta) else { return .ignored }
        return .moved(result)
    }

    /// Applies a move whose whole path the caller has already checked with `obstruction(for:movingBy:)`,
    /// then resolves connections and removals. `move` is `obstruction` followed by this; the solver
    /// calls it directly after one shared sweep covers several step counts.
    @discardableResult
    mutating func applyFreeMove(_ id: Piece.ID, by delta: Double) -> MoveResult? {
        guard let index = pieces.firstIndex(where: { $0.id == id }) else { return nil }
        let from = pieces[index].movement
        pieces[index].movement = from + delta
        let broken = refreshConnections(involving: id)
        let removed = removeUnconnectedPieces()
        return MoveResult(pieceID: id, from: from, to: from + delta, brokenConnections: broken, removedPieceIDs: removed)
    }

    // MARK: Sliding

    /// How far a sliding bar travels when pushed in `direction` (+1 along its axis, -1 against it):
    /// until something blocks it, or until its arm has left the hub and it is free. Nil for pieces
    /// that do not slide. The player drags bars by hand (`drag`/`settle`); this is the solver's
    /// macro move, one push as far as it goes.
    func slideStop(_ id: Piece.ID, direction: Double) -> SlideStop? {
        guard let piece = piece(id), piece.motion == .slide, let arm = piece.axialArm else { return nil }
        let sign: Double = direction >= 0 ? 1 : -1
        let half = GameRules.holderLength / 2
        let low = min(arm.from.x, arm.to.x)
        let high = max(arm.from.x, arm.to.x)
        // Offset at which the trailing end of the arm has cleared the hub by a hair.
        let exitOffset = sign > 0 ? half + 1 - low : -half - 1 - high
        let fullDelta = exitOffset - piece.offset
        guard fullDelta * sign > 0 else { return SlideStop(delta: 0, exits: true, reason: nil) }
        if let obstruction = obstruction(for: id, movingBy: fullDelta) {
            return SlideStop(delta: obstruction.stop - piece.offset, exits: false, reason: obstruction.reason)
        }
        return SlideStop(delta: fullDelta, exits: true, reason: nil)
    }

    /// Pushes a sliding bar in `direction` until it is blocked or free, then resolves connections and
    /// removals. A bar that exits its hub leaves the board.
    mutating func slideToStop(_ id: Piece.ID, direction: Double) -> MoveOutcome {
        guard let stop = slideStop(id, direction: direction), let from = piece(id)?.offset else { return .ignored }
        guard abs(stop.delta) >= 0.5 else {
            return .blocked(BlockedResult(pieceID: id, from: from, stop: from, reason: stop.reason ?? .hub))
        }
        guard let result = applyFreeMove(id, by: stop.delta) else { return .ignored }
        return .moved(result)
    }

    // MARK: Dragging

    /// Moves a piece by `delta` to follow a finger, stopping early at any obstruction.
    /// Connections are not resolved until the piece settles.
    mutating func drag(_ id: Piece.ID, by delta: Double) -> DragResult? {
        guard let index = pieces.firstIndex(where: { $0.id == id }) else { return nil }
        if let obstruction = obstruction(for: id, movingBy: delta) {
            pieces[index].movement = obstruction.stop
            return DragResult(pieceID: id, value: obstruction.stop, blockedBy: obstruction.reason)
        }
        pieces[index].movement += delta
        return DragResult(pieceID: id, value: pieces[index].movement, blockedBy: nil)
    }

    /// Lets go of a piece: it stays exactly where the finger left it, and connections and removals are
    /// resolved there.
    mutating func settle(_ id: Piece.ID) -> SettleResult? {
        guard let piece = piece(id) else { return nil }
        let broken = refreshConnections(involving: id)
        let removed = removeUnconnectedPieces()
        return SettleResult(pieceID: id, value: piece.movement, brokenConnections: broken, removedPieceIDs: removed)
    }

    // MARK: Power-ups

    /// Result of destroying a piece outright.
    struct DestroyResult: Equatable, Sendable {
        /// The piece that was destroyed.
        let destroyedPieceID: Piece.ID
        /// Pieces that lost their last connection because of it and left the board too.
        let freedPieceIDs: [Piece.ID]
    }

    /// Removes a piece regardless of its connections (rocket / hammer power-ups). Everything it was
    /// holding or held by loses that connection; pieces left with none leave as well.
    mutating func destroy(_ id: Piece.ID) -> DestroyResult? {
        guard pieces.contains(where: { $0.id == id }) else { return nil }
        pieces.removeAll { $0.id == id }
        connections.removeAll { $0.involves(id) }
        let freed = removeUnconnectedPieces()
        return DestroyResult(destroyedPieceID: id, freedPieceIDs: freed)
    }

    /// Removes every piece that nothing holds: no active connection and no other piece within touching
    /// distance. Removal cascades, because a departing piece can leave a neighbour clear. Returns the
    /// removed IDs in removal order.
    @discardableResult
    mutating func removeUnconnectedPieces() -> [Piece.ID] {
        var removed: [Piece.ID] = []
        var changed = true
        while changed {
            changed = false
            // A sliding bar out of its hub is free no matter what it touches.
            for piece in pieces where !connections.contains(where: { $0.involves(piece.id) }) && (piece.motion == .slide || !isTouchingAnotherPiece(piece)) {
                pieces.removeAll { $0.id == piece.id }
                removed.append(piece.id)
                changed = true
            }
        }
        return removed
    }

    /// Whether a body stroke of `piece` lies within `GameRules.touchDistance` of another piece's body.
    /// Clips do not count on either side, so a released clip never holds its ring back.
    func isTouchingAnotherPiece(_ piece: Piece) -> Bool {
        func bodies(of p: Piece) -> [Primitive] {
            p.worldPrimitives().compactMap { if case .body = $0.source { return $0.primitive } else { return nil } }
        }
        let own = bodies(of: piece)
        let center = piece.translation
        let reach = piece.collisionReach
        for other in pieces where other.id != piece.id {
            guard other.translation.distance(to: center) <= reach + other.collisionReach + GameRules.touchDistance else { continue }
            let theirs = bodies(of: other)
            for a in own {
                for b in theirs where Geometry.distance(a, b) < GameRules.touchDistance {
                    return true
                }
            }
        }
        return false
    }

    // MARK: Sweep / blocking

    struct Obstruction: Equatable, Sendable {
        /// The furthest free rotation or offset.
        let stop: Double
        let reason: BlockReason
    }

    /// Returns the first obstruction of the move, or `nil` if the whole path is free.
    ///
    /// A piece held back by the clip rule cannot move at all; otherwise collisions are sampled along
    /// the path and the last free value is reported.
    func obstruction(for id: Piece.ID, movingBy delta: Double) -> Obstruction? {
        guard let piece = piece(id), delta != 0 else { return nil }

        if let held = clipHoldViolation(for: piece) {
            return Obstruction(stop: piece.movement, reason: held)
        }

        let sampleStep = piece.motion == .slide ? GameRules.slideSampleDistance : GameRules.sweepSampleStep
        let steps = max(1, Int((abs(delta) / sampleStep).rounded(.up)))
        // The other pieces do not move during the sweep, so their world geometry is computed once.
        let others = collisionTargets(excluding: piece.id)
        var lastFree = piece.movement
        for k in 1...steps {
            let value = piece.movement + delta * Double(k) / Double(steps)
            if let reason = blockingReason(for: piece, at: value, against: others) {
                return Obstruction(stop: lastFree, reason: reason)
            }
            lastFree = value
        }
        return nil
    }

    /// A static piece prepared for repeated collision tests: its world primitives plus a circle
    /// around its pivot that contains all of them.
    private struct CollisionTarget {
        let id: Piece.ID
        let primitives: [WorldPrimitive]
        let center: Point
        let reach: Double
    }

    private func collisionTargets(excluding id: Piece.ID) -> [CollisionTarget] {
        pieces.compactMap { other in
            guard other.id != id else { return nil }
            return CollisionTarget(id: other.id, primitives: other.worldPrimitives(), center: other.translation, reach: other.collisionReach)
        }
    }

    /// A gripped ring holds its clips: a piece whose clip grips a ring cannot move at all, even when it
    /// pivots at that ring's center. Only the ring can turn, bringing its gap to the clip. Rings
    /// themselves spin freely under the clips holding them.
    func clipHoldViolation(for piece: Piece) -> BlockReason? {
        for connection in connections where connection.owner == piece.id && !connection.isHolder {
            return .heldByClip(connection)
        }
        return nil
    }

    /// Checks a single hypothetical rotation/offset of `piece` for geometry collisions with all other pieces.
    func blockingReason(for piece: Piece, at value: Double) -> BlockReason? {
        blockingReason(for: piece, at: value, against: collisionTargets(excluding: piece.id))
    }

    private func blockingReason(for piece: Piece, at value: Double, against others: [CollisionTarget]) -> BlockReason? {
        var moving = piece
        moving.movement = value

        // A sliding bar's bent arms cannot pass through its own hub.
        if moving.motion == .slide {
            for shape in moving.shapes {
                guard case .segment(let local) = shape, !Piece.isAxial(local) else { continue }
                let world = local.transformed(rotation: moving.rotation, translation: moving.translation)
                if Geometry.distance(from: moving.position, to: world) < GameRules.hubClearance { return .hub }
            }
        }

        let movingCenter = moving.translation
        let movingReach = moving.collisionReach
        var movingPrimitives: [WorldPrimitive]?
        for other in others {
            // Pieces whose reach circles do not come within a stroke of each other cannot collide.
            if other.center.distance(to: movingCenter) > movingReach + other.reach + GameRules.strokeThickness { continue }
            if movingPrimitives == nil { movingPrimitives = moving.worldPrimitives() }
            for a in movingPrimitives! {
                for b in other.primitives {
                    if isExcludedPair(a, of: moving, b, ofPiece: other.id, ringArcIndex: ringArcIndex(of: other.id)) { continue }
                    if Geometry.intersects(a.primitive, b.primitive) {
                        return .collision(with: other.id)
                    }
                }
            }
        }
        return nil
    }

    private func ringArcIndex(of id: Piece.ID) -> Int? {
        piece(id)?.ringArcIndex
    }

    /// A clip square is a sleeve: the arc of the ring it is aimed at passes through it freely, whether
    /// the clip currently grips (square on the arc) or has slipped off (square in the gap). So the pair
    /// is excluded whenever the clip targets that ring and its square sits on the ring's circle.
    private func isExcludedPair(_ a: WorldPrimitive, of pieceA: Piece, _ b: WorldPrimitive, ofPiece idB: Piece.ID, ringArcIndex arcIndexB: Int?) -> Bool {
        if case .clip(let clipIndex) = a.source, case .body(let bodyIndex) = b.source, bodyIndex == arcIndexB {
            return clipSitsOnRing(owner: pieceA, clipIndex: clipIndex, ringID: idB)
        }
        if case .clip(let clipIndex) = b.source, case .body(let bodyIndex) = a.source, bodyIndex == pieceA.ringArcIndex,
           let owner = piece(idB) {
            return clipSitsOnRing(owner: owner, clipIndex: clipIndex, ringID: pieceA.id)
        }
        return false
    }

    /// Whether the clip is aimed at `ringID` and its square lies on that ring's circle.
    private func clipSitsOnRing(owner: Piece, clipIndex: Int, ringID: Piece.ID) -> Bool {
        guard owner.clips[clipIndex].grips == ringID, let ring = piece(ringID), let arc = ring.worldRingArc() else { return false }
        let grip = owner.worldGripPoint(clipIndex: clipIndex)
        return abs(grip.distance(to: arc.center) - arc.radius) <= GameRules.clipHoldTolerance
    }

    // MARK: Connections

    /// Whether the arm of a sliding piece still runs through its hub.
    static func isInHolder(_ piece: Piece) -> Bool {
        guard let arm = piece.axialArm else { return false }
        let low = min(arm.from.x, arm.to.x) + piece.offset
        let high = max(arm.from.x, arm.to.x) + piece.offset
        let half = GameRules.holderLength / 2
        return high > -half && low < half
    }

    /// A clip connection is released when the grip point sits fully inside the ring's gap.
    /// A holder connection is released when the sliding piece has left the holder completely.
    func isReleased(_ connection: Connection) -> Bool {
        guard let owner = piece(connection.owner) else { return false }
        guard let clipIndex = connection.clipIndex else {
            return !Self.isInHolder(owner)
        }
        guard let ring = piece(connection.ring),
              let arc = ring.worldRingArc(),
              let gap = arc.gap else { return false }
        let grip = owner.worldGripPoint(clipIndex: clipIndex)
        let angle = (grip - arc.center).angle
        // The whole clip square must fit in the gap before it can slip off.
        let clipHalfAngle = asin(min(1, (GameRules.clipSize / 2) / arc.radius))
        return gap.contains(angle, margin: clipHalfAngle)
    }

    /// Whether a possible connection holds right now: a clip square sitting on its ring's arc (on the
    /// circle, outside the gap), or a sliding piece inside its holder.
    func isHolding(_ connection: Connection) -> Bool {
        guard let owner = piece(connection.owner) else { return false }
        guard let clipIndex = connection.clipIndex else {
            return Self.isInHolder(owner)
        }
        guard let ring = piece(connection.ring), let arc = ring.worldRingArc() else { return false }
        let grip = owner.worldGripPoint(clipIndex: clipIndex)
        guard abs(grip.distance(to: arc.center) - arc.radius) <= GameRules.clipHoldTolerance else { return false }
        return !isReleased(connection)
    }

    /// Re-evaluates the connections involving `id` (or all of them when `id` is `nil`) from the
    /// current geometry: released ones are dropped and any that hold again are restored, so a ring
    /// turned back under a clip is gripped again. Returns the connections that were released.
    @discardableResult
    mutating func refreshConnections(involving id: Piece.ID?) -> [Connection] {
        var broken: [Connection] = []
        for connection in connections where id == nil || connection.involves(id!) {
            if isReleased(connection) { broken.append(connection) }
        }
        connections.removeAll { broken.contains($0) }
        for candidate in Self.potentialConnections(of: pieces)
        where (id == nil || candidate.involves(id!)) && !connections.contains(candidate) && !broken.contains(candidate) && isHolding(candidate) {
            connections.append(candidate)
        }
        return broken
    }
}

extension Piece {
    /// Radius of a circle around the piece's origin that contains every body and clip primitive at
    /// any rotation. Used to skip collision tests between pieces that are far apart.
    var collisionReach: Double {
        var reach = 0.0
        for shape in shapes {
            let circle = shape.boundingCircle
            reach = max(reach, circle.center.length + circle.radius)
        }
        for clip in clips {
            for primitive in clip.primitives() {
                let circle = primitive.boundingCircle
                reach = max(reach, circle.center.length + circle.radius)
            }
        }
        return reach
    }
}
