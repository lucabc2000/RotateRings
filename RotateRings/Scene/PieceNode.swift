//
//  PieceNode.swift
//  RotateRings
//
//  Renders one model `Piece` with thick rounded strokes, a soft blurred shadow, silver clips and an
//  optional hub or holder. The node's position is the piece's pivot/holder and its zRotation is the
//  piece's rotation, so the children use the piece's local coordinates directly. For sliding pieces the
//  body sits in a child node that is offset along the local x axis while the holder stays put.
//

import SpriteKit
import CoreImage

@MainActor
final class PieceNode: SKNode {
    let pieceID: Piece.ID
    let motion: Piece.Motion
    /// The piece's stroke colour, reused by effects such as debris.
    let color: UIColor

    /// Body, clips and their shadow. Moves along x for sliding pieces.
    private let bodyNode = SKNode()
    /// The fixed hub of a sliding piece and its shadow; empty for turning pieces.
    private var hubNodes: [SKNode] = []

    /// Vertical silver gradient used to fill clips, hubs and holders.
    static let silverTexture: SKTexture = {
        let size = CGSize(width: 8, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [Palette.silverLight.cgColor, Palette.silverDark.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }()

    init(piece: Piece) {
        pieceID = piece.id
        motion = piece.motion
        color = Palette.pieceColor(named: piece.color)
        super.init()
        position = CGPoint(x: piece.position.x, y: piece.position.y)
        zRotation = CGFloat(piece.rotation)

        let bodyPath = Self.path(for: piece.shapes)

        // Shadow pass (body + clips), blurred and offset downwards, below everything else.
        let shadowGroup = Self.makeShadowGroup()
        shadowGroup.addChild(Self.strokeNode(path: bodyPath, color: Palette.shadow))
        for clip in piece.clips {
            for node in Self.clipNodes(for: clip, stemColor: Palette.shadow, shadow: true) {
                shadowGroup.addChild(node)
            }
        }
        bodyNode.addChild(shadowGroup)

        // Body.
        let body = Self.strokeNode(path: bodyPath, color: color)
        body.zPosition = 1
        bodyNode.addChild(body)

        // Clips.
        for clip in piece.clips {
            for node in Self.clipNodes(for: clip, stemColor: color, shadow: false) {
                node.zPosition = 2
                bodyNode.addChild(node)
            }
        }
        addChild(bodyNode)
        setOffset(piece.offset)

        // The fixed metal hub of a sliding piece, at the local origin. Only sliding pieces have one.
        if piece.hasHub {
            let hubShadow = Self.makeShadowGroup()
            hubShadow.zPosition = 2.5
            hubShadow.addChild(Self.hubNode(shadow: true))
            addChild(hubShadow)

            let hub = Self.hubNode(shadow: false)
            hub.zPosition = 3
            addChild(hub)
            hubNodes = [hubShadow, hub]
        }
    }

    /// Leaves the hub behind when the bar flies off: it stays bolted where it was and fades out, while
    /// the rest of the node (the bar) keeps moving.
    func dropHub(fadeDuration: TimeInterval) {
        guard let parent else { return }
        for hub in hubNodes {
            let world = convert(hub.position, to: parent)
            hub.removeFromParent()
            parent.addChild(hub)
            hub.position = world
            hub.zRotation = zRotation
            hub.zPosition = zPosition - 0.5
            hub.run(.sequence([.fadeOut(withDuration: fadeDuration), .removeFromParent()]))
        }
        hubNodes = []
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("PieceNode does not support NSCoding")
    }

    /// Moves the body of a sliding piece along its axis.
    func setOffset(_ offset: Double) {
        bodyNode.position = CGPoint(x: offset, y: 0)
    }

    /// Applies the model's movement value: a rotation for turning pieces, an offset for sliding ones.
    func apply(movement value: Double) {
        switch motion {
        case .rotation: zRotation = CGFloat(value)
        case .slide: setOffset(value)
        }
    }

    private static let shakeKey = "shake"

    /// A quick wobble played when the piece is pressed against an obstruction: a small twist for turning
    /// pieces, a sideways shiver for sliding bars. It runs on the inner body node, which the finger
    /// never drives directly, so it cannot fight with `apply(movement:)`. Purely visual.
    func shake() {
        stopShake()
        switch motion {
        case .rotation:
            let wiggle: CGFloat = 0.03
            bodyNode.run(.sequence([
                .rotate(byAngle: wiggle, duration: 0.03),
                .rotate(byAngle: -wiggle * 2, duration: 0.06),
                .rotate(byAngle: wiggle, duration: 0.04),
            ]), withKey: Self.shakeKey)
        case .slide:
            let wiggle: CGFloat = 3
            bodyNode.run(.sequence([
                .moveBy(x: 0, y: wiggle, duration: 0.03),
                .moveBy(x: 0, y: -wiggle * 2, duration: 0.06),
                .moveBy(x: 0, y: wiggle, duration: 0.04),
            ]), withKey: Self.shakeKey)
        }
    }

    /// Cancels a running wobble and removes whatever offset it left behind on the body node.
    func stopShake() {
        bodyNode.removeAction(forKey: Self.shakeKey)
        bodyNode.zRotation = 0
        bodyNode.position.y = 0
    }

    // MARK: Building blocks

    /// A blurred, offset container for shadow copies. Rasterized so the blur is computed once.
    private static func makeShadowGroup() -> SKEffectNode {
        let group = SKEffectNode()
        group.filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: Palette.shadowBlurRadius])
        group.shouldRasterize = true
        group.shouldEnableEffects = true
        group.position = Palette.shadowOffset
        group.zPosition = 0
        return group
    }

    private static func path(for shapes: [Primitive]) -> CGPath {
        let path = CGMutablePath()
        for shape in shapes {
            switch shape {
            case .arc(let arc):
                let center = CGPoint(x: arc.center.x, y: arc.center.y)
                if arc.isClosed {
                    path.addEllipse(in: CGRect(
                        x: center.x - arc.radius, y: center.y - arc.radius,
                        width: arc.radius * 2, height: arc.radius * 2
                    ))
                } else {
                    path.move(to: CGPoint(x: arc.startPoint.x, y: arc.startPoint.y))
                    // SpriteKit's y axis points up, so clockwise: false sweeps counterclockwise on screen.
                    path.addArc(center: center, radius: arc.radius, startAngle: arc.start, endAngle: arc.end, clockwise: false)
                }
            case .segment(let segment):
                path.move(to: CGPoint(x: segment.from.x, y: segment.from.y))
                path.addLine(to: CGPoint(x: segment.to.x, y: segment.to.y))
            }
        }
        return path
    }

    private static func strokeNode(path: CGPath, color: UIColor, lineWidth: CGFloat = GameRules.strokeThickness) -> SKShapeNode {
        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.fillColor = .clear
        node.lineWidth = lineWidth
        node.lineCap = .round
        node.lineJoin = .round
        node.isAntialiased = true
        return node
    }

    /// Fills a shape with the silver gradient and gives it the silver outline.
    private static func silverFill(_ node: SKShapeNode) {
        node.fillTexture = silverTexture
        node.fillColor = .white
        node.strokeColor = Palette.silverOutline
        node.lineWidth = 1.5
    }

    private static func clipNodes(for clip: Clip, stemColor: UIColor, shadow: Bool) -> [SKNode] {
        let stemPath = CGMutablePath()
        stemPath.move(to: CGPoint(x: clip.stemStart.x, y: clip.stemStart.y))
        stemPath.addLine(to: CGPoint(x: clip.stemEnd.x, y: clip.stemEnd.y))
        let stem = strokeNode(path: stemPath, color: stemColor, lineWidth: GameRules.strokeThickness * 0.7)

        let size = GameRules.clipSize
        let square = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: 3.5)
        if shadow {
            square.fillColor = Palette.shadow
            square.strokeColor = .clear
        } else {
            silverFill(square)
        }
        square.position = CGPoint(x: clip.stemEnd.x, y: clip.stemEnd.y)
        square.zRotation = CGFloat((clip.stemEnd - clip.stemStart).angle)
        return [stem, square]
    }

    /// The fixed sleeve a sliding bar passes through: a squarer, heavier block than a clip square,
    /// lying along the local x axis, with a darker slot showing where the bar runs through it.
    private static func hubNode(shadow: Bool) -> SKNode {
        let size = CGSize(width: GameRules.holderLength, height: GameRules.strokeThickness + 14)
        let block = SKShapeNode(rectOf: size, cornerRadius: 3)
        if shadow {
            block.fillColor = Palette.shadow
            block.strokeColor = .clear
            return block
        }
        silverFill(block)
        block.lineWidth = 2
        block.strokeColor = Palette.silverOutline

        // The slot: a darker band the bar slides through, open at both ends.
        let slot = SKShapeNode(rectOf: CGSize(width: size.width - 4, height: GameRules.strokeThickness + 3), cornerRadius: 2)
        slot.fillColor = Palette.silverOutline.withAlphaComponent(0.55)
        slot.strokeColor = Palette.silverOutline.withAlphaComponent(0.8)
        slot.lineWidth = 1
        slot.zPosition = 0.1
        block.addChild(slot)

        // Two rivets at the ends, so the hub reads as bolted to the board.
        for x in [-size.width / 2 + 5, size.width / 2 - 5] {
            for y in [-size.height / 2 + 4, size.height / 2 - 4] {
                let rivet = SKShapeNode(circleOfRadius: 1.5)
                rivet.fillColor = Palette.silverOutline
                rivet.strokeColor = .clear
                rivet.position = CGPoint(x: x, y: y)
                rivet.zPosition = 0.2
                block.addChild(rivet)
            }
        }
        return block
    }
}
