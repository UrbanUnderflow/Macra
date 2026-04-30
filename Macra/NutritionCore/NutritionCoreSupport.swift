import Foundation
import FirebaseAuth
import FirebaseFirestore
#if canImport(UIKit)
import UIKit
#endif

enum NutritionCoreError: LocalizedError {
    case missingUserId
    case invalidDocument
    case invalidImageData
    case invalidPayload(String)
    case firestoreError(String)

    var errorDescription: String? {
        switch self {
        case .missingUserId:
            return "Missing user id"
        case .invalidDocument:
            return "Invalid nutrition document"
        case .invalidImageData:
            return "Invalid image data"
        case .invalidPayload(let message):
            return message
        case .firestoreError(let message):
            return message
        }
    }
}

enum NutritionCoreLogLevel: String {
    case debug
    case info
    case warning
    case error
}

enum NutritionCoreLogger {
    static func log(_ level: NutritionCoreLogLevel, message: String, error: Error? = nil) {
        var output = "[NutritionCore][\(level.rawValue.uppercased())] \(message)"
        if let error {
            output += " | error=\(error.localizedDescription)"
        }
        print(output)
    }
}

enum NutritionCoreNotification {
    static let dataDidChange = Notification.Name("NutritionCoreDataDidChange")
    /// Fired when the user's active meal plan is mirrored to
    /// `macraSuggestedMealPlans/current`. Today's fuel listens for this so
    /// it can reload the plan that drives the daily UI.
    static let activePlanDidChange = Notification.Name("NutritionCoreActivePlanDidChange")
}

struct NutritionCoreConfiguration {
    static let usersCollection = "users"
    static let mealLogsCollection = "mealLogs"
    static let mealPlansCollection = "meal-plan"
    static let pinnedMealsCollection = "pinnedMeals"
    static let pinnedLabelScansCollection = "pinnedLabelScans"
    static let pinnedFoodSnapsCollection = "pinnedFoodSnaps"
    static let savedSupplementsCollection = "savedSupplements"
    static let supplementLogsCollection = "supplementLogs"
    static let labelScansCollection = "labelScans"
    static let macroProfileCollection = "macro-profile"
    static let macroRecommendationsCollection = "macro-recommendations"
    static let generateMealMacrosCollection = "generateMealMacros"
    static let labelScanStorageFolder = "label-scans"
    static let noraChatCollection = "noraChat"

    static func resolvedUserId(_ explicitUserId: String? = nil) -> String? {
        explicitUserId ?? Auth.auth().currentUser?.uid
    }
}

enum DaysOfTheWeekShort: String, CaseIterable {
    case mon
    case tues
    case wed
    case thur
    case fri
    case sat
    case sun
}

func generateUniqueID(prefix: String? = nil) -> String {
    let timestamp = Date().timeIntervalSince1970
    let uuid = UUID().uuidString
    let prefixString = prefix.map { "\($0)-" } ?? ""
    return "\(prefixString)\(uuid)-\(timestamp)"
}

func nutritionDate(from value: Any?) -> Date {
    if let timestamp = value as? Timestamp {
        return timestamp.dateValue()
    }
    if let date = value as? Date {
        return date
    }
    if let number = value as? Double {
        return Date(timeIntervalSince1970: number)
    }
    if let number = value as? Int {
        return Date(timeIntervalSince1970: Double(number))
    }
    if let string = value as? String, let number = Double(string) {
        return Date(timeIntervalSince1970: number)
    }
    return Date()
}

func nutritionOptionalDate(from value: Any?) -> Date? {
    guard let value else { return nil }
    if value is NSNull { return nil }
    return nutritionDate(from: value)
}

func nutritionInt(from value: Any?) -> Int {
    if let intValue = value as? Int { return intValue }
    if let doubleValue = value as? Double { return Int(doubleValue) }
    if let number = value as? NSNumber { return number.intValue }
    if let stringValue = value as? String, let intValue = Int(stringValue) { return intValue }
    return 0
}

func nutritionOptionalInt(from value: Any?) -> Int? {
    guard let value else { return nil }
    if value is NSNull { return nil }
    let parsed = nutritionInt(from: value)
    return parsed == 0 ? nil : parsed
}

func nutritionDouble(from value: Any?) -> Double {
    if let doubleValue = value as? Double { return doubleValue }
    if let number = value as? NSNumber { return number.doubleValue }
    if let intValue = value as? Int { return Double(intValue) }
    if let stringValue = value as? String, let doubleValue = Double(stringValue) { return doubleValue }
    return 0
}

func nutritionStringIntMap(from value: Any?) -> [String: Int]? {
    guard let value, !(value is NSNull) else { return nil }

    if let existing = value as? [String: Int] {
        return existing.isEmpty ? nil : existing
    }

    if let dictionary = value as? [String: Any] {
        let converted = dictionary.reduce(into: [String: Int]()) { result, element in
            let parsed = nutritionOptionalInt(from: element.value)
            if let parsed, parsed > 0 {
                result[element.key] = parsed
            }
        }
        return converted.isEmpty ? nil : converted
    }

    return nil
}

func nutritionStringArray(from value: Any?) -> [String] {
    if let array = value as? [String] {
        return array
    }
    if let array = value as? [Any] {
        return array.compactMap { $0 as? String }
    }
    return []
}

extension Date {
    var nutritionMealLogDocumentPrefix: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMddyyyy"
        return formatter.string(from: self)
    }

    var monthDayYear: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd-yyyy"
        return formatter.string(from: self)
    }

    var dayOfWeekShort: String {
        switch Calendar.current.component(.weekday, from: self) {
        case 1: return DaysOfTheWeekShort.sun.rawValue
        case 2: return DaysOfTheWeekShort.mon.rawValue
        case 3: return DaysOfTheWeekShort.tues.rawValue
        case 4: return DaysOfTheWeekShort.wed.rawValue
        case 5: return DaysOfTheWeekShort.thur.rawValue
        case 6: return DaysOfTheWeekShort.fri.rawValue
        case 7: return DaysOfTheWeekShort.sat.rawValue
        default: return DaysOfTheWeekShort.mon.rawValue
        }
    }
}

#if canImport(UIKit)
extension UIImage {
    func toBase64() -> String? {
        jpegData(compressionQuality: 0.8)?.base64EncodedString()
    }
}
#endif

extension String {
    func contains(regex pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Pinned Scans Service
//
// Mirrors the QuickLifts `pinnedMeals` pattern: each pin is a standalone
// Firestore doc under `users/{userId}/pinnedLabelScans` or
// `users/{userId}/pinnedFoodSnaps`, keyed by the source scan/meal id so
// repeat pins are idempotent. Pinning does not mutate the source doc, so
// users can clear scan history and still keep their quick-add library.

final class MacraPinnedScanService {
    static let sharedInstance = MacraPinnedScanService()

    private let db: Firestore

    private init() {
        self.db = Firestore.firestore()
    }

    // MARK: Label scans

    func loadPinnedLabelScans(userId: String? = nil, completion: @escaping (Result<[MacraScannedLabel], Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.pinnedLabelScansCollection)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let docs = snapshot?.documents ?? []
                let pins: [(order: Int, scan: MacraScannedLabel)] = docs.map { document in
                    let data = document.data()
                    let order = nutritionInt(from: data["sortOrder"])
                    return (order, MacraScannedLabel(id: document.documentID, data: data))
                }
                let sorted = pins.sorted { lhs, rhs in
                    if lhs.order != rhs.order { return lhs.order < rhs.order }
                    return lhs.scan.createdAt > rhs.scan.createdAt
                }
                completion(.success(sorted.map { $0.scan }))
            }
    }

    func pinLabelScan(_ scan: MacraScannedLabel, userId: String? = nil, sortOrder: Int = Int.max, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion?(.failure(NutritionCoreError.missingUserId))
            return
        }

        var data = encodePinnedLabelScan(scan)
        data["sortOrder"] = sortOrder
        data["pinnedAt"] = Timestamp(date: Date())

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.pinnedLabelScansCollection)
            .document(scan.id)
            .setData(data) { error in
                if let error {
                    completion?(.failure(error))
                } else {
                    completion?(.success(()))
                }
            }
    }

    func unpinLabelScan(id: String, userId: String? = nil, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion?(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.pinnedLabelScansCollection)
            .document(id)
            .delete { error in
                if let error {
                    completion?(.failure(error))
                } else {
                    completion?(.success(()))
                }
            }
    }

    // MARK: Food snaps

    func loadPinnedFoodSnaps(userId: String? = nil, completion: @escaping (Result<[Meal], Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.pinnedFoodSnapsCollection)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let docs = snapshot?.documents ?? []
                let pins: [(order: Int, meal: Meal)] = docs.map { document in
                    let data = document.data()
                    let order = nutritionInt(from: data["sortOrder"])
                    return (order, Meal(id: document.documentID, dictionary: data))
                }
                let sorted = pins.sorted { lhs, rhs in
                    if lhs.order != rhs.order { return lhs.order < rhs.order }
                    return lhs.meal.createdAt > rhs.meal.createdAt
                }
                completion(.success(sorted.map { $0.meal }))
            }
    }

    func pinFoodSnap(_ meal: Meal, userId: String? = nil, sortOrder: Int = Int.max, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion?(.failure(NutritionCoreError.missingUserId))
            return
        }

        var data = meal.toDictionary()
        data["sortOrder"] = sortOrder
        data["pinnedAt"] = Timestamp(date: Date())

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.pinnedFoodSnapsCollection)
            .document(meal.id)
            .setData(data) { error in
                if let error {
                    completion?(.failure(error))
                } else {
                    completion?(.success(()))
                }
            }
    }

    func unpinFoodSnap(id: String, userId: String? = nil, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion?(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.pinnedFoodSnapsCollection)
            .document(id)
            .delete { error in
                if let error {
                    completion?(.failure(error))
                } else {
                    completion?(.success(()))
                }
            }
    }

    // MARK: Encoders

    private func encodePinnedLabelScan(_ scan: MacraScannedLabel) -> [String: Any] {
        let grade = scan.gradeResult
        var gradeDict: [String: Any] = [
            "grade": grade.grade,
            "summary": grade.summary,
            "detailedExplanation": grade.detailedExplanation,
            "confidence": grade.confidence,
            "flaggedIngredients": grade.flaggedIngredients
        ]
        if let productTitle = grade.productTitle { gradeDict["productTitle"] = productTitle }
        if let calories = grade.calories { gradeDict["calories"] = calories }
        if let protein = grade.protein { gradeDict["protein"] = protein }
        if let fat = grade.fat { gradeDict["fat"] = fat }
        if let carbs = grade.carbs { gradeDict["carbs"] = carbs }
        if let servingSize = grade.servingSize { gradeDict["servingSize"] = servingSize }
        if let sugars = grade.sugars { gradeDict["sugars"] = sugars }
        if let dietaryFiber = grade.dietaryFiber { gradeDict["dietaryFiber"] = dietaryFiber }
        if let sugarAlcohols = grade.sugarAlcohols { gradeDict["sugarAlcohols"] = sugarAlcohols }
        if let sodium = grade.sodium { gradeDict["sodium"] = sodium }

        var data: [String: Any] = [
            "id": scan.id,
            "gradeResult": gradeDict,
            "createdAt": Timestamp(date: scan.createdAt),
            "userNotes": scan.userNotes,
            "productTitleEdited": scan.productTitleEdited
        ]
        if let imageURL = scan.imageURL { data["imageURL"] = imageURL }
        if let productTitle = scan.productTitle { data["productTitle"] = productTitle }
        return data
    }
}
