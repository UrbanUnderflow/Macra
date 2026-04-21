import Foundation
import RevenueCat
import StoreKit

enum PurchaseResult {
    case success
    case failure(Error)
}

enum SubscriptionPlanPeriodKind: Int {
    case year = 1
    case month = 2
    case week = 3
    case day = 4
    case unknown = 98
}

struct LocalSubscriptionPlanViewModel: Identifiable {
    let id: String
    let displayTitle: String
    let localizedPriceString: String
    let price: Decimal
    let periodKind: SubscriptionPlanPeriodKind
    let trialDays: Int?
    let product: Product?

    var billingNote: String {
        switch periodKind {
        case .day: return "Billed daily"
        case .week: return "Billed weekly"
        case .month: return "Billed monthly"
        case .year: return "\(localizedPriceString) billed annually"
        case .unknown: return ""
        }
    }

    var perPeriodDisplay: String {
        switch periodKind {
        case .year:
            let perMonth = NSDecimalNumber(decimal: price).doubleValue / 12.0
            return String(format: "$%.2f/mo", perMonth)
        case .month: return "\(localizedPriceString)/mo"
        case .week: return "\(localizedPriceString)/wk"
        case .day: return "\(localizedPriceString)/day"
        case .unknown: return localizedPriceString
        }
    }
}

enum SubscriptionPlanOption: Identifiable {
    case revenueCat(PackageViewModel)
    case local(LocalSubscriptionPlanViewModel)

    var id: String {
        switch self {
        case .revenueCat(let package): return package.id
        case .local(let plan): return plan.id
        }
    }

    var packageViewModel: PackageViewModel? {
        guard case .revenueCat(let package) = self else { return nil }
        return package
    }

    var displayTitle: String {
        switch self {
        case .revenueCat(let package): return package.displayTitle
        case .local(let plan): return plan.displayTitle
        }
    }

    var perPeriodDisplay: String {
        switch self {
        case .revenueCat(let package): return package.perPeriodDisplay
        case .local(let plan): return plan.perPeriodDisplay
        }
    }

    var billingNote: String {
        switch self {
        case .revenueCat(let package): return package.billingNote
        case .local(let plan): return plan.billingNote
        }
    }

    var periodKind: SubscriptionPlanPeriodKind {
        switch self {
        case .revenueCat(let package): return package.subscriptionPeriodKind
        case .local(let plan): return plan.periodKind
        }
    }

    var price: Decimal {
        switch self {
        case .revenueCat(let package): return package.package.storeProduct.price
        case .local(let plan): return plan.price
        }
    }

    var priceLabel: String {
        switch self {
        case .revenueCat(let package): return package.price
        case .local(let plan): return plan.localizedPriceString
        }
    }

    var trialDays: Int? {
        switch self {
        case .revenueCat(let package): return package.trialDays
        case .local(let plan): return plan.trialDays
        }
    }
}

@MainActor
final class OfferingViewModel: ObservableObject, OfferingViewModelProtocol {
    
    static let sharedInstance = OfferingViewModel()

    @Published private(set) var packageViewModel: [PackageViewModel] = []
    @Published private(set) var monthlyPackage: PackageViewModel?
    @Published private(set) var yearlyPackage: PackageViewModel?
    @Published private(set) var isLoadingPackages = false
    @Published private(set) var packageLoadError: String?
    @Published private(set) var localPlanViewModel: [LocalSubscriptionPlanViewModel] = []

    var sortedPackages: [PackageViewModel] {
        return packageViewModel.sorted { $0.subscriptionPeriodKind.rawValue < $1.subscriptionPeriodKind.rawValue }
    }

    var sortedLocalPlans: [LocalSubscriptionPlanViewModel] {
        return localPlanViewModel.sorted { $0.periodKind.rawValue < $1.periodKind.rawValue }
    }

    var planOptions: [SubscriptionPlanOption] {
        if !packageViewModel.isEmpty {
            return sortedPackages.map(SubscriptionPlanOption.revenueCat)
        }

        return sortedLocalPlans.map(SubscriptionPlanOption.local)
    }

    func start() async {
        guard !isLoadingPackages else { return }

        isLoadingPackages = true
        packageLoadError = nil

        defer {
            isLoadingPackages = false
        }

        do {
            let offerings = try await Purchases.shared.offerings()
            let availablePackages = offerings.current?.availablePackages ?? []
            let packages = availablePackages.filter(packageIsSupported)
            localPlanViewModel = []

            if availablePackages.isEmpty {
                packageLoadError = "No subscription plans came back from RevenueCat. Check the default offering."
            } else if packages.isEmpty {
                let returnedIDs = availablePackages
                    .map { "\($0.identifier) / \($0.storeProduct.productIdentifier)" }
                    .joined(separator: ", ")
                packageLoadError = "RevenueCat returned plans, but none matched rc_monthly or rc_annual. Returned: \(returnedIDs)"
            }

            guard !packages.isEmpty else {
                await loadStoreKitFallbackPlans()
                return
            }

            packageViewModel = packages.map(PackageViewModel.init(package:))
            // find monthly and yearly packages
            monthlyPackage = packageViewModel.first(where: { $0.package.storeProduct.subscriptionPeriod?.unit == .month })
            yearlyPackage = packageViewModel.first(where: { $0.package.storeProduct.subscriptionPeriod?.unit == .year })
        } catch {
            await loadStoreKitFallbackPlans()
            print("Unable to Fetch Offerings \(error)")
        }
    }

    private func packageIsSupported(_ package: Package) -> Bool {
        let packageIdentifier = package.identifier
        let productIdentifier = package.storeProduct.productIdentifier
        let normalizedPackageIdentifier = packageIdentifier.hasPrefix("$")
            ? String(packageIdentifier.dropFirst())
            : packageIdentifier
        let supportedIdentifiers = MacraRevenueCatProducts.supportedOfferingIdentifiers

        return supportedIdentifiers.contains(packageIdentifier) ||
            supportedIdentifiers.contains(normalizedPackageIdentifier) ||
            MacraRevenueCatProducts.supportedSubscriptionIdentifiers.contains(productIdentifier)
    }

    private func loadStoreKitFallbackPlans() async {
#if DEBUG
        let productIDs = Array(MacraRevenueCatProducts.supportedSubscriptionIdentifiers)

        do {
            let products = try await Product.products(for: productIDs)
            let productPlans = products.map(LocalSubscriptionPlanViewModel.init(product:))

            if productPlans.isEmpty {
                localPlanViewModel = Self.staticFallbackPlans()
                packageLoadError = nil
                return
            }

            localPlanViewModel = productPlans
            packageLoadError = nil
        } catch {
            localPlanViewModel = Self.staticFallbackPlans()
            packageLoadError = nil
            print("Unable to Fetch StoreKit fallback products \(error)")
        }
#else
        packageLoadError = "Unable to load subscription plans. Please try again."
#endif
    }

    private static func staticFallbackPlans() -> [LocalSubscriptionPlanViewModel] {
        return [
            LocalSubscriptionPlanViewModel(
                id: "rc_annual",
                displayTitle: "Annual",
                localizedPriceString: "$39.99",
                price: Decimal(39.99),
                periodKind: .year,
                trialDays: 3,
                product: nil
            ),
            LocalSubscriptionPlanViewModel(
                id: "rc_monthly",
                displayTitle: "Monthly",
                localizedPriceString: "$4.99",
                price: Decimal(4.99),
                periodKind: .month,
                trialDays: 3,
                product: nil
            )
        ]
    }
    
    func purchase(_ viewmodel: PackageViewModel, completion: @escaping (PurchaseResult) -> Void) {
        Task {
            do {
                let purchased = try await Purchases.shared.purchase(package: viewmodel.package)
                if purchased.userCancelled {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "Purchase Canceled", code: -1)))
                    }
                    return
                }

                DispatchQueue.main.async {
                    completion(.success)
                }
            } catch {
                let productIdentifier = viewmodel.package.storeProduct.productIdentifier
                if PurchaseService.sharedInstance.isInvalidReceiptError(error),
                   await PurchaseService.sharedInstance.storeKitHasSubscriptionAccess(matching: [productIdentifier]) {
                    PurchaseService.sharedInstance.acceptStoreKitSubscriptionAccess(productIdentifier: productIdentifier)
                    DispatchQueue.main.async {
                        completion(.success)
                    }
                    return
                }

                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func purchase(_ plan: SubscriptionPlanOption, completion: @escaping (PurchaseResult) -> Void) {
        switch plan {
        case .revenueCat(let package):
            purchase(package, completion: completion)
        case .local(let localPlan):
            purchaseLocalPlan(localPlan, completion: completion)
        }
    }

    private func purchaseLocalPlan(_ plan: LocalSubscriptionPlanViewModel, completion: @escaping (PurchaseResult) -> Void) {
        Task {
            do {
                let product: Product?
                if let existingProduct = plan.product {
                    product = existingProduct
                } else {
                    product = try await Product.products(for: [plan.id]).first
                }

                guard let product else {
                    let error = NSError(
                        domain: "StoreKit Configuration",
                        code: -2,
                        userInfo: [
                            NSLocalizedDescriptionKey: "StoreKit could not find \(plan.id). Make sure the Macra scheme uses MacraProducts.storekit under Run > Options > StoreKit Configuration."
                        ]
                    )
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }

                let result = try await product.purchase()

                switch result {
                case .success(let verification):
                    guard case .verified(let transaction) = verification else {
                        let error = NSError(
                            domain: "StoreKit",
                            code: -3,
                            userInfo: [NSLocalizedDescriptionKey: "The StoreKit transaction could not be verified."]
                        )
                        DispatchQueue.main.async { completion(.failure(error)) }
                        return
                    }

                    await transaction.finish()
                    PurchaseService.sharedInstance.acceptStoreKitSubscriptionAccess(productIdentifier: transaction.productID)
                    DispatchQueue.main.async { completion(.success) }
                case .userCancelled:
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "Purchase Canceled", code: -1)))
                    }
                case .pending:
                    let error = NSError(
                        domain: "StoreKit",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "The purchase is pending approval."]
                    )
                    DispatchQueue.main.async { completion(.failure(error)) }
                @unknown default:
                    let error = NSError(
                        domain: "StoreKit",
                        code: -5,
                        userInfo: [NSLocalizedDescriptionKey: "StoreKit returned an unknown purchase result."]
                    )
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}

@MainActor
protocol OfferingViewModelProtocol {
    var packageViewModel: [PackageViewModel] { get }
    var monthlyPackage: PackageViewModel? { get }
    var yearlyPackage: PackageViewModel? { get }
    var isLoadingPackages: Bool { get }
    var packageLoadError: String? { get }
    var planOptions: [SubscriptionPlanOption] { get }

    func start() async
    func purchase(_ viewmodel: PackageViewModel, completion: @escaping (PurchaseResult) -> Void)
    func purchase(_ plan: SubscriptionPlanOption, completion: @escaping (PurchaseResult) -> Void)
}

extension PackageViewModel {
    var subscriptionPeriodKind: SubscriptionPlanPeriodKind {
        switch subscriptionPeriodUnit {
        case .year: return .year
        case .month: return .month
        case .week: return .week
        case .day: return .day
        default: return .unknown
        }
    }

    var trialDays: Int? {
        guard let discount = package.storeProduct.introductoryDiscount,
              discount.paymentMode == .freeTrial else {
            return nil
        }

        switch discount.subscriptionPeriod.unit {
        case .day: return discount.subscriptionPeriod.value
        case .week: return discount.subscriptionPeriod.value * 7
        case .month: return discount.subscriptionPeriod.value * 30
        case .year: return discount.subscriptionPeriod.value * 365
        @unknown default: return nil
        }
    }
}

private extension LocalSubscriptionPlanViewModel {
    init(product: Product) {
        let periodKind = product.subscription?.subscriptionPeriod.periodKind ?? .unknown
        self.init(
            id: product.id,
            displayTitle: periodKind.displayTitle,
            localizedPriceString: product.displayPrice,
            price: product.price,
            periodKind: periodKind,
            trialDays: product.subscription?.introductoryOffer?.trialDays,
            product: product
        )
    }
}

private extension Product.SubscriptionPeriod {
    var periodKind: SubscriptionPlanPeriodKind {
        switch unit {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        @unknown default: return .unknown
        }
    }
}

private extension Product.SubscriptionOffer {
    var trialDays: Int? {
        guard paymentMode == .freeTrial else { return nil }

        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }
}

private extension SubscriptionPlanPeriodKind {
    var displayTitle: String {
        switch self {
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Annual"
        case .unknown: return "Plan"
        }
    }
}
