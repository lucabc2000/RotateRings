//
//  SettingsView.swift
//  RotateRings
//

import SwiftUI
import UIKit

/// Sound and haptics toggles, a feedback link and a restart action, shown as a sheet from the gear button.
struct SettingsView: View {
    let onRestart: () -> Void
    /// Debug builds only: opens the Level Browser. Ignored in release builds.
    var onOpenLevelBrowser: (() -> Void)? = nil

    @Bindable private var settings = GameSettings.shared
    private let ads = RewardedAds.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// Shown under the rows when no mail app could be opened.
    @State private var feedbackNote: String?

    init(onRestart: @escaping () -> Void, onOpenLevelBrowser: (() -> Void)? = nil) {
        self.onRestart = onRestart
        self.onOpenLevelBrowser = onOpenLevelBrowser
    }

    #if DEBUG
    private let showsLevelBrowser = true
    #else
    private let showsLevelBrowser = false
    #endif

    /// Tall enough for the rows on show: each extra row adds about 50 points.
    private var sheetHeight: CGFloat {
        370 + (showsLevelBrowser ? 70 : 0) + (ads.needsPrivacyOptions ? 50 : 0) + (feedbackNote == nil ? 0 : 40)
    }

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
                Divider()
                    .overlay(Color(uiColor: Palette.cardBorder))
                    .padding(.horizontal, 16)
                linkRow("Send feedback", systemImage: "envelope.fill", action: sendFeedback)
                if ads.needsPrivacyOptions {
                    Divider()
                        .overlay(Color(uiColor: Palette.cardBorder))
                        .padding(.horizontal, 16)
                    // Required by Google where consent was asked: a way to change the ad choices.
                    linkRow("Privacy choices", systemImage: "hand.raised.fill") {
                        Task { await ads.presentPrivacyOptions() }
                    }
                }
                if showsLevelBrowser, let onOpenLevelBrowser {
                    Divider()
                        .overlay(Color(uiColor: Palette.cardBorder))
                        .padding(.horizontal, 16)
                    linkRow("Level Browser", systemImage: "list.number") {
                        dismiss()
                        onOpenLevelBrowser()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(uiColor: Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(uiColor: Palette.cardBorder), lineWidth: 1.5))
            )

            if let feedbackNote {
                Text(feedbackNote)
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: Palette.textSecondary))
                    .multilineTextAlignment(.center)
            }

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

    /// Opens a new mail to the feedback address. Without a mail app the address is copied instead,
    /// and a note under the rows says so.
    private func sendFeedback() {
        guard let url = Feedback.mailURL else { return }
        openURL(url) { accepted in
            guard !accepted else { return }
            UIPasteboard.general.string = Feedback.address
            feedbackNote = "No mail app found. The address \(Feedback.address) was copied."
        }
    }

    /// A row that opens something else, with a chevron.
    private func linkRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color(uiColor: Palette.textPrimary))
                } icon: {
                    Image(systemName: systemImage)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
