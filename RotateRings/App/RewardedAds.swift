//
//  RewardedAds.swift
//  RotateRings
//
//  AdMob rewarded videos: the only ads in the game. A player who runs out of a booster can watch one
//  to get another. At launch: Google's consent form (UMP, shown only where the law asks for it),
//  then Apple's tracking prompt (App Tracking Transparency, required because AdMob's data is used to
//  track), then one video is kept loaded so it plays the moment the player asks.
//

import AppTrackingTransparency
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// AdMob identifiers. Debug builds always use Google's test unit, so development never serves
/// real ads. The app ID lives in Info.plist as `GADApplicationIdentifier`.
private enum AdUnit {
    #if DEBUG
    static let rewarded = "ca-app-pub-3940256099942544/1712485313"
    #else
    static let rewarded = "ca-app-pub-3669336532662186/3562952355"
    #endif
}

@MainActor
@Observable
final class RewardedAds: NSObject, FullScreenContentDelegate {
    static let shared = RewardedAds()

    /// A video is loaded and can play right away.
    var isReady: Bool { ad != nil && !isExpired }
    private(set) var isLoading = false
    /// The last load failed; the player can ask to try again.
    private(set) var didFailToLoad = false
    /// The player must be offered a way to change their consent (a row in Settings).
    private(set) var needsPrivacyOptions = false

    private var ad: RewardedAd?
    /// When `ad` finished loading. AdMob videos expire an hour after loading.
    private var loadedAt: Date?
    private static let lifetime: TimeInterval = 55 * 60
    private var hasStarted = false
    /// Called once the playing video is closed, with whether the reward was earned.
    private var onFinish: ((Bool) -> Void)?
    private var didEarnReward = false

    /// Asks for consent where required, then for tracking permission, starts the SDK and loads the
    /// first video. Safe to call again.
    func start() async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            // No network or no message set up: carry on with whatever consent is already stored.
        }
        needsPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        await requestTrackingPermission()
        guard ConsentInformation.shared.canRequestAds, !hasStarted else { return }
        hasStarted = true
        await MobileAds.shared.start()
        load()
    }

    /// Loads the next video unless one is already loaded or on its way. An expired video is dropped
    /// and replaced.
    func load() {
        if isExpired { ad = nil }
        guard hasStarted, ad == nil, !isLoading else { return }
        isLoading = true
        didFailToLoad = false
        Task {
            do {
                let ad = try await RewardedAd.load(with: AdUnit.rewarded, request: Request())
                ad.fullScreenContentDelegate = self
                self.ad = ad
                loadedAt = .now
            } catch {
                didFailToLoad = true
            }
            isLoading = false
        }
    }

    /// Plays the loaded video. `onFinish` runs when the player closes it, with true if they watched
    /// long enough to earn the reward. False straight away if no video is ready.
    func show(onFinish: @escaping (Bool) -> Void) {
        guard let ad else { onFinish(false); return }
        self.onFinish = onFinish
        didEarnReward = false
        ad.present(from: Self.topViewController()) { [weak self] in
            self?.didEarnReward = true
        }
    }

    private var isExpired: Bool {
        guard ad != nil, let loadedAt else { return false }
        return Date.now.timeIntervalSince(loadedAt) > Self.lifetime
    }

    /// Apple's tracking prompt, once. The system only shows it while the app is active; asked too
    /// early in launch it returns "not determined" without showing anything, so wait briefly first.
    private func requestTrackingPermission() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        var waited = 0
        while UIApplication.shared.applicationState != .active && waited < 20 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    /// Google's form for changing consent, from the Settings row.
    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController())
        needsPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    // MARK: FullScreenContentDelegate

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        finish()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        finish()
    }

    /// Hands the result back, forgets the used video and loads the next one.
    private func finish() {
        let onFinish = onFinish
        self.onFinish = nil
        ad = nil
        load()
        onFinish?(didEarnReward)
    }

    /// The view controller on top, to present the video and forms over (sheets included).
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
