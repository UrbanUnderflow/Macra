import Foundation
import Combine
import AppTrackingTransparency
import AdSupport

// Service Manager
class ServiceManager: ObservableObject {
    // Initialize services
    let firebaseService = FirebaseService.sharedInstance
    let userService = UserService.sharedInstance
    let notificationService = NotificationService.sharedInstance
    let purchaseService = PurchaseService.sharedInstance
    let gptService = GPTService.sharedInstance
    let entryService = EntryService.sharedInstance
    let appleSignInService = AppleSignInService.sharedInstance

    
    @Published var isConfigured = false
    
    @Published var showTabBar = false

    func configure() async {
//        do {
//            // Do any other configuration here
//            if self.firebaseService.isAuthenticated {
//                self.userService.getUser { user, error in
//
//                    guard let u = self.userService.user else {
//                        DispatchQueue.main.async {
//                            self.isConfigured = true
//                            self.requestTrackingAuthorization()
//                        }
//
//                        return
//                    }
//                }
//            } else {
//                DispatchQueue.main.async {
//                    self.isConfigured = true
//                    self.requestTrackingAuthorization()
//                }
//            }
//        } catch {
//            print(error)
            // ATT is requested once on first launch. AppsFlyer requires
            // the user's decision before `start()` so the SDK can pick up
            // (or skip) the IDFA without crashing. The
            // `INFOPLIST_KEY_NSUserTrackingUsageDescription` build setting
            // ships the rationale string iOS shows in the prompt.
            self.requestTrackingAuthorization()
//        }
    }
    
    func requestTrackingAuthorization() {
        ATTrackingManager.requestTrackingAuthorization(completionHandler: { status in
            switch status {
            case .authorized:
                print("[Macra][ATT] permission granted")
            case .denied:
                print("[Macra][ATT] permission denied")
            case .notDetermined:
                print("[Macra][ATT] permission not determined")
            case .restricted:
                print("[Macra][ATT] permission restricted")
            @unknown default:
                print("[Macra][ATT] unknown status \(status.rawValue)")
            }
            // Start AppsFlyer regardless of the answer — `start()` is
            // safe to call after either authorize or deny; what changes
            // is whether the SDK has access to the IDFA. Doing this after
            // the prompt rather than at launch is what kept the app
            // from crashing in the previous turn.
            DispatchQueue.main.async {
                MacraDeepLinkService.sharedInstance.startSDK()
            }
        })
    }
}
