//
//  SettingsView.swift
//  RotateRings
//

import SwiftUI
import UIKit

/// Sound and haptics toggles plus a restart action, shown as a sheet from the gear button.
struct SettingsView: View {
    let onRestart: () -> Void
    /// Debug builds only: opens the Level Browser. Ignored in release builds.
    var onOpenLevelBrowser: (() -> Void)? = nil

    @Bindable private var settings = GameSettings.shared
    @Environment(\.dismiss) private var dismiss

    init(onRestart: @escaping () -> Void, onOpenLevelBrowser: (() -> Void)? = nil) {
        self.onRestart = onRestart
        self.onOpenLevelBrowser = onOpenLevelBrowser
    }

    #if DEBUG
    private let showsLevelBrowser = true
    private let sheetHeight: CGFloat = 390
    #else
    private let showsLevelBrowser = false
    private let sheetHeight: CGFloat = 320
    #endif

    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(uiColor: Palette.textPrimary))

            VStack(spacing: 0) {
                settingRow("Sound", systemImage: "speaker.wave.2.fill", isOn: $settings.isSoundEnabled)
                Divider()
                    .overlay(Color(uiColor: Palette.cardBorder))
                    .padding(.horizontal, 16)
                settingRow("Haptics", systemImage: "iphone.radiowaves.left.and.right", isOn: $settings.isHapticsEnabled)
                if showsLevelBrowser, let onOpenLevelBrowser {
                    Divider()
                        .overlay(Color(uiColor: Palette.cardBorder))
                        .padding(.horizontal, 16)
                    Button {
                        dismiss()
                        onOpenLevelBrowser()
                    } label: {
                        HStack {
                            Label {
                                Text("Level Browser")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color(uiColor: Palette.textPrimary))
                            } icon: {
                                Image(systemName: "list.number")
                                    .foregroundStyle(Color(uiColor: Palette.icon))
                                    .frame(width: 28)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(uiColor: Palette.textSecondary))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(uiColor: Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(uiColor: Palette.cardBorder), lineWidth: 1.5))
            )

            Button {
                dismiss()
                onRestart()
            } label: {
                Label("Restart level", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: Palette.backgroundBottom))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color(uiColor: Palette.pieceColor(named: "mint"))))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: Palette.backgroundBottom))
        // A little feedback when a setting is switched back on, so the player hears or feels it work.
        .onChange(of: settings.isSoundEnabled) { _, isOn in
            if isOn { SoundPlayer.shared.play(.button) }
        }
        .onChange(of: settings.isHapticsEnabled) { _, isOn in
            if isOn { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        }
    }

    private func settingRow(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(uiColor: Palette.textPrimary))
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Color(uiColor: Palette.icon))
                    .frame(width: 28)
            }
        }
        .tint(Color(uiColor: Palette.pieceColor(named: "mint")))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    SettingsView(onRestart: {})
}
