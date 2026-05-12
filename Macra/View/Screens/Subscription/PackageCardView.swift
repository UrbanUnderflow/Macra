//
//  PackageCardView.swift
//  Macra
//
//  Created by Tremaine Grant on 8/24/23.
//

import SwiftUI
import RevenueCat

struct PackageCardView: View {
    var badgeLabel: String
    var title: String
    var subtitle: String
    var breakDownPrice: String
    var billPrice: String
    var bottomLabel: String
    var buttonTitle: String
    
    var package: PackageViewModelProtocol
    var offeringViewModel: OfferingViewModelProtocol
    
    var onPurchase: () -> Void
    
    var body: some View {
        VStack {
            HStack {
                VStack {
                    Text(badgeLabel)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }

                .padding(.top)
                .padding(.leading)
                
                Spacer()
            }
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    Text(title)
                        .font(.title2)
                    
                    Text(subtitle)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 10)
                    
                    Text(breakDownPrice)
                        .font(.headline)
                        .bold()
                    Text(billPrice)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    ConfirmationButton(title: buttonTitle, type: .primaryLargeConfirmation) {
                        onPurchase()
                    }
                    .padding(.horizontal)
                    Text(bottomLabel)
                        .padding(.bottom)
                    
                    Spacer()
                }
                .background(CardBackground(color: .secondaryWhite))
                .frame(width: 360, height: 400)
                .padding(.horizontal, 1)
            }
        }
    }
}

struct MockPackage: PackageViewModelProtocol {
    var id: String
    
    var title: String?
    
    var price: String
}

struct MockOfferingViewModel: OfferingViewModelProtocol {
    var packageViewModel: [PackageViewModel]

    var monthlyPackage: PackageViewModel?

    var yearlyPackage: PackageViewModel?

    var isLoadingPackages: Bool = false

    var packageLoadError: String?

    var planOptions: [SubscriptionPlanOption] = []

    func start() async {

    }
    
    func purchase(_ viewmodel: PackageViewModel, completion: @escaping (PurchaseResult) -> Void) {
        
    }

    func purchase(_ plan: SubscriptionPlanOption, completion: @escaping (PurchaseResult) -> Void) {

    }
}

struct PackageCardView_Previews: PreviewProvider {
    static var previews: some View {
        PackageCardView(
            badgeLabel: "Best Value",
            title: "Annual Pro Plan",
            subtitle: "A full year of Macra Pro with premium nutrition features.",
            breakDownPrice: "Price from App Store",
            billPrice: "Billed by App Store",
            bottomLabel: "Most popular plan",
            buttonTitle: "Get Annual",
            package: MockPackage(id: "preview", title: "Annual", price: ""),
            offeringViewModel: MockOfferingViewModel(packageViewModel: [])) {
        }
    }
}
