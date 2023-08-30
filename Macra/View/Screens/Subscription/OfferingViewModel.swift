import Foundation
import RevenueCat

enum PurchaseResult {
    case success
    case failure(Error)
}

@MainActor
final class OfferingViewModel: ObservableObject, OfferingViewModelProtocol {
    
    static let sharedInstance = OfferingViewModel()

    @Published private(set) var packageViewModel: [PackageViewModel] = []
    @Published private(set) var monthlyPackage: PackageViewModel?
    @Published private(set) var yearlyPackage: PackageViewModel?
    @Published private(set) var lifetimePackage: PackageViewModel?

    func start() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            let packages = offerings.current?.availablePackages ?? []
            packageViewModel = packages.map(PackageViewModel.init(package:))
            // find monthly and yearly packages
            monthlyPackage = packageViewModel.first(where: { $0.package.storeProduct.subscriptionPeriod?.unit == .month })
            yearlyPackage = packageViewModel.first(where: { $0.package.storeProduct.subscriptionPeriod?.unit == .year })
            lifetimePackage = packageViewModel.first(where: { $0.package.storeProduct.subscriptionPeriod?.unit == .none })
        } catch {
            print("Unable to Fetch Offerings \(error)")
        }
    }
    
    func purchase(_ viewmodel: PackageViewModel, completion: @escaping (PurchaseResult) -> Void) {
        Task {
            do {
                var purchased = try await Purchases.shared.purchase(package: viewmodel.package)
                if purchased.userCancelled == true {
                    completion(.failure(NSError(domain: "Purchase Canceled", code: -1)))
                    return
                }
                
                if purchased.customerInfo.originalPurchaseDate == nil {
                    completion(.failure(NSError(domain: "Purchase Canceled", code: -1)))
                    return
                }
                
                DispatchQueue.main.async {
                    completion(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}

protocol OfferingViewModelProtocol {
    var packageViewModel: [PackageViewModel] { get }
    var monthlyPackage: PackageViewModel? { get }
    var yearlyPackage: PackageViewModel? { get }
    var lifetimePackage: PackageViewModel? { get }
    
    func start() async
    func purchase(_ viewmodel: PackageViewModel, completion: @escaping (PurchaseResult) -> Void)
}
