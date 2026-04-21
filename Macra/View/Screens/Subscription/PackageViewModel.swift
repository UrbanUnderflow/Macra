import Foundation
import RevenueCat

struct PackageViewModel: Identifiable, PackageViewModelProtocol {
    
    let package: Package
    
    var id: String {
        package.identifier
    }
    
    var title: String? {
        guard let subscriptionPeriod = package.storeProduct.subscriptionPeriod else {
            return "Plan"
        }

        switch subscriptionPeriod.unit {
        case .month:
            return "Monthly"
        case .year:
            return "Yearly"
        default:
            return "Plan"
        }
    }
    
    var price: String {
        package.storeProduct.localizedPriceString
    }

    var subscriptionPeriodUnit: SubscriptionPeriod.Unit? {
        package.storeProduct.subscriptionPeriod?.unit
    }

    var displayTitle: String {
        switch subscriptionPeriodUnit {
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        case .year: return "Annual"
        default: return "Plan"
        }
    }

    var billingNote: String {
        switch subscriptionPeriodUnit {
        case .day: return "Billed daily"
        case .week: return "Billed weekly"
        case .month: return "Billed monthly"
        case .year: return "\(price) billed annually"
        default: return ""
        }
    }

    var perPeriodDisplay: String {
        switch subscriptionPeriodUnit {
        case .year:
            let perMonth = NSDecimalNumber(decimal: package.storeProduct.price).doubleValue / 12.0
            return String(format: "$%.2f/mo", perMonth)
        case .month: return "\(price)/mo"
        case .week: return "\(price)/wk"
        case .day: return "\(price)/day"
        default: return price
        }
    }
}

protocol PackageViewModelProtocol {
    var id: String { get }
    var title: String? { get }
    var price: String { get }
}
