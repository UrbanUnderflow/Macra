import SwiftUI
import FirebaseCore
import RevenueCat


@main
struct MacraApp: App {
    @StateObject private var serviceManager = ServiceManager()
    
    
    init() {
        Purchases.configure(withAPIKey: "appl_dkVuiAvCaUxSvgfcDhIRLdMdEZh")
        Purchases.logLevel = .info
//        Purchases.logLevel = .verbose //set to info for production
        Purchases.shared.delegate = serviceManager.purchaseService
    }
    var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView(serviceManager: serviceManager)
            }
        }
    }
}
