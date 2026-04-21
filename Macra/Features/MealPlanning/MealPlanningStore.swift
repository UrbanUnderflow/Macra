import Foundation
import FirebaseFirestore

enum MealPlanningStoreError: LocalizedError {
    case notFound
    case unauthorized
    case invalidData
    case noUserId

    var errorDescription: String? {
        switch self {
        case .notFound: return "The requested item could not be found."
        case .unauthorized: return "You do not have permission to edit this item."
        case .invalidData: return "The stored meal-planning data is invalid."
        case .noUserId: return "A user id is required for this action."
        }
    }
}

protocol MealPlanningStore {
    func fetchMealPlans(userId: String, completion: @escaping (Result<[MealPlan], Error>) -> Void)
    func saveMealPlan(_ mealPlan: MealPlan, completion: @escaping (Result<MealPlan, Error>) -> Void)
    func createMealPlan(userId: String, planName: String, sourceMeals: [Meal], completion: @escaping (Result<MealPlan, Error>) -> Void)
    func updateMealPlanName(planId: String, userId: String, newName: String, completion: @escaping (Result<MealPlan, Error>) -> Void)
    func deleteMealPlan(planId: String, userId: String, completion: @escaping (Result<Void, Error>) -> Void)
    func fetchMeals(for date: Date, userId: String, completion: @escaping (Result<[Meal], Error>) -> Void)
    func fetchRecentMeals(userId: String, limit: Int, completion: @escaping (Result<[Meal], Error>) -> Void)
    func logMeals(_ meals: [Meal], userId: String, at date: Date, completion: @escaping (Result<Void, Error>) -> Void)
    func saveMacroRecommendation(_ recommendation: MacroRecommendation, completion: @escaping (Result<MacroRecommendation, Error>) -> Void)
    func fetchMacroRecommendations(userId: String, completion: @escaping (Result<[MacroRecommendation], Error>) -> Void)
    func fetchCurrentMacroRecommendation(userId: String, dayOfWeek: String?, completion: @escaping (Result<MacroRecommendation?, Error>) -> Void)
}

final class FirestoreMealPlanningStore: MealPlanningStore {
    private let db: Firestore

    init(db: Firestore = .firestore()) {
        self.db = db
    }

    func fetchMealPlans(userId: String, completion: @escaping (Result<[MealPlan], Error>) -> Void) {
        db.collection("meal-plan")
            .whereField("userId", isEqualTo: userId)
            .whereField("isActive", isEqualTo: true)
            .order(by: "createdAt", descending: false)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let plans = snapshot?.documents.map { document -> MealPlan in
                    var plan = MealPlan(dictionary: document.data())
                    plan.id = document.documentID
                    return plan
                } ?? []
                completion(.success(plans))
            }
    }

    func saveMealPlan(_ mealPlan: MealPlan, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        let ref = db.collection("meal-plan").document(mealPlan.id)
        var plan = mealPlan
        plan.updatedAt = Date()

        ref.setData(plan.toDictionary()) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(plan))
            }
        }
    }

    func createMealPlan(userId: String, planName: String, sourceMeals: [Meal], completion: @escaping (Result<MealPlan, Error>) -> Void) {
        let ref = db.collection("meal-plan").document()
        var plan = MealPlan(id: ref.documentID, userId: userId, planName: planName)
        if !sourceMeals.isEmpty {
            plan.addMeals(sourceMeals)
        }

        ref.setData(plan.toDictionary()) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(plan))
            }
        }
    }

    func updateMealPlanName(planId: String, userId: String, newName: String, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        let ref = db.collection("meal-plan").document(planId)
        ref.getDocument { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                completion(.failure(MealPlanningStoreError.notFound))
                return
            }

            var plan = MealPlan(dictionary: data)
            guard plan.userId == userId else {
                completion(.failure(MealPlanningStoreError.unauthorized))
                return
            }

            plan.id = planId
            plan.planName = newName
            plan.updatedAt = Date()
            self.saveMealPlan(plan, completion: completion)
        }
    }

    func deleteMealPlan(planId: String, userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let ref = db.collection("meal-plan").document(planId)
        ref.getDocument { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                completion(.failure(MealPlanningStoreError.notFound))
                return
            }

            let plan = MealPlan(dictionary: data)
            guard plan.userId == userId else {
                completion(.failure(MealPlanningStoreError.unauthorized))
                return
            }

            ref.delete { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func fetchMeals(for date: Date, userId: String, completion: @escaping (Result<[Meal], Error>) -> Void) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            completion(.failure(MealPlanningStoreError.invalidData))
            return
        }

        db.collection("users")
            .document(userId)
            .collection("mealLogs")
            .whereField("createdAt", isGreaterThanOrEqualTo: startOfDay.timeIntervalSince1970)
            .whereField("createdAt", isLessThan: endOfDay.timeIntervalSince1970)
            .order(by: "createdAt", descending: false)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let meals = snapshot?.documents.map { document in
                    Meal(id: document.documentID, dictionary: document.data())
                } ?? []
                completion(.success(meals))
            }
    }

    func fetchRecentMeals(userId: String, limit: Int, completion: @escaping (Result<[Meal], Error>) -> Void) {
        db.collection("users")
            .document(userId)
            .collection("mealLogs")
            .order(by: "createdAt", descending: true)
            .limit(to: max(limit, 1))
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let meals = snapshot?.documents.map { document in
                    Meal(id: document.documentID, dictionary: document.data())
                } ?? []
                completion(.success(meals))
            }
    }

    func logMeals(_ meals: [Meal], userId: String, at date: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !meals.isEmpty else {
            completion(.success(()))
            return
        }

        let batch = db.batch()
        let prefix = MealPlanningDates.datePrefixFormatter.string(from: date)

        for meal in meals {
            var loggedMeal = meal
            if loggedMeal.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                loggedMeal.id = MealPlanningIDs.make(prefix: "meal")
            }
            loggedMeal.createdAt = date
            loggedMeal.updatedAt = Date()

            let ref = db.collection("users")
                .document(userId)
                .collection("mealLogs")
                .document("\(prefix)\(loggedMeal.id)")
            batch.setData(loggedMeal.toDictionary(), forDocument: ref)
        }

        batch.commit { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func saveMacroRecommendation(_ recommendation: MacroRecommendation, completion: @escaping (Result<MacroRecommendation, Error>) -> Void) {
        let ref = db.collection("macro-profile")
            .document(recommendation.userId)
            .collection("macro-recommendations")
            .document(recommendation.id)

        ref.setData(recommendation.toDictionary()) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(recommendation))
            }
        }
    }

    func fetchMacroRecommendations(userId: String, completion: @escaping (Result<[MacroRecommendation], Error>) -> Void) {
        db.collection("macro-profile")
            .document(userId)
            .collection("macro-recommendations")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let recommendations = snapshot?.documents.map { MacroRecommendation(dictionary: $0.data()) } ?? []
                completion(.success(recommendations))
            }
    }

    func fetchCurrentMacroRecommendation(userId: String, dayOfWeek: String?, completion: @escaping (Result<MacroRecommendation?, Error>) -> Void) {
        fetchMacroRecommendations(userId: userId) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let recommendations):
                completion(.success(MacroRecommendationResolver.current(from: recommendations, dayOfWeek: dayOfWeek)))
            }
        }
    }
}

final class InMemoryMealPlanningStore: MealPlanningStore {
    private var mealPlans: [MealPlan]
    private var recommendations: [MacroRecommendation]

    init(
        mealPlans: [MealPlan] = [],
        recommendations: [MacroRecommendation] = []
    ) {
        self.mealPlans = mealPlans
        self.recommendations = recommendations
    }

    func fetchMealPlans(userId: String, completion: @escaping (Result<[MealPlan], Error>) -> Void) {
        completion(.success(mealPlans.filter { $0.userId == userId }))
    }

    func saveMealPlan(_ mealPlan: MealPlan, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        var plan = mealPlan
        plan.updatedAt = Date()
        if let index = mealPlans.firstIndex(where: { $0.id == plan.id }) {
            mealPlans[index] = plan
        } else {
            mealPlans.append(plan)
        }
        completion(.success(plan))
    }

    func createMealPlan(userId: String, planName: String, sourceMeals: [Meal], completion: @escaping (Result<MealPlan, Error>) -> Void) {
        var plan = MealPlan(userId: userId, planName: planName)
        if !sourceMeals.isEmpty {
            plan.addMeals(sourceMeals)
        }
        mealPlans.append(plan)
        completion(.success(plan))
    }

    func updateMealPlanName(planId: String, userId: String, newName: String, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        guard let index = mealPlans.firstIndex(where: { $0.id == planId }), mealPlans[index].userId == userId else {
            completion(.failure(MealPlanningStoreError.notFound))
            return
        }
        mealPlans[index].planName = newName
        mealPlans[index].updatedAt = Date()
        completion(.success(mealPlans[index]))
    }

    func deleteMealPlan(planId: String, userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let index = mealPlans.firstIndex(where: { $0.id == planId }), mealPlans[index].userId == userId else {
            completion(.failure(MealPlanningStoreError.notFound))
            return
        }
        mealPlans.remove(at: index)
        completion(.success(()))
    }

    func fetchMeals(for date: Date, userId: String, completion: @escaping (Result<[Meal], Error>) -> Void) {
        fetchRecentMeals(userId: userId, limit: 25, completion: completion)
    }

    func fetchRecentMeals(userId: String, limit: Int, completion: @escaping (Result<[Meal], Error>) -> Void) {
        let meals = mealPlans
            .filter { $0.userId == userId }
            .flatMap { $0.plannedMeals.flatMap(\.meals) }
            .prefix(limit)
        completion(.success(Array(meals)))
    }

    func logMeals(_ meals: [Meal], userId: String, at date: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }

    func saveMacroRecommendation(_ recommendation: MacroRecommendation, completion: @escaping (Result<MacroRecommendation, Error>) -> Void) {
        if let index = recommendations.firstIndex(where: { $0.id == recommendation.id }) {
            recommendations[index] = recommendation
        } else {
            recommendations.append(recommendation)
        }
        completion(.success(recommendation))
    }

    func fetchMacroRecommendations(userId: String, completion: @escaping (Result<[MacroRecommendation], Error>) -> Void) {
        completion(.success(recommendations.filter { $0.userId == userId }))
    }

    func fetchCurrentMacroRecommendation(userId: String, dayOfWeek: String?, completion: @escaping (Result<MacroRecommendation?, Error>) -> Void) {
        let all = recommendations.filter { $0.userId == userId }
        completion(.success(MacroRecommendationResolver.current(from: all, dayOfWeek: dayOfWeek)))
    }
}
