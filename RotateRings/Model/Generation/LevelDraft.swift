//
//  LevelDraft.swift
//  RotateRings
//
//  A level under construction: pieces, clip wiring, gap planning, colouring, validation and the
//  conversion to a `LevelFile`.
//

import Foundation

struct LevelDraft {
    var name: String
    var template: String
    var pieces: [DraftPiece] = []

    init(name: String, template: String, pieces: [DraftPiece] = []) {
        self.name = name
        self.template = template
        self.pieces = pieces
    }

    func index(of id: String) -> Int? {
        pieces.firstIndex { $0.id == id }
    }

    subscript(id: String) -> DraftPiece? {
        index(of: id).map { pieces[$0] }
    }

    // MARK: Wiring

    /// Adds a clip from `ownerID` to the ring `targetID`. The stem leaves the owner at `bodyPoint`
    /// (world) and the grip lands exactly on the target's circle, so the level validator accepts it.
    /// Fails when the stem would be too short or too long.
    @discardableResult
    mutating func addClip(from ownerID: String, at bodyPoint: Point, to targetID: String) -> Bool {
        guard let owner = index(of: ownerID), let target = index(of: targetID),
              let radius = pieces[target].radius, !pieces[target].isClosedRing else { return false }
        let center = pieces[target].position
        let grip = center + (bodyPoint - center).normalized() * radius
        guard ForgeRules.stemRange.contains(grip.distance(to: bodyPoint)) else { return false }
        pieces[owner].clips.append(.init(stemStart: pieces[owner].toLocal(bodyPoint), stemEnd: pieces[owner].toLocal(grip), grips: targetID))
        return true
    }

    /// Adds a clip from ring `ownerID` to ring `targetID`, leaving the owner's circle at the point
    /// facing the target.
    @discardableResult
    mutating func addRingClip(from ownerID: String, to targetID: String) -> Bool {
        guard let owner = self[ownerID], let target = self[targetID], let radius = owner.radius else { return false }
        let bodyPoint = owner.position + (target.position - owner.position).normalized() * radius
        return addClip(from: ownerID, at: bodyPoint, to: targetID)
    }

    /// World angles (degrees, around the ring's centre) at which clips grip the ring.
    func contactAngles(on ringID: String) -> [Double] {
        guard let ring = self[ringID] else { return [] }
        var angles: [Double] = []
        for owner in pieces {
            for clip in owner.clips where clip.grips == ringID {
                let grip = owner.toWorld(clip.stemEnd)
                angles.append(normalizedDegrees(AngleMath.degrees(fromRadians: (grip - ring.position).angle)))
            }
        }
        return angles
    }

    /// Local angles at which the ring's own clip stems and tails leave its arc.
    func stemRootAngles(of ringID: String) -> [Double] {
        guard let ring = self[ringID] else { return [] }
        var angles: [Double] = ring.clips.map { normalizedDegrees(AngleMath.degrees(fromRadians: $0.stemStart.angle)) }
        for shape in ring.shapes {
            if case .segment(let segment) = shape {
                angles.append(normalizedDegrees(AngleMath.degrees(fromRadians: segment.from.angle)))
            }
        }
        return angles
    }

    // MARK: Gap planning

    /// Whether a gap centred at `center` keeps every contact gripped and every stem root on the arc.
    func gapIsValid(centerDegrees center: Double, gapDegrees gap: Double, for ringID: String) -> Bool {
        guard let ring = self[ringID], let radius = ring.radius else { return false }
        let contactLimit = gap / 2 + ForgeRules.contactClearanceDegrees(radius: radius)
        for contact in contactAngles(on: ringID) where degreeDifference(contact, center) < contactLimit { return false }
        let rootLimit = gap / 2 + ForgeRules.stemRootClearanceDegrees
        for root in stemRootAngles(of: ringID) where degreeDifference(root, center) < rootLimit { return false }
        return true
    }

    /// Turns the ring's gap so that the first clip gripping it is `lockSteps` grid steps away. Falls
    /// back to nearby step counts when that spot is taken. Returns the step count used, nil if none fits.
    @discardableResult
    mutating func planGap(for ringID: String, lockSteps: Int, gapDegrees gap: Double = ForgeRules.defaultGapDegrees) -> Int? {
        guard let index = index(of: ringID), let radius = pieces[index].radius, let primary = contactAngles(on: ringID).first else { return nil }
        var order = [lockSteps, -lockSteps]
        for magnitude in 1...4 { order += [magnitude, -magnitude] }
        var tried = Set<Int>()
        let oneStepAllowed = ForgeRules.supportsOneStepLock(radius: radius)
        for steps in order where steps != 0 && tried.insert(steps).inserted {
            if abs(steps) == 1 && !oneStepAllowed { continue }
            let center = normalizedDegrees(primary + Double(steps) * ForgeRules.gridDegrees)
            // One step away the clip only fits beside a narrower gap.
            let width = abs(steps) == 1 ? min(gap, ForgeRules.narrowGapDegrees(radius: radius)) : gap
            if gapIsValid(centerDegrees: center, gapDegrees: width, for: ringID) {
                pieces[index].setGap(centerDegrees: center, degrees: width)
                return steps
            }
        }
        return nil
    }

    /// Gap for a ring gripped by several clips: the wide gap, every contact at least two steps away
    /// (so a clip whose owner stays behind can swing out through the gap), the largest step count as
    /// small as possible. Returns that largest step count, nil if nothing fits.
    @discardableResult
    mutating func planSharedGap(for ringID: String, rng: inout SplitMix64) -> Int? {
        guard let index = index(of: ringID) else { return nil }
        let contacts = contactAngles(on: ringID)
        guard contacts.count >= 2 else { return planGap(for: ringID, lockSteps: rng.lockSteps(in: 1...2)) }
        let gap = sharedGapRequirement(for: ringID)
        var best: [(center: Double, worst: Int)] = []
        for center in stride(from: 0.0, to: 360, by: ForgeRules.gridDegrees) where gapIsValid(centerDegrees: center, gapDegrees: gap, for: ringID) {
            let steps = contacts.map { Int((degreeDifference($0, center) / ForgeRules.gridDegrees).rounded()) }
            guard let least = steps.min(), least >= 2, let worst = steps.max() else { continue }
            if let current = best.first?.worst, worst > current { continue }
            if let current = best.first?.worst, worst < current { best.removeAll() }
            best.append((center, worst))
        }
        guard !best.isEmpty else { return nil }
        let choice = best[Int(rng.next() % UInt64(best.count))]
        pieces[index].setGap(centerDegrees: choice.center, degrees: gap)
        return choice.worst
    }

    /// Gap a ring with several owners needs so that, once its gap sits at one owner's contact, that
    /// owner can turn one step either way and swing its loose clip out without touching the arc ends.
    /// Simulated degree by degree from the actual geometry; rounded up to a multiple of 5. Two
    /// contacts up to a quarter turn apart are released together, with the gap over both; the gap
    /// then also leaves `sharedReleaseWindowDegrees` of play around the pair.
    func sharedGapRequirement(for ringID: String) -> Double {
        guard let ring = self[ringID], let radius = ring.radius else { return ForgeRules.sharedGapDegrees }
        let band = GameRules.strokeThickness + GameRules.clipSize / 2
        var halfGap = ForgeRules.sharedGapDegrees / 2
        let contacts = contactAngles(on: ringID)
        for (index, first) in contacts.enumerated() {
            for second in contacts[(index + 1)...] where degreeDifference(first, second) <= 90 {
                let span = degreeDifference(first, second) + 2 * ForgeRules.clipHalfAngleDegrees(radius: radius)
                halfGap = max(halfGap, (span + ForgeRules.sharedReleaseWindowDegrees) / 2)
            }
        }
        for owner in pieces {
            for clip in owner.clips where clip.grips == ringID {
                let contact = normalizedDegrees(AngleMath.degrees(fromRadians: (owner.toWorld(clip.stemEnd) - ring.position).angle))
                for direction in [1.0, -1.0] {
                    for step in 1...Int(ForgeRules.gridDegrees) {
                        let turn = AngleMath.radians(fromDegrees: owner.rotationDegrees + direction * Double(step))
                        let clipCenter = clip.stemEnd.rotated(by: turn) + owner.position
                        let relative = clipCenter - ring.position
                        let distance = relative.length
                        guard abs(distance - radius) < band else { continue }
                        let angle = normalizedDegrees(AngleMath.degrees(fromRadians: relative.angle))
                        // The clip square's half size plus a stroke width, as an angle at this distance.
                        let clearance = AngleMath.degrees(fromRadians: asin(min(1, (GameRules.clipSize / 2 + GameRules.strokeThickness) / max(distance, 1))))
                        halfGap = max(halfGap, degreeDifference(angle, contact) + clearance + 2)
                    }
                }
            }
        }
        return min(150, (2 * halfGap / 5).rounded(.up) * 5)
    }

    /// Turns a ring that grips others (but is gripped by nothing) so its gap stays clear of its own
    /// stems. Picks randomly among the grid positions that fit.
    @discardableResult
    mutating func planFreeGap(for ringID: String, gapDegrees gap: Double = ForgeRules.defaultGapDegrees, rng: inout SplitMix64) -> Bool {
        guard let index = index(of: ringID) else { return false }
        let options = stride(from: 0.0, to: 360, by: ForgeRules.gridDegrees).filter { gapIsValid(centerDegrees: $0, gapDegrees: gap, for: ringID) }
        guard !options.isEmpty else { return false }
        pieces[index].setGap(centerDegrees: options[Int(rng.next() % UInt64(options.count))], degrees: gap)
        return true
    }

    // MARK: Finishing

    /// Gives pieces ids by kind (`r1`, `o1`, `t1`, `b1`, `l1`, `s1`) in board order and updates clips.
    mutating func renumberIDs() {
        var counters: [PieceKind: Int] = [:]
        var mapping: [String: String] = [:]
        for piece in pieces {
            let count = (counters[piece.kind] ?? 0) + 1
            counters[piece.kind] = count
            let prefix: String
            switch piece.kind {
            case .cRing: prefix = "r"
            case .closedRing: prefix = "o"
            case .tailRing: prefix = "t"
            case .latchBar: prefix = "b"
            case .lBar: prefix = "l"
            case .slideBar: prefix = "s"
            }
            mapping[piece.id] = "\(prefix)\(count)"
        }
        for index in pieces.indices {
            pieces[index].id = mapping[pieces[index].id] ?? pieces[index].id
            pieces[index].clips = pieces[index].clips.map { clip in
                var clip = clip
                clip.grips = clip.grips.flatMap { mapping[$0] }
                return clip
            }
        }
    }

    /// Colours pieces so that no piece shares a colour with a piece it touches: clip partners,
    /// concentric rings and close neighbours.
    mutating func assignColors(rng: inout SplitMix64) {
        var neighbors = [Set<Int>](repeating: [], count: pieces.count)
        for (i, piece) in pieces.enumerated() {
            for clip in piece.clips {
                if let target = clip.grips, let j = index(of: target) {
                    neighbors[i].insert(j)
                    neighbors[j].insert(i)
                }
            }
            for (j, other) in pieces.enumerated() where j > i {
                let reach = (piece.radius ?? 60) + (other.radius ?? 60) + 40
                if piece.position.distance(to: other.position) < reach {
                    neighbors[i].insert(j)
                    neighbors[j].insert(i)
                }
            }
        }
        var palette = ForgeRules.colors
        palette.shuffle(using: &rng)
        var assigned = [String?](repeating: nil, count: pieces.count)
        for i in pieces.indices {
            let used = Set(neighbors[i].compactMap { assigned[$0] })
            let color = palette.first { !used.contains($0) } ?? palette[i % palette.count]
            assigned[i] = color
            pieces[i].color = color
            palette.append(palette.removeFirst())
        }
    }

    func levelFile(number: Int) -> LevelFile {
        LevelFile(id: number, name: name, board: .init(width: ForgeRules.boardWidth, height: ForgeRules.boardHeight), pieces: pieces.map(\.spec))
    }

    // MARK: Validation

    enum DraftError: Error, CustomStringConvertible {
        case level(LevelError)
        case decoding(Error)
        case pieceRemovedOnLoad(String)
        case startingCollision(String, Board.BlockReason)
        case outOfBounds(String)
        case gapTooNarrow(String)
        case gripsClosedRing(String)

        var description: String {
            switch self {
            case .level(let error): return error.localizedDescription
            case .decoding(let error): return "\(error)"
            case .pieceRemovedOnLoad(let id): return "\(id) has no connection at the start"
            case .startingCollision(let id, let reason): return "\(id) starts in a collision: \(reason)"
            case .outOfBounds(let id): return "\(id) leaves the board"
            case .gapTooNarrow(let id): return "\(id) has a gap too narrow for the move grid"
            case .gripsClosedRing(let id): return "\(id) grips a closed ring"
            }
        }
    }

    /// Checks everything the generator requires before solving and returns the start board.
    func validate(number: Int = 0) throws -> Board {
        let file = levelFile(number: number)
        let board: Board
        do {
            board = try file.makeBoard()
        } catch let error as LevelError {
            throw DraftError.level(error)
        }
        // Nothing may leave on load: every piece is either connected or held by contact.
        var probe = board
        if let dropped = probe.removeUnconnectedPieces().first {
            throw DraftError.pieceRemovedOnLoad(dropped)
        }
        for piece in board.pieces {
            if let reason = board.blockingReason(for: piece, at: piece.movement) {
                throw DraftError.startingCollision(piece.id, reason)
            }
            let minX = ForgeRules.margin, maxX = ForgeRules.boardWidth - ForgeRules.margin
            let minY = ForgeRules.margin, maxY = ForgeRules.boardHeight - ForgeRules.margin
            let pad = GameRules.strokeThickness / 2
            func inside(_ point: Point, _ reach: Double) -> Bool {
                point.x - reach >= minX && point.x + reach <= maxX && point.y - reach >= minY && point.y + reach <= maxY
            }
            for primitive in piece.worldPrimitives() {
                let ok: Bool
                switch primitive.primitive {
                case .arc(let arc): ok = inside(arc.center, arc.radius + pad)
                case .segment(let segment): ok = inside(segment.from, pad) && inside(segment.to, pad)
                }
                if !ok { throw DraftError.outOfBounds(piece.id) }
            }
        }
        for piece in pieces {
            if let gap = piece.gapDegrees, let radius = piece.radius, gap < ForgeRules.minGapDegrees(radius: radius) {
                throw DraftError.gapTooNarrow(piece.id)
            }
            for clip in piece.clips {
                if let target = clip.grips, self[target]?.isClosedRing == true {
                    throw DraftError.gripsClosedRing(piece.id)
                }
            }
        }
        return board
    }
}
