import Foundation
import FirebaseAuth
import FirebaseFirestore

final class MacroRecommendationService {
    static let sharedInstance = MacroRecommendationService()

    private let db: Firestore

    private init() {
        self.db = Firestore.firestore()
    }

    func saveMacroRecommendation(_ recommendation: MacroRecommendation, completion: @escaping (Result<MacroRecommendation, Error>) -> Void) {
        saveMacroRecommendation(recommendation, userId: recommendation.userId, completion: completion)
    }

    func saveMacroRecommendation(_ recommendation: MacroRecommendation, userId: String? = nil, completion: @escaping (Result<MacroRecommendation, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId ?? recommendation.userId), !resolvedUserId.isEmpty else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        var storedRecommendation = recommendation
        storedRecommendation.userId = resolvedUserId
        storedRecommendation.updatedAt = Date()

        let docRef = db.collection(NutritionCoreConfiguration.macroProfileCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.macroRecommendationsCollection)
            .document(storedRecommendation.id)

        docRef.setData(storedRecommendation.toDictionary()) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(storedRecommendation))
            }
        }
    }

    func saveMacroRecommendationsForDays(_ recommendations: [MacroRecommendation], completion: @escaping (Result<[MacroRecommendation], Error>) -> Void) {
        guard let first = recommendations.first else {
            completion(.success([]))
            return
        }

        let resolvedUserId = first.userId
        let batch = db.batch()
        let storedRecommendations = recommendations.map { recommendation -> MacroRecommendation in
            var stored = recommendation
            stored.userId = resolvedUserId
            stored.updatedAt = Date()
            return stored
        }

        for recommendation in storedRecommendations {
            let docRef = db.collection(NutritionCoreConfiguration.macroProfileCollection)
                .document(resolvedUserId)
                .collection(NutritionCoreConfiguration.macroRecommendationsCollection)
                .document(recommendation.id)
            batch.setData(recommendation.toDictionary(), forDocument: docRef)
        }

        batch.commit { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(storedRecommendations))
            }
        }
    }

    func saveMacroTargets(_ targets: MacroRecommendations, userId: String, dayOfWeek: String? = nil, completion: @escaping (Result<MacroRecommendation, Error>) -> Void) {
        let datedRecommendation = MacroRecommendation(
            userId: userId,
            calories: targets.calories,
            protein: targets.protein,
            carbs: targets.carbs,
            fat: targets.fat,
            dayOfWeek: dayOfWeek
        )
        saveMacroRecommendation(datedRecommendation, completion: completion)
    }

    func getCurrentMacroRecommendation(for userId: String, dayOfWeek: String? = nil, completion: @escaping (Result<MacroRecommendation?, Error>) -> Void) {
        let recommendationRef = db.collection(NutritionCoreConfiguration.macroProfileCollection)
            .document(userId)
            .collection(NutritionCoreConfiguration.macroRecommendationsCollection)

        recommendationRef.getDocuments { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            let recommendations = snapshot?.documents.map { MacroRecommendation(dictionary: $0.data()) } ?? []
            completion(.success(MacroRecommendationResolver.current(from: recommendations, dayOfWeek: dayOfWeek)))
        }
    }

    func getMacroRecommendation(for date: Date, userId: String, completion: @escaping (Result<MacroRecommendation?, Error>) -> Void) {
        let dayOfWeek = date.dayOfWeekShort
        getCurrentMacroRecommendation(for: userId, dayOfWeek: dayOfWeek, completion: completion)
    }

    func getAllMacroRecommendations(for userId: String, completion: @escaping (Result<[MacroRecommendation], Error>) -> Void) {
        let recommendationRef = db.collection(NutritionCoreConfiguration.macroProfileCollection)
            .document(userId)
            .collection(NutritionCoreConfiguration.macroRecommendationsCollection)

        recommendationRef.getDocuments { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            let recommendations = snapshot?.documents
                .map { MacroRecommendation(dictionary: $0.data()) }
                .sorted { $0.createdAt > $1.createdAt } ?? []
            completion(.success(recommendations))
        }
    }

}

enum MacroRecommendationResolver {
    static func current(from recommendations: [MacroRecommendation], dayOfWeek: String? = nil) -> MacroRecommendation? {
        let sorted = recommendations.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }

        if let normalizedDay = normalizedDayOfWeek(dayOfWeek),
           let daySpecific = sorted.first(where: { normalizedDayOfWeek($0.dayOfWeek) == normalizedDay }) {
            return daySpecific
        }

        return sorted.first(where: { normalizedDayOfWeek($0.dayOfWeek) == nil }) ?? sorted.first
    }

    private static func normalizedDayOfWeek(_ value: String?) -> String? {
        guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawValue.isEmpty else {
            return nil
        }

        switch rawValue {
        case "mon", "monday":
            return "mon"
        case "tue", "tues", "tuesday":
            return "tue"
        case "wed", "wednesday":
            return "wed"
        case "thu", "thur", "thurs", "thursday":
            return "thu"
        case "fri", "friday":
            return "fri"
        case "sat", "saturday":
            return "sat"
        case "sun", "sunday":
            return "sun"
        default:
            return rawValue
        }
    }
}
