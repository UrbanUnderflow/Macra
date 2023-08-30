import Foundation
import Combine
import RevenueCat

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

final class PurchaseService: NSObject, PurchasesDelegate {
    
    static let sharedInstance = PurchaseService()
    let offering = OfferingViewModel.sharedInstance

    @Published private(set) var isSubscribed = false
    
    var subscribedPublisher: AnyPublisher<Bool, Never> {
        $isSubscribed.eraseToAnyPublisher()
    }
    
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        guard let entitlement = customerInfo.entitlements.all["plus"] else {
            isSubscribed = false
            return
        }
        
        isSubscribed = entitlement.isActive
    }
    
    func checkSubscriptionStatus(completion: @escaping (Result<Bool, Error>) -> Void) {
        Purchases.shared.getCustomerInfo { (purchaserInfo, error) in
            if let error = error {
                completion(.failure(error))
            } else if let purchaserInfo = purchaserInfo {
                let isSubscribed = purchaserInfo.entitlements["plus"]?.isActive == true
                if UserService.sharedInstance.isBetaUser == true {
                    self.isSubscribed = true
                } else {
                    self.isSubscribed = isSubscribed
                }
                completion(.success(self.isSubscribed))
            } else {
                self.isSubscribed = false
                completion(.failure(CustomError.noPurchaserInfo))
            }
        }
    }
}
