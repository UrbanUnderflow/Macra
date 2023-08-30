import Foundation
import RevenueCat

struct PackageViewModel: Identifiable, PackageViewModelProtocol {
    
    let package: Package
    
    var id: String {
        package.identifier
    }
    
    var title: String? {
        guard let subscriptionPeriod = package.storeProduct.subscriptionPeriod else {
            return nil
        }
        
        switch subscriptionPeriod.unit {
        case .month:
            return "Monthly"
        case .year:
            return "Yearly"
        default:
            return "Lifetime"
        }
    }
    
    var price: String {
        package.storeProduct.localizedPriceString
    }
}

protocol PackageViewModelProtocol {
    var id: String { get }
    var title: String? { get }
    var price: String { get }
}
