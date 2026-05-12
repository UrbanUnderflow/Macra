import Foundation
import UIKit
import Combine
#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

/// Single funnel for every deep link the app receives — universal links,
/// custom-scheme URLs, and (once the SDK is installed) AppsFlyer OneLink
/// resolutions. Mirrors the QuickLifts pattern (`CustomAppDelegate` +
/// `AppState.handleIncomingLink`) but kept compact since Macra's only
/// link surface today is buddy invites.
///
/// AppsFlyer dependence is wrapped in `#if canImport(AppsFlyerLib)` so
/// the file builds before the SDK package is added — the integration
/// lights up automatically once the package is on the target.
final class MacraDeepLinkService: NSObject {
    static let sharedInstance = MacraDeepLinkService()

    /// Pending invite token captured at cold start before the UI has
    /// mounted. The Buddies-button SwiftUI view subscribes to
    /// `pendingInvitePublisher` and prompts the user to accept once the
    /// app is interactive.
    @Published private(set) var pendingInviteToken: String?

    var pendingInvitePublisher: AnyPublisher<String?, Never> {
        $pendingInviteToken.eraseToAnyPublisher()
    }

    /// AppsFlyer config. Same dev key as QuickLifts (shared AppsFlyer
    /// account); App ID + OneLink values are Macra-specific from the
    /// dashboard's `macra_template`.
    static let appsFlyerDevKey = "2sQsBqpiffBps2KyybNbzY"
    static let appleAppID = "6463771067"
    /// 4-character OneLink template ID — `iwHk` per the dashboard's
    /// macra_template. Required for `AppsFlyerShareInviteHelper
    /// .generateInviteUrl` to produce short URLs (e.g.
    /// `macra.onelink.me/iwHk/abcd1234`).
    static let oneLinkTemplateID: String? = "iwHk"
    /// OneLink subdomain provisioned for Macra. Matches the
    /// `applinks:macra.onelink.me` entitlement entry that needs to land in
    /// Signing & Capabilities for universal-link resolution to work.
    static let oneLinkSubdomain: String? = "macra.onelink.me"
    /// Keep buddy invite shares on the first-party universal-link domain
    /// until AppsFlyer serves an AASA file for `macra.onelink.me` that
    /// includes `ZG887P86D5.Tremaine.Macra`.
    static let useAppsFlyerOneLinkForBuddyInvites = false
    /// App Store URL used as the iOS fallback (`af_ios_url` / `af_r`)
    /// when the user taps a OneLink without Macra installed.
    static let appStoreURL = "https://apps.apple.com/us/app/macra-ai-calorie/id6463771067"

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Called from `MacraAppDelegate.didFinishLaunching` *before* any
    /// cold-start link is dispatched. Property assignments only — must
    /// be synchronous to satisfy AppsFlyer's "configure before any
    /// handleOpen" requirement.
    func configure() {
        #if canImport(AppsFlyerLib)
        let af = AppsFlyerLib.shared()
        af.appsFlyerDevKey = Self.appsFlyerDevKey
        af.appleAppID = Self.appleAppID
        if let oneLink = Self.oneLinkTemplateID {
            af.appInviteOneLinkID = oneLink
        }
        af.delegate = self
        af.deepLinkDelegate = self
        #if DEBUG
        af.isDebug = true
        #endif
        print("[Macra][DeepLink.configure] AppsFlyer configured · appID=\(Self.appleAppID)")
        #else
        print("[Macra][DeepLink.configure] AppsFlyerLib not yet on target — running in stub mode.")
        #endif
    }

    /// Call after the user has answered the ATT prompt (or skipped it).
    /// AppsFlyer requires `start()` only after that decision so iOS
    /// doesn't crash on IDFA access.
    func startSDK() {
        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().start()
        MacraAnalyticsService.shared.trackAppOpened()
        print("[Macra][DeepLink.startSDK] AppsFlyer started")
        #endif
    }

    // MARK: - URL ingress

    /// Universal-link entry point — invoked from `MacraAppDelegate
    /// .application(_:continue:)` and from `.onContinueUserActivity`
    /// in any SwiftUI surface that needs cold-start coverage.
    @discardableResult
    func handleContinue(userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }
        print("[Macra][DeepLink.continue] webpageURL=\(url.absoluteString)")
        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
        #endif
        return resolveBuddyToken(from: url)
    }

    /// Custom-scheme entry point (e.g. `macra://buddy/<token>`) — invoked
    /// from `MacraAppDelegate.application(_:open:)` and SwiftUI's
    /// `.onOpenURL`. Forwards to AppsFlyer first so attribution still
    /// reports, then routes the buddy token locally.
    @discardableResult
    func handleOpen(url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        print("[Macra][DeepLink.open] url=\(url.absoluteString)")
        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().handleOpen(url, options: options)
        #endif
        return resolveBuddyToken(from: url)
    }

    /// Pulled out so the hot path stays terse and AppsFlyer's resolved
    /// payload (which arrives via `DeepLinkDelegate`) and the raw URL
    /// path can share extraction.
    @discardableResult
    private func resolveBuddyToken(from url: URL) -> Bool {
        guard let token = BuddyURLParser.token(from: url.absoluteString) else {
            print("[Macra][DeepLink.resolve] no buddy token in url=\(url.absoluteString)")
            return false
        }
        print("[Macra][DeepLink.resolve] buddy token=\(token)")
        DispatchQueue.main.async { [weak self] in
            self?.pendingInviteToken = token
        }
        return true
    }

    /// Cleared by the UI after the invite has been presented + accepted
    /// (or dismissed). Stops the same token from re-prompting.
    func clearPendingInvite() {
        pendingInviteToken = nil
    }

    // MARK: - Share URL generation

    /// Async resolver for the share URL the inviter sends to a friend.
    /// Uses the first-party universal-link domain while AppsFlyer's AASA
    /// file is empty. Once `macra.onelink.me` is associated with Macra,
    /// flip `useAppsFlyerOneLinkForBuddyInvites` to restore short OneLink
    /// generation and install attribution.
    ///
    /// Falls back to the long-form `BuddyInvite.shareURL` when:
    /// - The AppsFlyer SDK isn't on the target yet (`canImport` guard)
    /// - The shortener returns nil (e.g. SDK not yet `start()`-ed,
    ///   network blocked, OneLink template misconfigured)
    /// Either way the completion is called exactly once on the main
    /// queue with a usable URL — share flows never deadlock waiting.
    func shareURL(forToken token: String, completion: @escaping (URL) -> Void) {
        let fallback = BuddyInvite.shareURL(forToken: token)
            ?? URL(string: "https://fitwithpulse.ai/macra/buddy/\(token)")!

        guard Self.useAppsFlyerOneLinkForBuddyInvites else {
            print("[Macra][DeepLink.shareURL] OneLink AASA not associated; serving canonical=\(fallback.absoluteString)")
            DispatchQueue.main.async { completion(fallback) }
            return
        }

        #if canImport(AppsFlyerLib)
        let canonicalURLString = "\(BuddyInvite.canonicalBuddyInviteHost)/macra/buddy/\(token)"
        let appStoreURL = Self.appStoreURL
        let appStoreID = Self.appleAppID
        AppsFlyerShareInviteHelper.generateInviteUrl(linkGenerator: { generator in
            generator.setChannel("buddy_invite")
            generator.setCampaign("buddy_invite")
            // Routing inside the app — `DeepLinkDelegate` checks
            // `deep_link_value == "buddy"` and pulls `buddy_token` from
            // the resolved payload.
            generator.addParameterValue("buddy", forKey: "deep_link_value")
            generator.addParameterValue(token, forKey: "buddy_token")
            // Custom-scheme + App Store fallbacks so a tap from any
            // surface (Safari, iMessage, embedded webview) lands on
            // either the in-app handler or the install path.
            generator.addParameterValue("macra://buddy/\(token)", forKey: "af_dp")
            generator.addParameterValue(appStoreURL, forKey: "af_ios_url")
            generator.addParameterValue(appStoreID, forKey: "af_app_id")
            generator.addParameterValue(canonicalURLString, forKey: "af_r")
            generator.addParameterValue(BuddyInvite.previewTitle, forKey: "af_og_title")
            generator.addParameterValue(BuddyInvite.previewDescription, forKey: "af_og_description")
            generator.addParameterValue(BuddyInvite.previewImageURL, forKey: "af_og_image")
            return generator
        }, completionHandler: { url in
            DispatchQueue.main.async {
                if let url {
                    print("[Macra][DeepLink.shareURL] ✓ short=\(url.absoluteString)")
                    completion(url)
                } else {
                    print("[Macra][DeepLink.shareURL] ⚠️ shortener nil — falling back to long-form")
                    completion(fallback)
                }
            }
        })
        #else
        // SDK not on target yet — caller still gets a working URL.
        print("[Macra][DeepLink.shareURL] AppsFlyer not installed; serving long-form fallback")
        DispatchQueue.main.async { completion(fallback) }
        #endif
    }
}

#if canImport(AppsFlyerLib)
extension MacraDeepLinkService: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        print("[Macra][DeepLink.conversion] keys=\(Array(conversionInfo.keys))")
    }

    func onConversionDataFail(_ error: Error) {
        print("[Macra][DeepLink.conversion] ❌ \(error.localizedDescription)")
    }
}

extension MacraDeepLinkService: DeepLinkDelegate {
    func didResolveDeepLink(_ result: DeepLinkResult) {
        switch result.status {
        case .notFound:
            print("[Macra][DeepLink.resolved] no deep link in this launch")
        case .failure:
            print("[Macra][DeepLink.resolved] ❌ resolve failed: \(result.error?.localizedDescription ?? "unknown")")
        case .found:
            // OneLink campaigns set `deep_link_value` and arbitrary
            // params — buddy invites carry `buddy_token` (with optional
            // `deep_link_value: buddy` for routing).
            let payload = result.deepLink?.clickEvent ?? [:]
            let tokenCandidate = (payload["buddy_token"] as? String)
                ?? (payload["deep_link_sub1"] as? String)
            if let token = tokenCandidate, !token.isEmpty {
                print("[Macra][DeepLink.resolved] buddy_token=\(token)")
                DispatchQueue.main.async { [weak self] in
                    self?.pendingInviteToken = token
                }
            } else if let token = tokenFromResolvedPayload(payload) {
                print("[Macra][DeepLink.resolved] nested buddy token=\(token)")
                DispatchQueue.main.async { [weak self] in
                    self?.pendingInviteToken = token
                }
            } else {
                print("[Macra][DeepLink.resolved] payload had no buddy_token — keys=\(Array(payload.keys))")
            }
        @unknown default:
            print("[Macra][DeepLink.resolved] unknown status")
        }
    }

    private func tokenFromResolvedPayload(_ payload: [AnyHashable: Any]) -> String? {
        for key in ["af_dp", "af_r", "deep_link_value"] {
            if let value = payload[key] as? String,
               let token = BuddyURLParser.token(from: value) {
                return token
            }
        }
        return nil
    }
}
#endif
