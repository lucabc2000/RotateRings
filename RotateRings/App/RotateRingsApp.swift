//
//  RotateRingsApp.swift
//  RotateRings
//

import SwiftUI

@main
struct RotateRingsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // The game is always on a dark background, so run in dark mode for a light status bar.
                .preferredColorScheme(.dark)
        }
    }
}
