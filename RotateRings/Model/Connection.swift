//
//  Connection.swift
//  RotateRings
//

import Foundation

/// Something that keeps a piece on the board. Two kinds exist:
/// - a clip of `owner` gripping the ring arc of `ring`;
/// - a sliding piece (`owner`) still sitting in its fixed holder. For this kind `ring == owner`.
struct Connection: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case clip(index: Int)
        case holder
    }

    /// The piece that is held: the clip owner, or the sliding piece.
    let owner: Piece.ID
    let kind: Kind
    /// The ring piece doing the holding (the piece itself for a holder).
    let ring: Piece.ID

    init(owner: Piece.ID, clipIndex: Int, ring: Piece.ID) {
        self.owner = owner
        self.kind = .clip(index: clipIndex)
        self.ring = ring
    }

    init(holderOf piece: Piece.ID) {
        self.owner = piece
        self.kind = .holder
        self.ring = piece
    }

    var clipIndex: Int? {
        if case .clip(let index) = kind { return index }
        return nil
    }

    var isHolder: Bool { kind == .holder }

    func involves(_ id: Piece.ID) -> Bool {
        owner == id || ring == id
    }
}
