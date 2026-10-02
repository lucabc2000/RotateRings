//
//  PowerUpEffects.swift
//  RotateRings
//
//  Procedural visuals for the boosters: a lightning strike and a lock-on laser, plus the shared
//  debris, flashes and camera shake. Everything is drawn with shape nodes and code-configured
//  emitters; no image assets involved.
//

import SpriteKit
import UIKit

@MainActor
enum PowerUpEffects {

    // MARK: Particle texture

    /// A soft round dot used by every emitter. Drawn once with Core Graphics.
    static let particleTexture: SKTexture = {
        let size = CGSize(width: 24, height: 24)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width / 2, options: [])
        }
        return SKTexture(image: image)
    }()

    private static let electricBlue = Palette.pieceColor(named: "sky")
    private static let laserPurple = Palette.pieceColor(named: "purple")

    // MARK: Lightning

    /// A bolt cracks down from above `height` (the top of the screen) into `point`: glowing jagged
    /// core with a side fork and a shower of electric sparks.
    static func addLightningStrike(to point: CGPoint, fromHeight height: CGFloat, in scene: SKScene) {
        let start = CGPoint(x: point.x + CGFloat.random(in: -60...60), y: height + 40)
        let mainPath = boltPath(from: start, to: point, segments: 9, jitter: 26)

        // Side fork leaving the bolt about a third of the way down.
        let forkOrigin = CGPoint(x: start.x + (point.x - start.x) * 0.35 + CGFloat.random(in: -15...15),
                                 y: start.y + (point.y - start.y) * 0.35)
        let forkEnd = CGPoint(x: forkOrigin.x + CGFloat.random(in: 40...90) * (Bool.random() ? 1 : -1),
                              y: forkOrigin.y - CGFloat.random(in: 60...120))
        let forkPath = boltPath(from: forkOrigin, to: forkEnd, segments: 4, jitter: 14)

        let bolt = SKNode()
        bolt.zPosition = 29
        for (path, width, alpha, color) in [
            (mainPath, 16.0, 0.35, electricBlue),
            (mainPath, 7.0, 0.8, electricBlue),
            (mainPath, 3.0, 1.0, UIColor.white),
            (forkPath, 8.0, 0.3, electricBlue),
            (forkPath, 2.0, 0.9, UIColor.white),
        ] {
            let stroke = SKShapeNode(path: path)
            stroke.strokeColor = color
            stroke.lineWidth = width
            stroke.alpha = alpha
            stroke.lineCap = .round
            stroke.lineJoin = .round
            stroke.blendMode = .add
            stroke.isAntialiased = true
            bolt.addChild(stroke)
        }
        scene.addChild(bolt)

        // The bolt flickers a few times, then is gone.
        bolt.run(.sequence([
            .fadeAlpha(to: 0.25, duration: 0.04),
            .fadeAlpha(to: 1.0, duration: 0.03),
            .fadeAlpha(to: 0.4, duration: 0.05),
            .fadeAlpha(to: 1.0, duration: 0.03),
            .wait(forDuration: 0.06),
            .fadeOut(withDuration: 0.18),
            .removeFromParent(),
        ]))

        // Impact glow and sparks. (The whole-screen flash is drawn by the host view, see GameScene.)
        addImpactGlow(at: point, color: electricBlue, radius: 30, in: scene)
        addSparks(at: point, color: electricBlue, count: 60, speed: 190, in: scene)
    }

    /// A jagged polyline from `start` to `end`, displaced sideways at each joint.
    private static func boltPath(from start: CGPoint, to end: CGPoint, segments: Int, jitter: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let normal = CGPoint(x: -dy / length, y: dx / length)
        for i in 1..<segments {
            let t = CGFloat(i) / CGFloat(segments)
            let offset = CGFloat.random(in: -jitter...jitter)
            path.addLine(to: CGPoint(x: start.x + dx * t + normal.x * offset, y: start.y + dy * t + normal.y * offset))
        }
        path.addLine(to: end)
        return path
    }

    // MARK: Laser

    /// A targeting reticle that closes in on `point` over `duration`. The caller removes it.
    @discardableResult
    static func addLockOnReticle(at point: CGPoint, duration: TimeInterval, in scene: SKScene) -> SKNode {
        let reticle = SKNode()
        reticle.position = point
        reticle.zPosition = 30

        let ring = SKShapeNode(circleOfRadius: 26)
        ring.strokeColor = laserPurple
        ring.lineWidth = 3
        ring.fillColor = .clear
        reticle.addChild(ring)

        let ticks = CGMutablePath()
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            ticks.move(to: CGPoint(x: cos(angle) * 20, y: sin(angle) * 20))
            ticks.addLine(to: CGPoint(x: cos(angle) * 36, y: sin(angle) * 36))
        }
        let tickNode = SKShapeNode(path: ticks)
        tickNode.strokeColor = .white
        tickNode.lineWidth = 3
        tickNode.lineCap = .round
        reticle.addChild(tickNode)

        let dot = SKShapeNode(circleOfRadius: 3.5)
        dot.fillColor = .white
        dot.strokeColor = .clear
        reticle.addChild(dot)

        reticle.setScale(2.6)
        reticle.alpha = 0.15
        let lock = SKAction.group([
            .scale(to: 1, duration: duration),
            .fadeIn(withDuration: duration * 0.6),
            .rotate(byAngle: -.pi / 2, duration: duration),
        ])
        lock.timingMode = .easeOut
        reticle.run(lock)
        scene.addChild(reticle)
        return reticle
    }

    /// Fires a beam from `start` to `point`: a wide glow with a white core, a muzzle bloom, an impact
    /// glow and a spray of hot particles.
    static func addLaserBeam(from start: CGPoint, to point: CGPoint, in scene: SKScene) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: point)

        let beam = SKNode()
        beam.zPosition = 28
        for (width, alpha, color) in [(22.0, 0.25, laserPurple), (10.0, 0.7, laserPurple), (4.0, 1.0, UIColor.white)] {
            let stroke = SKShapeNode(path: path)
            stroke.strokeColor = color
            stroke.lineWidth = width
            stroke.alpha = alpha
            stroke.lineCap = .round
            stroke.blendMode = .add
            beam.addChild(stroke)
        }
        beam.alpha = 0
        scene.addChild(beam)
        beam.run(.sequence([
            .fadeIn(withDuration: 0.04),
            .wait(forDuration: 0.16),
            .fadeOut(withDuration: 0.16),
            .removeFromParent(),
        ]))

        addImpactGlow(at: start, color: laserPurple, radius: 14, in: scene)
        addImpactGlow(at: point, color: laserPurple, radius: 24, in: scene)
        addSparks(at: point, color: laserPurple, count: 50, speed: 150, in: scene)
    }

    // MARK: Shared pieces

    /// A bright disc that swells and fades.
    private static func addImpactGlow(at point: CGPoint, color: UIColor, radius: CGFloat, in scene: SKScene) {
        let glow = SKShapeNode(circleOfRadius: radius)
        glow.position = point
        glow.fillColor = color
        glow.strokeColor = .clear
        glow.blendMode = .add
        glow.alpha = 0.9
        glow.zPosition = 27
        glow.setScale(0.4)
        scene.addChild(glow)
        glow.run(.sequence([.group([.scale(to: 2.6, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))

        let core = SKShapeNode(circleOfRadius: radius * 0.6)
        core.position = point
        core.fillColor = .white
        core.strokeColor = .clear
        core.blendMode = .add
        core.zPosition = 31
        scene.addChild(core)
        core.run(.sequence([.group([.scale(to: 1.8, duration: 0.15), .fadeOut(withDuration: 0.15)]), .removeFromParent()]))
    }

    /// A one-shot burst of glowing particles fading from white to `color`.
    private static func addSparks(at point: CGPoint, color: UIColor, count: Int, speed: CGFloat, in scene: SKScene) {
        let sparks = SKEmitterNode()
        sparks.particleTexture = particleTexture
        sparks.position = point
        sparks.numParticlesToEmit = count
        sparks.particleBirthRate = CGFloat(count) * 12
        sparks.particleLifetime = 0.5
        sparks.particleLifetimeRange = 0.3
        sparks.emissionAngleRange = .pi * 2
        sparks.particleSpeed = speed
        sparks.particleSpeedRange = speed * 0.6
        sparks.yAcceleration = -120
        sparks.particleScale = 0.7
        sparks.particleScaleRange = 0.35
        sparks.particleScaleSpeed = -0.9
        sparks.particleAlphaSpeed = -1.6
        sparks.particleColorBlendFactor = 1
        sparks.particleColorSequence = SKKeyframeSequence(keyframeValues: [UIColor.white, color, color.withAlphaComponent(0)], times: [0, 0.35, 1])
        sparks.particleBlendMode = .add
        sparks.zPosition = 28
        scene.addChild(sparks)
        sparks.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
    }

    /// Scatters shards in the piece's colour from the piece's footprint.
    static func addShards(for node: SKNode, color: UIColor, count: Int, to scene: SKScene) {
        let frame = node.calculateAccumulatedFrame()
        let radius = max(12, min(frame.width, frame.height) / 2)
        for _ in 0..<count {
            let shard = SKShapeNode(rectOf: CGSize(width: CGFloat.random(in: 7...14), height: CGFloat.random(in: 5...9)), cornerRadius: 2.5)
            shard.fillColor = color
            shard.strokeColor = .clear
            shard.zPosition = 26
            let spawnAngle = CGFloat.random(in: 0...(2 * .pi))
            let spawnRadius = CGFloat.random(in: 0...radius)
            shard.position = CGPoint(x: frame.midX + cos(spawnAngle) * spawnRadius, y: frame.midY + sin(spawnAngle) * spawnRadius)
            shard.zRotation = CGFloat.random(in: 0...(2 * .pi))
            scene.addChild(shard)

            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 50...130)
            let outward = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.28)
            outward.timingMode = .easeOut
            let fall = SKAction.moveBy(x: 0, y: -CGFloat.random(in: 40...90), duration: 0.4)
            fall.timingMode = .easeIn
            let spin = SKAction.rotate(byAngle: CGFloat.random(in: -4...4), duration: 0.68)
            shard.run(.sequence([
                .group([.sequence([outward, fall]), spin, .sequence([.wait(forDuration: 0.3), .fadeOut(withDuration: 0.38)])]),
                .removeFromParent(),
            ]))
        }
    }

    /// A struck piece: a quick swell, then it shrinks away.
    static func burstAction() -> SKAction {
        let action = SKAction.sequence([
            .group([.scale(to: 1.2, duration: 0.07), .fadeAlpha(to: 0.9, duration: 0.07)]),
            .group([.scale(to: 0.05, duration: 0.2), .fadeOut(withDuration: 0.2), .rotate(byAngle: 0.5, duration: 0.2)]),
            .removeFromParent(),
        ])
        action.timingMode = .easeIn
        return action
    }

    /// A lasered piece: it trembles under the beam, then vaporises.
    static func vaporizeAction() -> SKAction {
        var tremble: [SKAction] = []
        for _ in 0..<4 {
            tremble.append(.moveBy(x: CGFloat.random(in: -2.5...2.5), y: CGFloat.random(in: -2.5...2.5), duration: 0.03))
        }
        return .sequence([
            .sequence(tremble),
            .group([.scale(to: 0.3, duration: 0.22), .fadeOut(withDuration: 0.22), .rotate(byAngle: 0.3, duration: 0.22)]),
            .removeFromParent(),
        ])
    }

    // MARK: Camera shake

    /// Shakes a camera around `center` with decaying random offsets, ending exactly on `center`.
    static func shakeAction(around center: CGPoint, amplitude: CGFloat, duration: TimeInterval) -> SKAction {
        let steps = 9
        var actions: [SKAction] = []
        for i in 0..<steps {
            let falloff = 1 - CGFloat(i) / CGFloat(steps)
            let offset = CGPoint(
                x: CGFloat.random(in: -amplitude...amplitude) * falloff,
                y: CGFloat.random(in: -amplitude...amplitude) * falloff
            )
            actions.append(.move(to: CGPoint(x: center.x + offset.x, y: center.y + offset.y), duration: duration / Double(steps + 1)))
        }
        actions.append(.move(to: center, duration: duration / Double(steps + 1)))
        return .sequence(actions)
    }
}

extension CGRect {
    /// Center point of the rectangle.
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
