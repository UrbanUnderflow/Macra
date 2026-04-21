import Foundation
import HealthKit

/// Writes Macra meals to Apple Health as dietary `HKCorrelation`s.
///
/// Before this will do anything on-device the app must have the HealthKit
/// capability enabled in Xcode (Signing & Capabilities → +Capability →
/// HealthKit) and the following keys in Info.plist:
///
///   - `NSHealthShareUsageDescription`
///   - `NSHealthUpdateUsageDescription`
///
/// Without those, `HKHealthStore.isHealthDataAvailable()` returns false and
/// every call here is a no-op — the rest of the app stays functional.
final class MacraHealthKitService {
    static let shared = MacraHealthKitService()

    private let store = HKHealthStore()
    private let syncedMealsKey = "com.macra.healthkit.syncedMealIDs"
    private let userOptInKey = "com.macra.healthkit.userOptIn"

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var userOptIn: Bool {
        get { UserDefaults.standard.bool(forKey: userOptInKey) }
        set { UserDefaults.standard.set(newValue, forKey: userOptInKey) }
    }

    var syncedMealIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: syncedMealsKey) ?? [])
    }

    private init() {}

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if let energy = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            types.insert(energy)
        }
        if let protein = HKObjectType.quantityType(forIdentifier: .dietaryProtein) {
            types.insert(protein)
        }
        if let carbs = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            types.insert(carbs)
        }
        if let fat = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal) {
            types.insert(fat)
        }
        if let fiber = HKObjectType.quantityType(forIdentifier: .dietaryFiber) {
            types.insert(fiber)
        }
        if let food = HKObjectType.correlationType(forIdentifier: .food) as HKSampleType? {
            types.insert(food)
        }
        return types
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard isAvailable else {
            completion(false, nil)
            return
        }
        store.requestAuthorization(toShare: writeTypes, read: []) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }

    func saveMeal(_ meal: Meal, date: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        guard isAvailable, userOptIn else {
            completion(.success(()))
            return
        }

        var samples: [HKSample] = []

        if meal.calories > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: Double(meal.calories))
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: date, end: date))
        }
        if meal.protein > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryProtein) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: Double(meal.protein))
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: date, end: date))
        }
        if meal.carbs > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: Double(meal.carbs))
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: date, end: date))
        }
        if meal.fat > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: Double(meal.fat))
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: date, end: date))
        }
        if let fiber = meal.fiber, fiber > 0,
           let type = HKObjectType.quantityType(forIdentifier: .dietaryFiber) {
            let quantity = HKQuantity(unit: .gram(), doubleValue: Double(fiber))
            samples.append(HKQuantitySample(type: type, quantity: quantity, start: date, end: date))
        }

        guard !samples.isEmpty else {
            completion(.success(()))
            return
        }

        let quantitySamples = samples.compactMap { $0 as? HKQuantitySample }
        let correlationType = HKObjectType.correlationType(forIdentifier: .food)!
        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: meal.name,
            "macra.meal.id": meal.id
        ]
        let correlation = HKCorrelation(
            type: correlationType,
            start: date,
            end: date,
            objects: Set(quantitySamples),
            metadata: metadata
        )

        store.save(correlation) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.markSynced(mealID: meal.id)
                    completion(.success(()))
                } else if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func isMealSynced(_ mealID: String) -> Bool {
        syncedMealIDs.contains(mealID)
    }

    private func markSynced(mealID: String) {
        var current = syncedMealIDs
        current.insert(mealID)
        UserDefaults.standard.set(Array(current), forKey: syncedMealsKey)
    }
}
