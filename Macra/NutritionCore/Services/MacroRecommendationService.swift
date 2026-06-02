import Foundation
import FirebaseAuth
import FirebaseFirestore

final class MacroRecommendationService {
    static let sharedInstance = MacroRecommendationService()

    private let db: Firestore

    private init() {
        self.db = Firestore.firestore()
    }

    private static func defaultEffectiveFrom(for date: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: date)
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
        if storedRecommendation.effectiveFrom == nil {
            storedRecommendation.effectiveFrom = Self.defaultEffectiveFrom()
        }

        let docRef = db.collection(NutritionCoreConfiguration.macroProfileCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.macroRecommendationsCollection)
            .document(storedRecommendation.id)

        docRef.setData(storedRecommendation.toDictionary()) { error in
            if let error {
                completion(.failure(error))
            } else {
                // Mirror to the shared User doc so FWP + PulseCheck see
                // the same target without having to query Macra's
                // macro-profile collection.
                let mirrored = MacroRecommendations(
                    calories: storedRecommendation.calories,
                    protein: storedRecommendation.protein,
                    carbs: storedRecommendation.carbs,
                    fat: storedRecommendation.fat
                )
                FWPHandoffService.mirrorToFWPPersonal(mirrored) { _ in
                    completion(.success(storedRecommendation))
                }
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
            if stored.effectiveFrom == nil {
                stored.effectiveFrom = Self.defaultEffectiveFrom()
            }
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
        let recommendationRef = db.collection(NutritionCoreConfiguration.macroProfileCollection)
            .document(userId)
            .collection(NutritionCoreConfiguration.macroRecommendationsCollection)

        recommendationRef.getDocuments { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            let recommendations = snapshot?.documents.map { MacroRecommendation(dictionary: $0.data()) } ?? []
            completion(.success(MacroRecommendationResolver.current(from: recommendations, dayOfWeek: dayOfWeek, on: date)))
        }
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
    static func current(from recommendations: [MacroRecommendation], dayOfWeek: String? = nil, on date: Date? = nil) -> MacroRecommendation? {
        let candidates: [MacroRecommendation]
        if let date {
            let selectedDay = Calendar.current.startOfDay(for: date)
            candidates = recommendations.filter { recommendation in
                effectiveDay(for: recommendation) <= selectedDay
            }
        } else {
            candidates = recommendations
        }

        if let normalizedDay = normalizedDayOfWeek(dayOfWeek) {
            let scoped = candidates.filter { recommendation in
                let recommendationDay = normalizedDayOfWeek(recommendation.dayOfWeek)
                return recommendationDay == nil || recommendationDay == normalizedDay
            }
            return scoped.sorted {
                sortMostRecentFirst($0, $1, preferredDay: normalizedDay)
            }.first
        }

        let sorted = candidates.sorted(by: sortMostRecentFirst)
        return sorted.first(where: { normalizedDayOfWeek($0.dayOfWeek) == nil }) ?? sorted.first
    }

    private static func sortMostRecentFirst(_ lhs: MacroRecommendation, _ rhs: MacroRecommendation) -> Bool {
        sortMostRecentFirst(lhs, rhs, preferredDay: nil)
    }

    private static func sortMostRecentFirst(_ lhs: MacroRecommendation, _ rhs: MacroRecommendation, preferredDay: String?) -> Bool {
        let lhsEffective = effectiveDay(for: lhs)
        let rhsEffective = effectiveDay(for: rhs)
        if lhsEffective != rhsEffective {
            return lhsEffective > rhsEffective
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if let preferredDay {
            let lhsMatchesPreferredDay = normalizedDayOfWeek(lhs.dayOfWeek) == preferredDay
            let rhsMatchesPreferredDay = normalizedDayOfWeek(rhs.dayOfWeek) == preferredDay
            if lhsMatchesPreferredDay != rhsMatchesPreferredDay {
                return lhsMatchesPreferredDay
            }
        }
        return lhs.createdAt > rhs.createdAt
    }

    private static func effectiveDay(for recommendation: MacroRecommendation) -> Date {
        Calendar.current.startOfDay(for: recommendation.effectiveFrom ?? recommendation.createdAt)
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
