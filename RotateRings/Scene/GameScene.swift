//
//  GameScene.swift
//  RotateRings
//
//  Renders a `Board`, turns finger drags into model moves and animates the results.
//  All rules live in the model; the scene only shows what the model decided.
//
//  Interaction: touch a piece and move the finger. Turning pieces follow the finger's angle around
//  their pivot, sliding bars follow the finger along their hub axis. Pieces stop dead at obstructions
//  and stay exactly where they are released. A bar dragged fully out of its hub is free: it flies on
//  along the axis and the hub fades away.
//
//  The scene fills the whole screen so that pieces leaving the board are not cut off at the board's
//  edge. Scene coordinates are board coordinates; the camera scales and places the board inside
//  `boardFrame`, the part of the view the host keeps free of other controls.
//

import SpriteKit
import UIKit

/// A full-screen colour flash: fade to `peakOpacity` over `attack`, hold, then fade out over `release`.
struct ScreenFlash {
    let color: UIColor
    let peakOpacity: Double
    let attack: TimeInterval
    let hold: TimeInterval
    let release: TimeInterval
}

@MainActor
final class GameScene: SKScene {

    private enum Timing {
        static let flyOff: TimeInterval = 0.7
        static let initialRemovalDelay: TimeInterval = 0.4
    }

    /// The finger currently moving a piece.
    private struct DragState {
        let touch: UITouch
        let pieceID: Piece.ID
        let node: PieceNode
        let motion: Piece.Motion
        /// Pivot of a turning piece, or holder of a sliding piece.
        let pivot: Point
        /// World direction a sliding piece moves along.
        let slideAxis: Point
        /// Angle of the finger around the pivot at the previous move, if it was outside the dead zone.
        var lastFingerAngle: Double?
        /// Where the finger was at the previous move.
        var lastFingerPoint: Point
        /// True while the piece is pressed against an obstruction, so the bump feedback fires only once.
        var isPressingObstruction = false
    }

    private(set) var board: Board
    private var pieceNodes: [Piece.ID: PieceNode] = [:]
    private var drag: DragState?
    /// True while pieces are snapping or flying off; new drags wait until it is over.
    private(set) var isBusy = false

    /// Called once every piece has left the board.
    var onLevelComplete: (() -> Void)?
    /// Called when the armed laser has been fired at a piece.
    var onLaserConsumed: (() -> Void)?
    /// Asks the host to flash the whole screen. The scene itself only covers the board, so effects that
    /// should reach the screen edges (lightning dim and strike) go through here.
    var onScreenFlash: ((ScreenFlash) -> Void)?
    /// Called once, when the scene has finished its first frame. The host keeps the view hidden until
    /// then, because the Metal layer shows a blank grey block before anything has been drawn.
    var onFirstFrame: (() -> Void)?
    private var hasFinishedFirstFrame = false

    /// While the laser is armed, the next touch on a piece vaporises it instead of moving it.
    var isLaserArmed = false

    private let bumpHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationHaptic = UINotificationFeedbackGenerator()

    /// Size of the board in board units.
    let boardSize: CGSize
    /// Where the board goes, in the view's coordinates (points, y down). Nil fits it to the whole view.
    var boardFrame: CGRect? {
        didSet { layoutCamera() }
    }

    /// Camera showing the board inside `boardFrame`; besides layout, only screen-shake effects move it.
    private let cameraNode = SKCameraNode()
    /// Where the camera rests when nothing shakes it.
    private var cameraRest: CGPoint
    private var boardCenter: CGPoint { CGPoint(x: boardSize.width / 2, y: boardSize.height / 2) }

    /// The part of the board's coordinate space that is on screen: the board plus everything around it.
    var visibleRect: CGRect {
        let width = size.width * cameraNode.xScale
        let height = size.height * cameraNode.yScale
        return CGRect(x: cameraRest.x - width / 2, y: cameraRest.y - height / 2, width: width, height: height)
    }

    /// `size` is the board's size in board units; the scene itself resizes to its view.
    init(board: Board, size: CGSize) {
        self.board = board
        boardSize = size
        cameraRest = CGPoint(x: size.width / 2, y: size.height / 2)
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("GameScene does not support NSCoding")
    }

    // MARK: Haptics

    /// Fires an impact only when haptics are enabled in settings.
    private func impact(_ generator: UIImpactFeedbackGenerator, intensity: CGFloat) {
        guard GameSettings.shared.isHapticsEnabled else { return }
        generator.impactOccurred(intensity: intensity)
    }

    /// Fires a notification haptic only when haptics are enabled in settings.
    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard GameSettings.shared.isHapticsEnabled else { return }
        notificationHaptic.notificationOccurred(type)
    }

    override func didFinishUpdate() {
        guard !hasFinishedFirstFrame else { return }
        hasFinishedFirstFrame = true
        onFirstFrame?()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutCamera()
    }

    /// Scales and places the camera so the board fits `boardFrame`, keeping its proportions.
    private func layoutCamera() {
        guard size.width > 0, size.height > 0 else { return }
        let frame = boardFrame.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil } ?? CGRect(origin: .zero, size: size)
        // Board units per point.
        let scale = max(boardSize.width / frame.width, boardSize.height / frame.height)
        cameraNode.setScale(scale)
        // The camera looks at the middle of the view; shift it so the board's middle lands on the
        // middle of the frame. The view's y axis points down, the scene's up.
        let offsetX = frame.midX - size.width / 2
        let offsetY = frame.midY - size.height / 2
        cameraRest = CGPoint(x: boardCenter.x - offsetX * scale, y: boardCenter.y + offsetY * scale)
        cameraNode.removeAllActions()
        cameraNode.position = cameraRest
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        addChild(cameraNode)
        camera = cameraNode
        layoutCamera()
        for piece in board.pieces {
            let node = PieceNode(piece: piece)
            pieceNodes[piece.id] = node
            addChild(node)
        }
        bumpHaptic.prepare()

        // Pieces that start without any connection are not part of the puzzle and leave right away.
        let free = board.removeUnconnectedPieces()
        if !free.isEmpty {
            isBusy = true
            flyOff(free, delay: Timing.initialRemovalDelay) { [weak self] in
                self?.isBusy = false
                self?.checkCompletion()
            }
        }
    }

    // MARK: Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isBusy, drag == nil, let touch = touches.first else { return }
        let location = point(of: touch)
        guard let id = pieceID(at: location),
              let node = pieceNodes[id],
              let piece = board.piece(id) else { return }
        if isLaserArmed {
            isLaserArmed = false
            destroyPiece(id, using: .laser)
            onLaserConsumed?()
            return
        }
        drag = DragState(
            touch: touch,
            pieceID: id,
            node: node,
            motion: piece.motion,
            pivot: piece.position,
            slideAxis: piece.slideAxis,
            lastFingerAngle: fingerAngle(at: location, around: piece.position),
            lastFingerPoint: location
        )
        bumpHaptic.prepare()
        SoundPlayer.shared.play(.grab)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var state = drag, touches.contains(state.touch) else { return }
        defer { drag = state }

        let location = point(of: state.touch)
        let delta: Double
        switch state.motion {
        case .rotation:
            guard let angle = fingerAngle(at: location, around: state.pivot) else { return }
            guard let previous = state.lastFingerAngle else {
                state.lastFingerAngle = angle
                return
            }
            state.lastFingerAngle = angle
            delta = AngleMath.shortestDelta(from: previous, to: angle)
        case .slide:
            // Only the finger movement along the hub axis counts.
            delta = (location - state.lastFingerPoint).dot(state.slideAxis)
        }
        state.lastFingerPoint = location

        guard let result = board.drag(state.pieceID, by: delta) else { return }
        state.node.apply(movement: result.value)

        if result.blockedBy != nil {
            if !state.isPressingObstruction {
                impact(bumpHaptic, intensity: 0.9)
                SoundPlayer.shared.play(.bump)
                state.node.shake()
            }
            state.isPressingObstruction = true
        } else {
            state.isPressingObstruction = false
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = drag, touches.contains(state.touch) else { return }
        endDrag(state)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = drag, touches.contains(state.touch) else { return }
        endDrag(state)
    }

    private func point(of touch: UITouch) -> Point {
        let location = touch.location(in: self)
        return Point(location.x, location.y)
    }

    /// Angle of the finger around the pivot, or `nil` when it is too close to the pivot to be meaningful.
    private func fingerAngle(at location: Point, around pivot: Point) -> Double? {
        let v = location - pivot
        guard v.length >= GameRules.dragDeadZone else { return nil }
        return v.angle
    }

    /// Picks the piece whose stroke is closest to the point, within `GameRules.tapPickRadius`.
    func pieceID(at point: Point) -> Piece.ID? {
        var best: (id: Piece.ID, distance: Double)?
        for piece in board.pieces {
            let distance = piece.distance(to: point)
            guard distance <= GameRules.tapPickRadius else { continue }
            if best == nil || distance < best!.distance {
                best = (piece.id, distance)
            }
        }
        return best?.id
    }

    // MARK: Settling

    /// Lets go of the piece: it stays where the finger left it, then the model's decision is shown.
    private func endDrag(_ state: DragState) {
        drag = nil
        // Cancel any leftover wobble so the node matches the model exactly.
        state.node.stopShake()
        // A bar dragged out of its hub keeps going the way it was pulled.
        let pulled = board.piece(state.pieceID).map { $0.offset >= 0 ? 1.0 : -1.0 } ?? 1
        guard let result = board.settle(state.pieceID) else { return }
        state.node.apply(movement: result.value)
        isBusy = true
        var directions: [Piece.ID: Point] = [:]
        if state.motion == .slide, result.removedPieceIDs.contains(state.pieceID) {
            directions[state.pieceID] = state.slideAxis * pulled
        }
        finishMove(removing: result.removedPieceIDs, directions: directions)
    }

    // MARK: Boosters

    /// Lightning: strikes a random piece. Does nothing, and returns false, while an animation runs or
    /// the board is empty.
    @discardableResult
    func destroyRandomPiece() -> Bool {
        guard !isBusy, drag == nil, let target = board.pieces.randomElement() else { return false }
        destroyPiece(target.id, using: .lightning)
        return true
    }

    /// Removes a piece outright with the booster's animation, then lets whatever it was holding fly off.
    func destroyPiece(_ id: Piece.ID, using booster: Booster) {
        guard !isBusy, let result = board.destroy(id), let node = pieceNodes.removeValue(forKey: id) else { return }
        isBusy = true
        heavyHaptic.prepare()
        node.zPosition = 11

        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            self.flyOff(result.freedPieceIDs, delay: 0) { [weak self] in
                self?.isBusy = false
                self?.checkCompletion()
            }
        }

        switch booster {
        case .lightning: playLightning(on: node, completion: finish)
        case .laser: playLaser(on: node, completion: finish)
        }
    }

    /// A bolt cracks down from the sky into the piece, which bursts.
    private func playLightning(on target: PieceNode, completion: @escaping () -> Void) {
        let impactPoint = target.calculateAccumulatedFrame().center
        // A beat of anticipation: the whole screen darkens before the strike.
        onScreenFlash?(ScreenFlash(color: Palette.backgroundBottom, peakOpacity: 0.55, attack: 0.18, hold: 0.1, release: 0.25))
        impact(bumpHaptic, intensity: 0.4)

        run(.wait(forDuration: 0.22)) { [weak self] in
            guard let self else { return }
            self.impact(self.heavyHaptic, intensity: 1.0)
            SoundPlayer.shared.play(.lightningStrike)
            // The strike lights up the whole screen for an instant.
            self.onScreenFlash?(ScreenFlash(color: .white, peakOpacity: 0.3, attack: 0.04, hold: 0, release: 0.3))
            PowerUpEffects.addLightningStrike(to: impactPoint, fromHeight: self.visibleRect.maxY, in: self)
            self.cameraNode.run(PowerUpEffects.shakeAction(around: self.cameraRest, amplitude: 8, duration: 0.4))
            target.run(.sequence([.wait(forDuration: 0.06), .run {
                PowerUpEffects.addShards(for: target, color: target.color, count: 14, to: self)
            }, PowerUpEffects.burstAction()]))
            self.run(.wait(forDuration: 0.55)) { completion() }
        }
    }

    /// A reticle locks onto the piece, then a beam from the bottom of the screen vaporises it.
    private func playLaser(on target: PieceNode, completion: @escaping () -> Void) {
        let impactPoint = target.calculateAccumulatedFrame().center
        let lockDuration: TimeInterval = 0.3
        let reticle = PowerUpEffects.addLockOnReticle(at: impactPoint, duration: lockDuration, in: self)
        impact(bumpHaptic, intensity: 0.5)
        SoundPlayer.shared.play(.laserLock)

        run(.wait(forDuration: lockDuration)) { [weak self] in
            guard let self else { return }
            reticle.run(.sequence([.group([.scale(to: 0.7, duration: 0.1), .fadeOut(withDuration: 0.1)]), .removeFromParent()]))
            self.impact(self.heavyHaptic, intensity: 1.0)
            SoundPlayer.shared.play(.laserFire)
            let muzzle = CGPoint(x: self.boardCenter.x, y: self.visibleRect.minY - 30)
            PowerUpEffects.addLaserBeam(from: muzzle, to: impactPoint, in: self)
            self.cameraNode.run(PowerUpEffects.shakeAction(around: self.cameraRest, amplitude: 5, duration: 0.3))
            target.run(.sequence([.wait(forDuration: 0.1), .run {
                PowerUpEffects.addShards(for: target, color: target.color, count: 12, to: self)
            }, PowerUpEffects.vaporizeAction()]))
            self.run(.wait(forDuration: 0.6)) { completion() }
        }
    }

    private func finishMove(removing removed: [Piece.ID], directions: [Piece.ID: Point] = [:]) {
        guard !removed.isEmpty else {
            SoundPlayer.shared.play(.settle)
            isBusy = false
            return
        }
        notify(.success)
        // The fly-off sound is played by `flyOff` itself.
        flyOff(removed, delay: 0, directions: directions) { [weak self] in
            self?.isBusy = false
            self?.checkCompletion()
        }
    }

    private func checkCompletion() {
        if board.isComplete {
            SoundPlayer.shared.play(.levelComplete)
            onLevelComplete?()
        }
    }

    // MARK: Animations

    /// Sends the given pieces flying off the screen, then calls `completion`. Pieces fly away from the
    /// board's center, except those given an explicit direction (a bar that slid out of its hub keeps
    /// going along its axis, without spinning).
    private func flyOff(_ ids: [Piece.ID], delay: TimeInterval, directions: [Piece.ID: Point] = [:], completion: @escaping () -> Void) {
        let center = Point(boardCenter.x, boardCenter.y)
        // Far enough to leave the screen from anywhere on the board, whatever the direction.
        let screen = visibleRect
        let distance = max(screen.width, screen.height) * 1.2
        var nodes: [PieceNode] = []
        for id in ids {
            if let node = pieceNodes.removeValue(forKey: id) {
                nodes.append(node)
            }
        }
        var remaining = nodes.count
        guard remaining > 0 else {
            completion()
            return
        }

        // One sound for the whole group, timed with the start of the movement.
        run(.sequence([.wait(forDuration: delay), .run { SoundPlayer.shared.play(.flyOff) }]))

        for node in nodes {
            let origin = Point(node.position.x, node.position.y)
            let given = directions[node.pieceID]
            let direction = given ?? (origin - center).normalized(fallback: Point(0, 1))
            let move = SKAction.move(by: CGVector(dx: direction.x * distance, dy: direction.y * distance), duration: Timing.flyOff)
            // A pushed bar is already moving, so it keeps its speed instead of easing in.
            move.timingMode = given == nil ? .easeIn : .linear
            let spin = SKAction.rotate(byAngle: given == nil ? (direction.x >= 0 ? -.pi : .pi) : 0, duration: Timing.flyOff)
            let fade = SKAction.fadeOut(withDuration: Timing.flyOff)
            let lift = SKAction.sequence([.scale(to: 1.12, duration: 0.12), .scale(to: 0.9, duration: Timing.flyOff - 0.12)])
            node.zPosition = 10
            if given != nil {
                // The hub is bolted to the board; only the bar flies.
                node.dropHub(fadeDuration: Timing.flyOff * 0.6)
            }
            node.run(.sequence([.wait(forDuration: delay), .group([move, spin, fade, lift]), .removeFromParent()])) {
                remaining -= 1
                if remaining == 0 { completion() }
            }
        }
    }
}
