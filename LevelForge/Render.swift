//
//  Render.swift
//  LevelForge
//
//  `render`: contact sheets for reviewing levels without playing them. One PNG per block of ten
//  levels, each board drawn small with its number, name, design and scores underneath; with
//  `--candidates` each level gets a row with its runner-ups next to it. Drawn with CoreGraphics
//  from the model's own world geometry, so it shows the shape of a board, not the app's look.
//

import CoreGraphics
import CoreText
import Foundation
import ImageIO

enum ContactSheet {
    static let cellWidth = 220.0
    static let boardHeight = 360.0
    static let captionHeight = 58.0
    static let gap = 12.0
    static let columns = 5

    /// The app's piece colours (`Palette`), with the old names it still accepts.
    private static let colors: [String: UInt32] = [
        "coral": 0xFF5A5F, "yellow": 0xFFC93C, "mint": 0x2EE6C5, "sky": 0x4DB8FF, "purple": 0xA66BFF,
        "mustard": 0xFFC93C, "teal": 0x4DB8FF, "violet": 0xA66BFF, "navy": 0xA66BFF, "rose": 0xFF5A5F,
    ]

    struct Cell {
        let file: LevelFile
        let caption: [String]
    }

    /// Draws `rows` of cells (a row per level with `--candidates`, otherwise rows of five levels).
    static func write(rows: [[Cell]], title: String, to url: URL) throws {
        let columnCount = max(1, rows.map(\.count).max() ?? 1)
        let width = gap + Double(columnCount) * (cellWidth + gap)
        let titleHeight = 30.0
        let rowHeight = boardHeight + captionHeight + gap
        let height = titleHeight + gap + Double(rows.count) * rowHeight
        guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // CoreGraphics is y-up, like the board.
        context.setFillColor(rgb(0x0B1030))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        text(title, at: CGPoint(x: gap, y: height - titleHeight + 8), size: 16, color: rgb(0xFFFFFF), in: context)
        for (r, row) in rows.enumerated() {
            let top = height - titleHeight - gap - Double(r) * rowHeight
            for (c, cell) in row.enumerated() {
                let x = gap + Double(c) * (cellWidth + gap)
                draw(cell, in: CGRect(x: x, y: top - boardHeight - captionHeight, width: cellWidth, height: boardHeight + captionHeight), context: context)
            }
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func draw(_ cell: Cell, in frame: CGRect, context: CGContext) {
        let area = CGRect(x: frame.minX, y: frame.maxY - boardHeight, width: frame.width, height: boardHeight)
        let boardWidth = cell.file.board.width, boardHeightValue = cell.file.board.height
        let scale = min(area.width / boardWidth, area.height / boardHeightValue)
        let origin = CGPoint(x: area.midX - boardWidth * scale / 2, y: area.midY - boardHeightValue * scale / 2)
        context.setFillColor(rgb(0x141C4A))
        context.fill(CGRect(x: origin.x, y: origin.y, width: boardWidth * scale, height: boardHeightValue * scale))
        func map(_ p: Point) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }

        if let board = try? cell.file.makeBoard() {
            context.setLineCap(.round)
            for piece in board.pieces {
                let color = rgb(colors[piece.color] ?? 0xCCCCCC)
                for world in piece.worldPrimitives() {
                    if case .clip = world.source {
                        context.setStrokeColor(rgb(0xFFFFFF, alpha: 0.75))
                        context.setLineWidth(max(1, GameRules.strokeThickness * 0.6 * scale))
                    } else {
                        context.setStrokeColor(color)
                        context.setLineWidth(max(1, GameRules.strokeThickness * scale))
                    }
                    switch world.primitive {
                    case .arc(let arc):
                        context.addArc(center: map(arc.center), radius: arc.radius * scale, startAngle: arc.start,
                                       endAngle: arc.start + arc.sweep, clockwise: false)
                    case .segment(let segment):
                        context.move(to: map(segment.from))
                        context.addLine(to: map(segment.to))
                    }
                    context.strokePath()
                }
                if piece.motion == .slide {
                    context.setFillColor(rgb(0xC9CED8))
                    for hub in piece.hubOffsets {
                        let p = map(piece.position + hub.rotated(by: piece.rotation))
                        let r = GameRules.hubRadius * scale
                        context.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                    }
                }
                if let bomb = piece.worldBomb {
                    let p = map(bomb), r = GameRules.bombRadius * scale
                    context.setFillColor(rgb(0x000000))
                    context.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                    context.setStrokeColor(rgb(0xFF5A5F))
                    context.setLineWidth(1)
                    context.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
                }
            }
        }
        for (i, line) in cell.caption.enumerated() {
            text(line, at: CGPoint(x: frame.minX + 2, y: frame.minY + captionHeight - 16 - Double(i) * 15),
                 size: i == 0 ? 12 : 11, color: rgb(i == 0 ? 0xFFFFFF : 0xB8C0D8), in: context)
        }
    }

    private static func text(_ string: String, at point: CGPoint, size: Double, color: CGColor, in context: CGContext) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        guard let attributed = CFAttributedStringCreate(nil, string as CFString, attributes) else { return }
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }

    private static func rgb(_ hex: UInt32, alpha: Double = 1) -> CGColor {
        CGColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }
}
