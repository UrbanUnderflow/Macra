import SwiftUI
import RevenueCat

class PayWallViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator
    
    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }
    
    func checkSubscriptionStatus(completion: @escaping (Bool) -> Void) {
        PurchaseService.sharedInstance.checkSubscriptionStatus { [weak self] (result) in
            switch result {
            case .success(let isSubscribed):
                if isSubscribed {
                    self?.appCoordinator.showNotificationModal(viewModel: CustomModalViewModel(type: .confirmation, title: "Cancel your subscription", message: "You currently have an active subscription, make sure you cancel your subscription from your iPhone's Settings app under your Profile -> Subscriptions or it will renew automatically despite buying your Lifetime plan", primaryButtonTitle: "OK", secondaryButtonTitle: "Cancel", primaryAction: { message in
                        completion(true)
                    }, secondaryAction: {
                        completion(false)
                    }))
                } else {
                    completion(true)
                }
            case .failure(let error):
                self?.appCoordinator.showNotificationModal(viewModel: CustomModalViewModel(type: .confirmation, title: "Subscription attempt failed", message: "\(error.localizedDescription). You were not charged.", primaryButtonTitle: "OK", secondaryButtonTitle: "Cancel", primaryAction: { message in
                    completion(false)
                }))
            }
        }
    }

}

struct PayWallView: View {
    var offeringViewModel = PurchaseService.sharedInstance.offering
    @ObservedObject var viewModel: PayWallViewModel
    
    var body: some View {
        VStack {
            HeaderView(viewModel: HeaderViewModel(headerTitle: "", type: .close, closeModal: {
                viewModel.appCoordinator.closeModals()
            }, actionCallBack: {
                //
            }))
            ScrollView {
                VStack(spacing: 0) {
                    Rectangle()
                        .frame(height: 350)
                        .foregroundColor(.white)
                    ZStack {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.black)
                                .ignoresSafeArea(.all)
                            Rectangle()
                                .fill(Color.white)
                                .ignoresSafeArea(.all)
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                if let package = offeringViewModel.yearlyPackage {
                                    
                                    PackageCardView(badgeLabel: "Best Value", title: "Annual Pro Plan", subtitle: "The best trainig app for your new puppy with all our pro features.", breakDownPrice: "About $6 per month", billPrice: "$79.99 billed annually", bottomLabel: "Most popular plan", buttonTitle: "Get 7 day Trial w/ Annual", package: package, offeringViewModel: offeringViewModel) {
                                        
                                        self.offeringViewModel.purchase(package) { result in
                                            switch result {
                                            case .success:
                                                print("Success")
                                                viewModel.appCoordinator.closeModals()
                                            case .failure(let error):
                                                print("There was an error while purchasing \(error)")
                                            }
                                        }
                                    }
                                }
                                if let package = offeringViewModel.monthlyPackage {
                                    PackageCardView(badgeLabel: "Most Flexible", title: "Monthly Pro Plan", subtitle: "Flexible, great for dogs that just need a bit of extra training.", breakDownPrice: "12.99 /month", billPrice: "Billed monthly", bottomLabel: "Great for limited training", buttonTitle: "Get Monthly", package: package, offeringViewModel: offeringViewModel) {
                                        
                                        self.offeringViewModel.purchase(package) { result in
                                            switch result {
                                            case .success:
                                                print("Success")
                                                viewModel.appCoordinator.closeModals()
                                            case .failure(let error):
                                                print("There was an error while purchasing \(error)")
                                            }
                                        }
                                    }
                                }
                                if let package = offeringViewModel.lifetimePackage {
                                    PackageCardView(badgeLabel: "Pay Once", title: "Lifetime", subtitle: "Pay once and get access to top notch dog training, forever!", breakDownPrice: "$249", billPrice: "Ont-Time Purchase", bottomLabel: "No subscription", buttonTitle: "Get Lifetime", package: package, offeringViewModel: offeringViewModel) {
                                        
                                        //check the status of subscription before moving forwad with this purchase
                                        viewModel.checkSubscriptionStatus { isPermitted in
                                            if isPermitted == true {
                                                self.viewModel.appCoordinator.hideNotification()
                                                
                                                self.offeringViewModel.purchase(package) { result in
                                                    switch result {
                                                    case .success:
                                                        print("Success")
                                                        viewModel.appCoordinator.closeModals()
                                                    case .failure(let error):
                                                        print("There was an error while purchasing \(error)")
                                                    }
                                                }
                                            }
                                        }
                                        
                                    }
                                }
                            }
                            .padding(.horizontal, 8) // Add padding to the HStack to center the cards
                        }
                        .frame(height: 400) // Set a fixed height for the ScrollView
                    }
                    .padding(.bottom, 50)
                    
                    PreviewCardView()
                    
                    Spacer()
                        .frame(height: 50)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Back to plans")
                                    .foregroundColor(.black)
                            }
                            .onTapGesture {
                                //scroll to the top
                            }
                            HStack {
                                Text("Restore Purchases")
                                    .foregroundColor(.gray)
                            }
                            .onTapGesture {
                                //restore
                            }
                            HStack {
                                Text("Privacy Policy")
                                    .foregroundColor(.gray)
                            }
                            .onTapGesture {
                                //open privacy policy
                            }
                            HStack {
                                Text("Terms of Service")
                                    .foregroundColor(.gray)
                            }
                            .onTapGesture {
                                //open terms
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.bottom, 50)
                        Spacer()
                    }
                    
                    
                }
            }
            .ignoresSafeArea(.all)
        }
    }
}

struct PayWallView_Previews: PreviewProvider {
    static var previews: some View {
        PayWallView(viewModel: PayWallViewModel(appCoordinator: AppCoordinator(serviceManager: ServiceManager())))
    }
}
