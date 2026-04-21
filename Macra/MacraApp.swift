import SwiftUI
import FirebaseCore
import RevenueCat
import UIKit

final class MacraAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseService.configureFirebaseAppIfNeeded()
        return true
    }
}

@main
struct MacraApp: App {
    @UIApplicationDelegateAdaptor(MacraAppDelegate.self) private var appDelegate
    @StateObject private var serviceManager: ServiceManager
    
    
    init() {
        FirebaseService.configureFirebaseAppIfNeeded()
        _serviceManager = StateObject(wrappedValue: ServiceManager())

        Purchases.configure(withAPIKey: "appl_dkVuiAvCaUxSvgfcDhIRLdMdEZh")
        Purchases.logLevel = .info
//        Purchases.logLevel = .verbose //set to info for production
        Purchases.shared.delegate = PurchaseService.sharedInstance
    }
    var body: some Scene {
        WindowGroup {
            ContentView(serviceManager: serviceManager)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .dismissKeyboardOnTapOutside()
        }
    }
}
