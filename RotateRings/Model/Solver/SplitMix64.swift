//
//  SplitMix64.swift
//  RotateRings
//
//  A tiny deterministic random number generator. The system generator is seeded from entropy, so
//  anything that must reproduce byte-for-byte across runs and machines (level generation, solver
//  playouts) uses this instead.
//

import Foundation

struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A derived generator for an independent stream (e.g. one per level or candidate).
    func derived(_ salt: UInt64) -> SplitMix64 {
        var copy = self
        copy.state ^= salt &* 0xD6E8_FEB8_6659_FD93
        _ = copy.next()
        return copy
    }
}
