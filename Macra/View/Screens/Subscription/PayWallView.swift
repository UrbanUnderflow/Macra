import SwiftUI
import RevenueCat

class PayWallViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator

    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
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
    //                                    HStack {
    //                                        IconImage(.sfSymbol(.upArrow, color: .primaryPurple))
    //                                        Text("Back to plans")
    //                                            .foregroundColor(.primaryPurple)
    //                                    }
    //                                    .onTapGesture {
    //                                        withAnimation {
    //                                            scrollProxy.scrollTo(0, anchor: .top)
    //                                        }
    //                                    }
                                HStack {
                                    IconImage(.sfSymbol(.reload, color: .gray))
                                    Text("Restore Purchases")
                                        .foregroundColor(.gray)
                                }
    //                                                                .onTapGesture {
    //                                                                    PurchaseService.sharedInstance.restorePurchases { result in
    //                                                                        switch result {
    //                                                                        case .success:
    //                                                                            viewModel.appCoordinator.showHomeScreen()
    //                                                                        case .failure(let error):
    //                                                                            print(error)
    //                                                                            viewModel.appCoordinator.showToast(viewModel: ToastViewModel(message: "We were unable to restore your purchase. Please contact support at puppyschoolapp@gmail.com", backgroundColor: .secondaryCharcoal, textColor: .secondaryWhite))
    //                                                                        }
    //                                                                    }
    //                                                                }
                                HStack {
                                    IconImage(.sfSymbol(.privacy, color: .gray))
                                    Text("Privacy Policy")
                                        .foregroundColor(.gray)
                                }
                                .onTapGesture {
                                    viewModel.appCoordinator.showPrivacyScreenModal()
                                }
                                HStack {
                                    IconImage(.sfSymbol(.doc, color: .gray))
                                    Text("Terms of Service")
                                        .foregroundColor(.gray)
                                }
                                .onTapGesture {
    //                                                                    viewModel.appCoordinator.showTermsScreenModal()
                                }
                              //  if BetaService.sharedInstance.betaEligibleUsers.contains(UserService.sharedInstance.user?.email ?? "nothing") {
                                    HStack {
                                        IconImage(.sfSymbol(.doc, color: .gray))
                                        Text("Enroll in Beta")
                                            .foregroundColor(.gray)
                                    }
                                    .onTapGesture {
                                        viewModel.appCoordinator.showHomeScreen()
                                    }
                              //  }
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

struct MacraReviewPaywallScreenshotView: View {
    private let featureChips = [
        "AI meal scan",
        "Macro tracking",
        "Nutrition insights",
        "Meal planning"
    ]

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("MACRA PLUS")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundColor(.primaryGreen)

                        Text("Unlock deeper\nnutrition clarity.")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Track macros, scan meals, build smarter habits, and keep your plan moving every day.")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    MacraAuthChipRow(labels: featureChips)

                    VStack(spacing: 14) {
                        MacraReviewPlanCard(
                            accent: .primaryGreen,
                            tint: .primaryGreen,
                            badge: "Most Popular",
                            title: "Annual",
                            subtitle: "A full year of Macra Plus",
                            price: "$79.99",
                            cadence: "per year",
                            supportingLine: "Best value for everyday tracking"
                        )

                        MacraReviewPlanCard(
                            accent: .primaryBlue,
                            tint: .primaryBlue,
                            badge: "Flexible",
                            title: "Monthly",
                            subtitle: "Stay consistent month to month",
                            price: "$12.99",
                            cadence: "per month",
                            supportingLine: "Start anytime, cancel anytime"
                        )
                    }

                    MacraGlassCard(accent: .white, tint: .white, tintOpacity: 0.04) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primaryGreen)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Includes the full Macra nutrition experience")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)

                                Text("Meal logging, AI meal analysis, macro targets, planning, and premium nutrition insights.")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.white.opacity(0.68))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    HStack(spacing: 14) {
                        MacraReviewFooterPill(label: "Restore Purchases")
                        MacraReviewFooterPill(label: "Terms")
                        MacraReviewFooterPill(label: "Privacy")
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct MacraReviewPlanCard: View {
    let accent: Color
    let tint: Color
    let badge: String
    let title: String
    let subtitle: String
    let price: String
    let cadence: String
    let supportingLine: String

    var body: some View {
        MacraGlassCard(accent: accent, tint: tint, tintOpacity: 0.08) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(badge.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())

                    Text(title)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.68))

                    Text(supportingLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.54))
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(price)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text(cadence)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.62))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

private struct MacraReviewFooterPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}
