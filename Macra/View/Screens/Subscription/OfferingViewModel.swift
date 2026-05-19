import Foundation
import RevenueCat
import StoreKit

enum PurchaseResult {
    case success
    case failure(Error)
}

enum MacraPurchaseFlowBlockReason: String, Equatable {
    case plansLoading = "plans_loading"
    case packageLoadError = "package_load_error"
    case selectedPlanMissing = "selected_plan_missing"
}

struct MacraPurchaseFlowInput {
    let isPurchasing: Bool
    let isDemoMode: Bool
    let usesLivePurchasesInDemo: Bool
    let hasExistingSubscriptionAccess: Bool
    let isLoadingPackages: Bool
    let packageLoadError: String?
    let selectedPlan: SubscriptionPlanOption?
}

enum MacraPurchaseFlowDecision {
    case ignoreAlreadyPurchasing
    case continueDemoAccess
    case continueExistingAccess
    case blocked(reason: MacraPurchaseFlowBlockReason, message: String)
    case purchase(SubscriptionPlanOption)
}

struct MacraPurchaseFlowResolver {
    static func decision(for input: MacraPurchaseFlowInput) -> MacraPurchaseFlowDecision {
        if input.isPurchasing {
            return .ignoreAlreadyPurchasing
        }

        if input.isDemoMode && !input.usesLivePurchasesInDemo {
            return .continueDemoAccess
        }

        if input.hasExistingSubscriptionAccess {
            return .continueExistingAccess
        }

        if input.isLoadingPackages {
            return .blocked(
                reason: .plansLoading,
                message: "Plans are still loading. Please try again in a moment."
            )
        }

        if let packageLoadError = input.packageLoadError, !packageLoadError.isEmpty {
            return .blocked(reason: .packageLoadError, message: packageLoadError)
        }

        guard let selectedPlan = input.selectedPlan else {
            return .blocked(
                reason: .selectedPlanMissing,
                message: "Plans are still loading. Please try again in a moment."
            )
        }

        return .purchase(selectedPlan)
    }
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
        case .year: return "\(localizedPriceString)/yr"
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
        await start(source: "subscription_offering")
    }

    func start(source: String) async {
        guard !isLoadingPackages else { return }

        isLoadingPackages = true
        packageLoadError = nil
        packageViewModel = []
        monthlyPackage = nil
        yearlyPackage = nil
        localPlanViewModel = []
        MacraAnalyticsService.shared.trackSubscriptionPlansLoadStarted(source: source)
        logPlanLoad("Starting RevenueCat offerings fetch. source=\(source)")

        defer {
            isLoadingPackages = false
        }

        do {
            let offerings = try await Purchases.shared.offerings()
            let currentOfferingIdentifier = offerings.current?.identifier
            let availablePackages = offerings.current?.availablePackages ?? []
            let packages = availablePackages.filter(packageIsSupported)
            let packageIdentifiers = availablePackages.map(\.identifier)
            let productIdentifiers = availablePackages.map(\.storeProduct.productIdentifier)
            logPlanLoad(
                """
                RevenueCat offerings fetched. source=\(source) current=\(currentOfferingIdentifier ?? "none") \
                available=\(availablePackages.count) supported=\(packages.count) \
                packageIDs=\(packageIdentifiers.joined(separator: ", ")) \
                productIDs=\(productIdentifiers.joined(separator: ", "))
                """
            )

            if availablePackages.isEmpty {
                let reason = offerings.current == nil ? "no_current_offering" : "current_offering_empty"
                packageLoadError = "Unable to load subscription plans. Please try again."
                MacraAnalyticsService.shared.trackSubscriptionPlansLoadFailed(
                    source: source,
                    reason: reason,
                    currentOfferingIdentifier: currentOfferingIdentifier,
                    availablePackageCount: availablePackages.count,
                    supportedPackageCount: packages.count,
                    packageIdentifiers: packageIdentifiers,
                    productIdentifiers: productIdentifiers
                )
                return
            } else if packages.isEmpty {
                let returnedIDs = availablePackages
                    .map { "\($0.identifier) / \($0.storeProduct.productIdentifier)" }
                    .joined(separator: ", ")
                packageLoadError = "Unable to load subscription plans. Please try again."
                MacraAnalyticsService.shared.trackSubscriptionPlansLoadFailed(
                    source: source,
                    reason: "unsupported_revenuecat_packages",
                    currentOfferingIdentifier: currentOfferingIdentifier,
                    availablePackageCount: availablePackages.count,
                    supportedPackageCount: packages.count,
                    packageIdentifiers: packageIdentifiers,
                    productIdentifiers: productIdentifiers
                )
                logPlanLoad("RevenueCat returned packages, but none match Macra's supported IDs. Returned: \(returnedIDs)")
                return
            }

            packageViewModel = packages.map(PackageViewModel.init(package:))
            // find monthly and yearly packages
            monthlyPackage = packageViewModel.first(where: { $0.package.storeProduct.subscriptionPeriod?.unit == .month })
            yearlyPackage = packageViewModel.first(where: { $0.package.storeProduct.subscriptionPeriod?.unit == .year })
            packageLoadError = nil
            MacraAnalyticsService.shared.trackSubscriptionPlansLoaded(
                source: source,
                currentOfferingIdentifier: currentOfferingIdentifier,
                availablePackageCount: availablePackages.count,
                supportedPackageCount: packages.count,
                packageIdentifiers: packageIdentifiers,
                productIdentifiers: productIdentifiers
            )
        } catch {
            packageLoadError = "Unable to load subscription plans. Please try again."
            MacraAnalyticsService.shared.trackSubscriptionPlansLoadFailed(
                source: source,
                reason: "revenuecat_offerings_error",
                currentOfferingIdentifier: nil,
                availablePackageCount: 0,
                supportedPackageCount: 0,
                packageIdentifiers: [],
                productIdentifiers: [],
                error: error
            )
            logPlanLoad("Unable to fetch RevenueCat offerings. source=\(source) error=\(error)")
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

    private func logPlanLoad(_ message: String) {
        print("[Macra][Subscriptions][Plans] \(message)")
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
