//
//  LevelThumbnail.swift
//  RotateRings
//
//  Debug only. A small static rendering of a level file for the Level Browser.
//

#if DEBUG
import SwiftUI

struct LevelThumbnail: View {
    let file: LevelFile

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / file.board.width, size.height / file.board.height)
            let origin = CGPoint(x: (size.width - file.board.width * scale) / 2, y: (size.height - file.board.height * scale) / 2)
            func map(_ point: Point) -> CGPoint {
                CGPoint(x: origin.x + point.x * scale, y: origin.y + (file.board.height - point.y) * scale)
            }
            let strokeWidth = max(1.5, GameRules.strokeThickness * scale)
            let silver = Color(uiColor: Palette.silverLight)

            for piece in file.pieces {
                let color = Color(uiColor: Palette.pieceColor(named: piece.color ?? "coral"))
                let rotation = AngleMath.radians(fromDegrees: piece.rotation ?? 0)
                func world(_ local: Point) -> CGPoint { map(local.rotated(by: rotation) + piece.position) }

                var body = Path()
                for shape in piece.shapes {
                    switch shape {
                    case .arc(let arc):
                        let start = AngleMath.radians(fromDegrees: arc.start)
                        let sweep = AngleMath.radians(fromDegrees: min(360, arc.sweep))
                        let steps = max(8, Int(arc.sweep / 4))
                        for i in 0...steps {
                            let angle = start + sweep * Double(i) / Double(steps)
                            let point = world(Point(arc.center.x + arc.radius * cos(angle), arc.center.y + arc.radius * sin(angle)))
                            if i == 0 { body.move(to: point) } else { body.addLine(to: point) }
                        }
                    case .segment(let segment):
                        body.move(to: world(segment.from))
                        body.addLine(to: world(segment.to))
                    }
                }
                context.stroke(body, with: .color(color), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))

                for clip in piece.clips ?? [] {
                    var stem = Path()
                    stem.move(to: world(clip.stemStart))
                    stem.addLine(to: world(clip.stemEnd))
                    context.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: strokeWidth * 0.7, lineCap: .round))
                    let side = GameRules.clipSize * scale
                    let center = world(clip.stemEnd)
                    let square = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
                    context.fill(Path(roundedRect: square, cornerRadius: side * 0.2), with: .color(silver))
                }

                // The fixed hub of a sliding piece: a silver block with a darker slot along the axis
                // (same look as PieceNode, scaled down).
                if piece.motion == .slide {
                    let length = GameRules.holderLength * scale, thickness = (GameRules.strokeThickness + 14) * scale
                    let center = map(piece.position)
                    let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: -rotation)
                    let block = Path(roundedRect: CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness), cornerRadius: 3 * scale)
                    context.fill(block.applying(transform), with: .color(silver))
                    let slotHeight = (GameRules.strokeThickness + 3) * scale
                    let slot = Path(roundedRect: CGRect(x: -length / 2 + 2 * scale, y: -slotHeight / 2, width: length - 4 * scale, height: slotHeight), cornerRadius: 2 * scale)
                    context.fill(slot.applying(transform), with: .color(Color(uiColor: Palette.silverOutline).opacity(0.6)))
                }
            }
        }
        .aspectRatio(file.board.width / file.board.height, contentMode: .fit)
    }
}
#endif
