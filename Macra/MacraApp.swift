import SwiftUI
import FirebaseCore
import FirebaseMessaging
import RevenueCat
import UIKit

private func persistMacraPushRegistrationToken(_ token: String?) {
    guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines),
          !token.isEmpty else { return }

    UserService.sharedInstance.saveMacraPushToken(token)
}

final class MacraAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseService.configureFirebaseAppIfNeeded()
        Messaging.messaging().delegate = self

        // AppsFlyer must be configured synchronously, BEFORE any cold-start
        // universal link can land on `application(_:continue:)` — otherwise
        // the SDK has no dev key when iOS delivers the URL and silently
        // drops the resolution. Property assignments only here; actual
        // network start happens after the ATT decision (handled in
        // ServiceManager.requestTrackingAuthorization).
        MacraDeepLinkService.sharedInstance.configure()
        MacraAnalyticsService.shared.configureTikTokSDK()
        Task { @MainActor in
            MacraNoraVoiceService.shared.preloadOnboardingNarrations()
        }

        // Cold-start universal link — when iOS launches the app from a
        // Safari tap on `applinks:fitwithpulse.ai/macra/buddy/...`, the
        // userActivity is delivered here in `launchOptions` rather than
        // through `application(_:continue:)`. Forward it so the token
        // is captured before the UI mounts.
        if let activityDict = launchOptions?[.userActivityDictionary] as? [AnyHashable: Any] {
            for value in activityDict.values {
                if let userActivity = value as? NSUserActivity {
                    MacraDeepLinkService.sharedInstance.handleContinue(userActivity: userActivity)
                    break
                }
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, error in
            if let error = error {
                print("MacraAppDelegate: failed to fetch Macra FCM token - \(error.localizedDescription)")
                return
            }
            persistMacraPushRegistrationToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("MacraAppDelegate: failed to register for remote notifications - \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        MacraDeepLinkService.sharedInstance.handleContinue(userActivity: userActivity)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        MacraDeepLinkService.sharedInstance.handleOpen(url: url, options: options)
    }
}

extension MacraAppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        persistMacraPushRegistrationToken(fcmToken)
    }
}

@main
struct MacraApp: App {
    @UIApplicationDelegateAdaptor(MacraAppDelegate.self) private var appDelegate
    @StateObject private var serviceManager: ServiceManager
    
    
    init() {
        FirebaseService.configureFirebaseAppIfNeeded()
        MacraPaywallExperimentService.prefetch()
        _serviceManager = StateObject(wrappedValue: ServiceManager())

        Purchases.configure(withAPIKey: "appl_deKHiupBtyyZDtXuMcXhlwoVdXt")
        Purchases.logLevel = .info
//        Purchases.logLevel = .verbose //set to info for production
        Purchases.shared.delegate = PurchaseService.sharedInstance
    }
    var body: some Scene {
        WindowGroup {
            ContentView(serviceManager: serviceManager)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .dismissKeyboardOnTapOutside()
                .onOpenURL { url in
                    MacraDeepLinkService.sharedInstance.handleOpen(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    MacraDeepLinkService.sharedInstance.handleContinue(userActivity: userActivity)
                }
        }
    }
}
