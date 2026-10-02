//
//  ContentView.swift
//  RotateRings
//

import SwiftUI
import SpriteKit
import StoreKit

/// Where the feedback button sends mail.
private enum Feedback {
    static let address = "hello@lumisoftware.io"

    /// A `mailto:` link with the app's name in the subject.
    static var mailURL: URL? {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Game"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [URLQueryItem(name: "subject", value: "\(name) feedback")]
        return components.url
    }
}

struct ContentView: View {
    @State private var model = GameViewModel()
    @State private var isShowingSettings = false
    @State private var isShowingBrowser = false
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    /// Shown on the end screen when no mail app could be opened.
    @State private var feedbackNote: String?
    /// Where the full-screen game view and the board's area are on screen; together they tell the
    /// scene where to put the board.
    @State private var gameViewFrame = CGRect.zero
    @State private var boardAreaFrame = CGRect.zero

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(uiColor: Palette.backgroundTop), Color(uiColor: Palette.backgroundBottom)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            gameView

            VStack(spacing: 12) {
                header
                boardArea
                boosterBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Full-screen flashes requested by the scene (lightning dim and strike).
            Color(uiColor: model.flashColor)
                .opacity(model.flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if model.isLevelComplete || model.isCampaignFinished {
                // The scrim only fades, so it covers the whole screen from the first frame;
                // the card fades and scales.
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                Group {
                    if model.isCampaignFinished {
                        campaignFinishedCard
                    } else {
                        levelCompleteCard
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.spring(duration: 0.35), value: model.isLevelComplete || model.isCampaignFinished)
        .onChange(of: model.reviewRequests) {
            Task {
                // Let the completion card settle first, and skip it if the player has already moved on.
                try? await Task.sleep(for: .seconds(1.2))
                guard model.isLevelComplete else { return }
                requestReview()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(onRestart: model.restart, onOpenLevelBrowser: {
                isShowingBrowser = true
            })
        }
        #if DEBUG
        .fullScreenCover(isPresented: $isShowingBrowser) {
            LevelBrowserView { file, title in
                model.play(file, title: title)
                isShowingBrowser = false
            }
        }
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isPreviewing ? "Preview" : "Level \(model.levelNumber)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(uiColor: Palette.textPrimary))
                Text(model.levelName)
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: Palette.textSecondary))
            }
            Spacer()
            Button {
                if model.isPreviewing {
                    model.exitPreview()
                } else {
                    isShowingSettings = true
                }
            } label: {
                Image(systemName: model.isPreviewing ? "xmark" : "gearshape.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(uiColor: Palette.icon))
                    .frame(width: 44, height: 44)
                    .background(CardCircle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPreviewing ? "Leave preview" : "Settings")
            // The completion overlay covers the header, so the button is dimmed and disabled with it.
            .disabled(model.isLevelComplete || model.isCampaignFinished)
            .opacity(model.isLevelComplete || model.isCampaignFinished ? 0.4 : 1)
        }
    }

    /// The game itself, over the whole screen and behind the controls, so pieces flying off the board
    /// travel all the way to the screen's edge. The scene places the board inside `boardArea`.
    @ViewBuilder
    private var gameView: some View {
        if let scene = model.scene {
            // 120 fps on ProMotion displays; CADisableMinimumFrameDurationOnPhone in Info.plist allows it.
            SpriteView(scene: scene, preferredFramesPerSecond: 120, options: [.allowsTransparency])
                .id(ObjectIdentifier(scene))
                // Measured before the safe area is ignored: outside that modifier the view still
                // reports the safe area's frame, not the full-screen one the scene really has.
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    gameViewFrame = frame
                    updateBoardFrame()
                }
                .ignoresSafeArea()
                // Hidden until the scene has drawn its first frame, so the blank Metal layer never shows.
                .opacity(model.isSceneReady ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: model.isSceneReady)
        }
    }

    /// Tells the scene where the board's area is, in the game view's own coordinates.
    private func updateBoardFrame() {
        guard !gameViewFrame.isEmpty, !boardAreaFrame.isEmpty else { return }
        model.boardFrame = boardAreaFrame.offsetBy(dx: -gameViewFrame.minX, dy: -gameViewFrame.minY)
    }

    /// The space between the header and the booster bar. It only reserves the room and reports
    /// where it is; the board is drawn there by the full-screen game view underneath.
    @ViewBuilder
    private var boardArea: some View {
        if model.scene != nil {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    boardAreaFrame = frame
                    updateBoardFrame()
                }
        } else if model.isCampaignFinished {
            // Reopened after the last level: there is no board, only the end screen on top.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text(model.errorMessage ?? "Could not load level.")
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color(uiColor: Palette.textSecondary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Lightning (random piece) and laser (pick a piece) boosters.
    private var boosterBar: some View {
        VStack(spacing: 6) {
            Text(model.isLaserArmed ? "Tap a piece to aim the laser" : " ")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(uiColor: Palette.textSecondary))
                .animation(.easeInOut(duration: 0.15), value: model.isLaserArmed)
            HStack(spacing: 24) {
                BoosterButton(title: Booster.lightning.title, count: model.boosterCount(.lightning), isActive: false, action: model.useLightning) {
                    LightningIcon()
                }
                .disabled(model.isLaserArmed)
                BoosterButton(title: Booster.laser.title, count: model.boosterCount(.laser), isActive: model.isLaserArmed, action: model.toggleLaser) {
                    LaserIcon()
                }
            }
        }
        .disabled(model.scene == nil || model.isLevelComplete || model.isCampaignFinished)
        .opacity(model.isLevelComplete || model.isCampaignFinished ? 0.4 : 1)
    }

    private var levelCompleteCard: some View {
        OverlayCard {
            Text("Level complete!")
                .font(.title.weight(.bold))
                .foregroundStyle(Color(uiColor: Palette.textPrimary))
            Text(model.isPreviewing ? "Preview solved." : "Nicely untangled.")
                .font(.body)
                .foregroundStyle(Color(uiColor: Palette.textSecondary))
            earnedBoosterBadge
            Button {
                model.nextLevel()
            } label: {
                PrimaryButtonLabel(title: model.isPreviewing ? "Back" : "Next level")
            }
            .buttonStyle(.plain)
        }
    }

    /// The end of the campaign: shown after the last level, and again on every launch until new
    /// levels arrive or the player starts over.
    private var campaignFinishedCard: some View {
        OverlayCard {
            Text("You cleared every level!")
                .font(.title.weight(.bold))
                .foregroundStyle(Color(uiColor: Palette.textPrimary))
                .multilineTextAlignment(.center)
            Text("New levels are coming very soon.")
                .font(.body)
                .foregroundStyle(Color(uiColor: Palette.textSecondary))
                .multilineTextAlignment(.center)
            earnedBoosterBadge
            Button(action: sendFeedback) {
                PrimaryButtonLabel(title: "Send feedback")
            }
            .buttonStyle(.plain)
            if let feedbackNote {
                Text(feedbackNote)
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: Palette.textSecondary))
                    .multilineTextAlignment(.center)
            }
            Button {
                feedbackNote = nil
                model.startOver()
            } label: {
                Text("Start over from level 1")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: Palette.textSecondary))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
        }
    }

    /// The booster earned by the level just completed, if any. Boosters are rare, so earning one gets
    /// its own line on the card.
    @ViewBuilder
    private var earnedBoosterBadge: some View {
        if let booster = model.earnedBooster {
            HStack(spacing: 10) {
                Group {
                    switch booster {
                    case .lightning: LightningIcon()
                    case .laser: LaserIcon()
                    }
                }
                .frame(width: 20, height: 20)
                Text("+1 \(booster.title)")
                    .font(.headline)
            }
            .foregroundStyle(Color(uiColor: Palette.pieceColor(named: "yellow")))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(uiColor: Palette.backgroundBottom)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Earned one \(booster.title) booster")
        }
    }

    /// Opens a new mail to the feedback address. Without a mail app the address is copied instead,
    /// and a note on the card says so.
    private func sendFeedback() {
        guard let url = Feedback.mailURL else { return }
        openURL(url) { accepted in
            guard !accepted else { return }
            UIPasteboard.general.string = Feedback.address
            feedbackNote = "No mail app found. The address \(Feedback.address) was copied."
        }
    }
}

// MARK: - Shared chrome

/// The card shown over the dimmed board when a level, or the whole campaign, is done.
private struct OverlayCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 18, content: content)
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(uiColor: Palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(uiColor: Palette.cardBorder), lineWidth: 1.5))
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            .padding(32)
    }
}

/// The filled capsule of a card's main button.
private struct PrimaryButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color(uiColor: Palette.backgroundBottom))
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color(uiColor: Palette.pieceColor(named: "mint"))))
    }
}

/// The card-coloured disc with its subtle border used behind round buttons.
private struct CardCircle: View {
    var isActive = false

    var body: some View {
        Circle()
            .fill(isActive ? Color(uiColor: Palette.pieceColor(named: "purple")) : Color(uiColor: Palette.card))
            .overlay(
                Circle().strokeBorder(
                    isActive ? Color.white.opacity(0.7) : Color(uiColor: Palette.cardBorder),
                    lineWidth: 1.5
                )
            )
    }
}

/// A round booster button with a vector icon, a badge showing how many are left and a small caption.
/// With none left the button is dimmed and does nothing.
private struct BoosterButton<Icon: View>: View {
    let title: String
    let count: Int
    let isActive: Bool
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon()
                    .foregroundStyle(Color(uiColor: Palette.icon))
                    .frame(width: 26, height: 26)
                    .frame(width: 60, height: 60)
                    .background(CardCircle(isActive: isActive))
                    .overlay(alignment: .topTrailing) {
                        Text("\(count)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color(uiColor: Palette.backgroundBottom))
                            .frame(minWidth: 22, minHeight: 22)
                            .background(Capsule().fill(Color(uiColor: Palette.pieceColor(named: count > 0 ? "yellow" : "coral"))))
                            .offset(x: 4, y: -4)
                    }
                    .scaleEffect(isActive ? 1.08 : 1)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: Palette.textSecondary))
            }
        }
        .buttonStyle(.plain)
        .disabled(count == 0 && !isActive)
        .opacity(count == 0 && !isActive ? 0.45 : 1)
        .animation(.spring(duration: 0.25), value: isActive)
        .animation(.spring(duration: 0.25), value: count)
        .accessibilityLabel(title)
        .accessibilityValue("\(count) left")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Booster icons

/// A simple lightning bolt, filled.
private struct LightningIcon: View {
    var body: some View {
        LightningBoltShape()
            .fill()
    }
}

private struct LightningBoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.58, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.16, y: rect.minY + h * 0.58))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.46, y: rect.minY + h * 0.58))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.38, y: rect.minY + h))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.84, y: rect.minY + h * 0.40))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.54, y: rect.minY + h * 0.40))
        path.closeSubpath()
        return path
    }
}

/// A targeting reticle: ring, four ticks and a center dot, stroked.
private struct LaserIcon: View {
    var body: some View {
        ZStack {
            LaserReticleShape()
                .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            Circle()
                .fill()
                .frame(width: 5, height: 5)
        }
    }
}

private struct LaserReticleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - radius * 0.62, y: center.y - radius * 0.62, width: radius * 1.24, height: radius * 1.24))
        for i in 0..<4 {
            let angle = CGFloat(i) * .pi / 2
            path.move(to: CGPoint(x: center.x + cos(angle) * radius * 0.62, y: center.y + sin(angle) * radius * 0.62))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        }
        return path
    }
}

#Preview {
    ContentView()
}
