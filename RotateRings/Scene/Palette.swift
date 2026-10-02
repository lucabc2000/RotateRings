//
//  Palette.swift
//  RotateRings
//
//  The game's colours. Piece colours are looked up by the name stored in the level file.
//

import UIKit

enum Palette {
    // Backgrounds and surfaces
    static let backgroundTop = UIColor(hex: 0x1E2A6B)
    static let backgroundBottom = UIColor(hex: 0x0F1638)
    static let card = UIColor(hex: 0x25306E)
    static let cardBorder = UIColor(hex: 0x3A4690)

    // Text and icons
    static let textPrimary = UIColor.white
    static let textSecondary = UIColor(hex: 0x9AA3D0)
    static let icon = UIColor(hex: 0xDDE2F5)

    // Clips, hubs and holders (silver)
    static let silverLight = UIColor(hex: 0xF2F5FA)
    static let silverDark = UIColor(hex: 0xA9B0BF)
    static let silverOutline = UIColor(hex: 0x8C93A3)

    // Depth
    static let shadow = UIColor.black.withAlphaComponent(0.4)
    static let shadowOffset = CGPoint(x: 0, y: -7)
    static let shadowBlurRadius: CGFloat = 5

    /// The five ring colours.
    private static let pieceColors: [String: UIColor] = [
        "coral": UIColor(hex: 0xFF5A5F),
        "yellow": UIColor(hex: 0xFFC93C),
        "mint": UIColor(hex: 0x2EE6C5),
        "sky": UIColor(hex: 0x4DB8FF),
        "purple": UIColor(hex: 0xA66BFF),
    ]

    /// Older level files used these names.
    private static let aliases: [String: String] = [
        "mustard": "yellow",
        "teal": "sky",
        "violet": "purple",
        "navy": "purple",
        "rose": "coral",
    ]

    static func pieceColor(named name: String) -> UIColor {
        pieceColors[aliases[name] ?? name] ?? pieceColors["coral"]!
    }
}

extension UIColor {
    /// Creates an opaque colour from a 0xRRGGBB value.
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
