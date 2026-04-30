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

    enum HealthKitWriteError: LocalizedError {
        case unavailable
        case noTypesAuthorized

        var errorDescription: String? {
            switch self {
            case .unavailable: return "HealthKit isn't available on this device."
            case .noTypesAuthorized: return "Macra isn't authorized to write meals to Apple Health. Open the Health app → Sources → Macra and enable the categories you want to share."
            }
        }
    }

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

    /// Flips true after the first `noTypesAuthorized` toast in a session so we
    /// don't nag the user every meal log. Resets on app launch.
    var hasWarnedNoTypesAuthorized: Bool = false

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
        guard isAvailable else {
            completion(.failure(HealthKitWriteError.unavailable))
            return
        }
        guard userOptIn else {
            completion(.success(()))
            return
        }

        let authorizedSamples = buildAuthorizedSamples(for: meal, date: date)
        guard !authorizedSamples.isEmpty else {
            // User turned the toggle on but denied every sub-type in the
            // permission sheet. Don't crash — surface a recoverable error so
            // the UI can prompt the user to enable categories in Health app.
            completion(.failure(HealthKitWriteError.noTypesAuthorized))
            return
        }

        // Prefer saving as a `food` correlation so meals appear grouped in the
        // Health app. If that type was denied, fall back to individual quantity
        // samples — they still show up under each macro, just not grouped.
        let correlationType = HKObjectType.correlationType(forIdentifier: .food)
        if let correlationType,
           store.authorizationStatus(for: correlationType) == .sharingAuthorized {
            let metadata: [String: Any] = [
                HKMetadataKeyFoodType: meal.name,
                "macra.meal.id": meal.id
            ]
            let correlation = HKCorrelation(
                type: correlationType,
                start: date,
                end: date,
                objects: Set(authorizedSamples),
                metadata: metadata
            )
            store.save(correlation) { [weak self] success, error in
                DispatchQueue.main.async {
                    self?.handleSaveResult(mealID: meal.id, success: success, error: error, completion: completion)
                }
            }
        } else {
            store.save(authorizedSamples) { [weak self] success, error in
                DispatchQueue.main.async {
                    self?.handleSaveResult(mealID: meal.id, success: success, error: error, completion: completion)
                }
            }
        }
    }

    func isMealSynced(_ mealID: String) -> Bool {
        syncedMealIDs.contains(mealID)
    }

    private func buildAuthorizedSamples(for meal: Meal, date: Date) -> [HKQuantitySample] {
        var samples: [HKQuantitySample] = []

        appendIfAuthorized(.dietaryEnergyConsumed, value: Double(meal.calories), unit: .kilocalorie(), date: date, into: &samples, when: meal.calories > 0)
        appendIfAuthorized(.dietaryProtein, value: Double(meal.protein), unit: .gram(), date: date, into: &samples, when: meal.protein > 0)
        appendIfAuthorized(.dietaryCarbohydrates, value: Double(meal.carbs), unit: .gram(), date: date, into: &samples, when: meal.carbs > 0)
        appendIfAuthorized(.dietaryFatTotal, value: Double(meal.fat), unit: .gram(), date: date, into: &samples, when: meal.fat > 0)
        if let fiber = meal.fiber {
            appendIfAuthorized(.dietaryFiber, value: Double(fiber), unit: .gram(), date: date, into: &samples, when: fiber > 0)
        }

        return samples
    }

    private func appendIfAuthorized(
        _ identifier: HKQuantityTypeIdentifier,
        value: Double,
        unit: HKUnit,
        date: Date,
        into samples: inout [HKQuantitySample],
        when condition: Bool
    ) {
        guard condition,
              let type = HKObjectType.quantityType(forIdentifier: identifier),
              store.authorizationStatus(for: type) == .sharingAuthorized else { return }
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        samples.append(HKQuantitySample(type: type, quantity: quantity, start: date, end: date))
    }

    private func handleSaveResult(
        mealID: String,
        success: Bool,
        error: Error?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if success {
            markSynced(mealID: mealID)
            completion(.success(()))
        } else if let error {
            completion(.failure(error))
        } else {
            completion(.success(()))
        }
    }

    private func markSynced(mealID: String) {
        var current = syncedMealIDs
        current.insert(mealID)
        UserDefaults.standard.set(Array(current), forKey: syncedMealsKey)
    }
}
