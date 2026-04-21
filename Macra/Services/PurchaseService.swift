import Foundation
import Combine
import FirebaseCore
import RevenueCat
import StoreKit

enum CustomError: Error {
    case noPurchaserInfo
    case unknownError
    
    var localizedDescription: String {
        switch self {
        case .noPurchaserInfo:
            return "No purchaser info available"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

enum MacraRevenueCatProducts {
    static let supportedSubscriptionIdentifiers: Set<String> = [
        "rc_monthly",
        "rc_annual"
    ]

    static let supportedOfferingIdentifiers: Set<String> = {
        var identifiers = supportedSubscriptionIdentifiers
        identifiers.formUnion(supportedSubscriptionIdentifiers.map { "$\($0)" })
        return identifiers
    }()
}

final class PurchaseService: NSObject, PurchasesDelegate, ObservableObject {
    
    static let sharedInstance = PurchaseService()
    @MainActor let offering = OfferingViewModel.sharedInstance

    @Published private(set) var isSubscribed = false

    private let entitlementIdentifier = "plus"
    private var locallyConfirmedStoreKitProductIdentifiers: Set<String> = []
    
    var subscribedPublisher: AnyPublisher<Bool, Never> {
        $isSubscribed.eraseToAnyPublisher()
    }

    private var userServiceIfFirebaseConfigured: UserService? {
        guard FirebaseApp.app() != nil else { return nil }
        return UserService.sharedInstance
    }

    private var localUserHasSubscriptionAccess: Bool {
        guard let userService = userServiceIfFirebaseConfigured else { return false }
        return userService.user?.subscriptionType.grantsMacraAccess == true || userService.isBetaUser
    }

    private func setSubscribed(_ isSubscribed: Bool) {
        DispatchQueue.main.async {
            self.isSubscribed = isSubscribed
            self.userServiceIfFirebaseConfigured?.isSubscribed = isSubscribed
        }
    }

    func resetSubscriptionStatus() {
        setSubscribed(false)
    }

    private func revenueCatHasSubscriptionAccess(_ customerInfo: CustomerInfo) -> Bool {
        let hasActiveEntitlement =
            customerInfo.entitlements.all[entitlementIdentifier]?.isActive == true ||
            customerInfo.entitlements[entitlementIdentifier]?.isActive == true
        let hasKnownActiveSubscription = !customerInfo.activeSubscriptions.intersection(MacraRevenueCatProducts.supportedSubscriptionIdentifiers).isEmpty
        let hasAnyActiveSubscription = !customerInfo.activeSubscriptions.isEmpty
        let latestExpirationIsFuture = customerInfo.latestExpirationDate.map { $0 > Date() } ?? false

        return hasActiveEntitlement || hasKnownActiveSubscription || hasAnyActiveSubscription || latestExpirationIsFuture
    }

    private func activeStoreKitProductIdentifiers(matching productIdentifiers: Set<String>? = nil) -> Set<String> {
        let localIdentifiers = MacraRevenueCatProducts.supportedSubscriptionIdentifiers
            .union(locallyConfirmedStoreKitProductIdentifiers)
        return productIdentifiers ?? localIdentifiers
    }

    private func transactionGrantsAccess(_ transaction: StoreKit.Transaction, productIdentifiers: Set<String>) -> Bool {
        guard productIdentifiers.contains(transaction.productID) else { return false }
        guard transaction.revocationDate == nil else { return false }

        if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
            return false
        }

        return true
    }

    func storeKitHasSubscriptionAccess(matching productIdentifiers: Set<String>? = nil) async -> Bool {
        let identifiers = activeStoreKitProductIdentifiers(matching: productIdentifiers)
        guard !identifiers.isEmpty else { return false }

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transactionGrantsAccess(transaction, productIdentifiers: identifiers) { return true }
        }

        for productID in identifiers {
            guard let result = await StoreKit.Transaction.latest(for: productID),
                  case .verified(let transaction) = result,
                  transactionGrantsAccess(transaction, productIdentifiers: identifiers) else {
                continue
            }
            return true
        }

        return false
    }

    func acceptStoreKitSubscriptionAccess(productIdentifier: String) {
        locallyConfirmedStoreKitProductIdentifiers.insert(productIdentifier)
        setSubscribed(true)
    }

    private func completeSubscriptionCheck(
        customerInfo: CustomerInfo?,
        error: Error?,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        let localUserHasAccess = localUserHasSubscriptionAccess

        if let customerInfo {
            let hasRevenueCatAccess = revenueCatHasSubscriptionAccess(customerInfo)
            if hasRevenueCatAccess || localUserHasAccess {
                setSubscribed(true)
                completion(.success(true))
                return
            }
        } else if localUserHasAccess {
            setSubscribed(true)
            completion(.success(true))
            return
        }

        let hasCustomerInfo = customerInfo != nil
        Task {
            if await self.storeKitHasSubscriptionAccess() {
                setSubscribed(true)
                completion(.success(true))
                return
            }

            setSubscribed(false)

            if hasCustomerInfo {
                completion(.success(false))
            } else if let error {
                completion(.failure(error))
            } else {
                completion(.failure(CustomError.noPurchaserInfo))
            }
        }
    }

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        let revenueCatHasAccess = revenueCatHasSubscriptionAccess(customerInfo)
        setSubscribed(revenueCatHasAccess || localUserHasSubscriptionAccess)
    }

    func checkSubscriptionStatus(forceRefresh: Bool = false, completion: @escaping (Result<Bool, Error>) -> Void) {
        if forceRefresh {
            Purchases.shared.invalidateCustomerInfoCache()
        }

        Purchases.shared.getCustomerInfo { (purchaserInfo, error) in
            self.completeSubscriptionCheck(customerInfo: purchaserInfo, error: error, completion: completion)
        }
    }

    func syncSubscriptionStatus(completion: @escaping (Result<Bool, Error>) -> Void) {
        Purchases.shared.invalidateCustomerInfoCache()
        Purchases.shared.syncPurchases { customerInfo, error in
            self.completeSubscriptionCheck(customerInfo: customerInfo, error: error, completion: completion)
        }
    }

    func restoreSubscriptionStatus(completion: @escaping (Result<Bool, Error>) -> Void) {
        Purchases.shared.invalidateCustomerInfoCache()
        Purchases.shared.restorePurchases { customerInfo, error in
            self.completeSubscriptionCheck(customerInfo: customerInfo, error: error, completion: completion)
        }
    }

    func isAlreadySubscribedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let messageParts = [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion
        ]

        let message = messageParts.compactMap { $0 }.joined(separator: " ").lowercased()
        return message.contains("already subscribed") || message.contains("currently subscribed")
    }

    func isInvalidReceiptError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let messageParts = [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion,
            nsError.userInfo["readable_error_code"] as? String
        ]

        let message = messageParts.compactMap { $0 }.joined(separator: " ").lowercased()
        return nsError.code == 8 || message.contains("invalid_receipt") || message.contains("receipt is not valid")
    }
}
