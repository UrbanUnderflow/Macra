import Foundation
import FirebaseAuth
import FirebaseFirestore

final class MealService {
    static let sharedInstance = MealService()

    private let db: Firestore

    private init() {
        self.db = Firestore.firestore()
    }

    // MARK: - Meal Logs

    func saveMeal(_ meal: Meal, for date: Date = Date(), userId: String? = nil, completion: @escaping (Result<Meal, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let documentID = mealLogDocumentID(for: date, mealId: meal.id)
        var storedMeal = meal
        storedMeal.createdAt = date
        storedMeal.updatedAt = Date()

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.mealLogsCollection)
            .document(documentID)
            .setData(storedMeal.toDictionary()) { [weak self] error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.postNutritionChange()
                completion(.success(storedMeal))
            }
    }

    func saveMeals(_ meals: [Meal], for date: Date = Date(), userId: String? = nil, completion: @escaping (Result<[Meal], Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        guard !meals.isEmpty else {
            completion(.success([]))
            return
        }

        let batch = db.batch()
        let storedMeals = meals.map { meal -> Meal in
            var storedMeal = meal
            storedMeal.createdAt = date
            storedMeal.updatedAt = Date()
            return storedMeal
        }

        for meal in storedMeals {
            let documentID = mealLogDocumentID(for: date, mealId: meal.id)
            let docRef = db.collection(NutritionCoreConfiguration.usersCollection)
                .document(resolvedUserId)
                .collection(NutritionCoreConfiguration.mealLogsCollection)
                .document(documentID)
            batch.setData(meal.toDictionary(), forDocument: docRef)
        }

        batch.commit { [weak self] error in
            if let error {
                completion(.failure(error))
                return
            }
            self?.postNutritionChange()
            completion(.success(storedMeals))
        }
    }

    func getMeals(byDate date: Date, userId: String? = nil, completion: @escaping (Result<[Meal], Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        guard let range = dateRange(for: date) else {
            completion(.failure(NutritionCoreError.invalidPayload("Could not calculate the date range for meal lookup.")))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.mealLogsCollection)
            .whereField("createdAt", isGreaterThanOrEqualTo: range.start.timeIntervalSince1970)
            .whereField("createdAt", isLessThanOrEqualTo: range.end.timeIntervalSince1970)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let meals = snapshot?.documents.map { Meal(id: $0.documentID, dictionary: $0.data()) } ?? []
                completion(.success(meals.sorted { $0.createdAt < $1.createdAt }))
            }
    }

    func getLoggedDates(inMonth referenceDate: Date, userId: String? = nil, completion: @escaping (Result<Set<Date>, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: referenceDate) else {
            completion(.failure(NutritionCoreError.invalidPayload("Could not calculate the date range for the selected month.")))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.mealLogsCollection)
            .whereField("createdAt", isGreaterThanOrEqualTo: monthInterval.start.timeIntervalSince1970)
            .whereField("createdAt", isLessThan: monthInterval.end.timeIntervalSince1970)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                var days: Set<Date> = []
                for doc in snapshot?.documents ?? [] {
                    let raw = doc.data()["createdAt"]
                    let date = nutritionDate(from: raw)
                    days.insert(calendar.startOfDay(for: date))
                }
                completion(.success(days))
            }
    }

    func getRecentMeals(userId: String? = nil, limit: Int = 50, completion: @escaping (Result<[Meal], Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.mealLogsCollection)
            .order(by: "createdAt", descending: true)
            .limit(to: max(limit, 1))
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let meals = snapshot?.documents.map { Meal(id: $0.documentID, dictionary: $0.data()) } ?? []
                completion(.success(meals.sorted { $0.createdAt > $1.createdAt }))
            }
    }

    func updateMeal(_ meal: Meal, for date: Date? = nil, userId: String? = nil, completion: @escaping (Result<Meal, Error>) -> Void) {
        updateMeal(meal, from: meal.createdAt, to: date ?? meal.createdAt, userId: userId, completion: completion)
    }

    func updateMeal(_ meal: Meal, from originalDate: Date, to newDate: Date, userId: String? = nil, completion: @escaping (Result<Meal, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let oldDocumentID = mealLogDocumentID(for: originalDate, mealId: meal.id)
        let newDocumentID = mealLogDocumentID(for: newDate, mealId: meal.id)

        guard oldDocumentID != newDocumentID else {
            saveMeal(meal, for: newDate, userId: resolvedUserId, completion: completion)
            return
        }

        let mealLogs = db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.mealLogsCollection)

        mealLogs.document(oldDocumentID).delete { [weak self] deleteError in
            guard let self else { return }
            if let deleteError {
                completion(.failure(deleteError))
                return
            }
            self.saveMeal(meal, for: newDate, userId: resolvedUserId, completion: completion)
        }
    }

    func deleteMeal(_ meal: Meal, for date: Date? = nil, userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let logDate = date ?? meal.createdAt
        let documentID = mealLogDocumentID(for: logDate, mealId: meal.id)
        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.mealLogsCollection)
            .document(documentID)
            .delete { [weak self] error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.postNutritionChange()
                completion(.success(()))
            }
    }

    // MARK: - Pinned Meals

    func savePinnedMeal(_ meal: Meal, sortOrder: Int = Int.max, userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let docId = pinnedMealDocumentID(for: meal)
        var data = meal.toDictionary()
        data["sortOrder"] = sortOrder

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.pinnedMealsCollection)
            .document(docId)
            .setData(data) { [weak self] error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.postNutritionChange()
                completion(.success(()))
            }
    }

    func getPinnedMeals(userId: String? = nil, completion: @escaping (Result<[Meal], Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let ref = db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.pinnedMealsCollection)

        ref.order(by: "sortOrder", descending: false).getDocuments { [weak self] snapshot, error in
            if let error {
                self?.log(.warning, "Pinned meal query failed, falling back to unordered read", error: error)
                ref.getDocuments { fallbackSnapshot, fallbackError in
                    if let fallbackError {
                        completion(.failure(fallbackError))
                        return
                    }

                    let meals = fallbackSnapshot?.documents.map { Meal(id: $0.documentID, dictionary: $0.data()) } ?? []
                    completion(.success(meals))
                }
                return
            }

            let meals = snapshot?.documents.map { Meal(id: $0.documentID, dictionary: $0.data()) } ?? []
            completion(.success(meals))
        }
    }

    func deletePinnedMeal(withId mealId: String, userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.pinnedMealsCollection)
            .document(mealId)
            .delete { [weak self] error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.postNutritionChange()
                completion(.success(()))
            }
    }

    func updatePinnedMealOrder(_ orderedDocIds: [String], userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let batch = db.batch()
        let collRef = db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.pinnedMealsCollection)

        for (index, docId) in orderedDocIds.enumerated() {
            batch.updateData(["sortOrder": index], forDocument: collRef.document(docId))
        }

        batch.commit { [weak self] error in
            if let error {
                completion(.failure(error))
                return
            }
            self?.postNutritionChange()
            completion(.success(()))
        }
    }

    // MARK: - Meal Plans

    func saveMealPlan(_ mealPlan: MealPlan, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        saveMealPlan(mealPlan, userId: mealPlan.userId, completion: completion)
    }

    func saveMealPlan(_ mealPlan: MealPlan, userId: String? = nil, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        let resolvedUserId = userId ?? mealPlan.userId
        guard !resolvedUserId.isEmpty else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        var storedMealPlan = mealPlan
        storedMealPlan.userId = resolvedUserId
        storedMealPlan.updatedAt = Date()

        db.collection(NutritionCoreConfiguration.mealPlansCollection)
            .document(storedMealPlan.id)
            .setData(storedMealPlan.toDictionary()) { [weak self] error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.postNutritionChange()
                completion(.success(storedMealPlan))
            }
    }

    func saveMealPlansForAllDays(_ mealPlans: [MealPlan], completion: @escaping (Result<[MealPlan], Error>) -> Void) {
        guard !mealPlans.isEmpty else {
            completion(.success([]))
            return
        }

        let batch = db.batch()
        let storedPlans = mealPlans.map { plan -> MealPlan in
            var updated = plan
            updated.updatedAt = Date()
            return updated
        }

        for mealPlan in storedPlans {
            let docRef = db.collection(NutritionCoreConfiguration.mealPlansCollection).document(mealPlan.id)
            batch.setData(mealPlan.toDictionary(), forDocument: docRef)
        }

        batch.commit { [weak self] error in
            if let error {
                completion(.failure(error))
                return
            }
            self?.postNutritionChange()
            completion(.success(storedPlans))
        }
    }

    func createMealPlan(userId: String? = nil, planName: String, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let planRef = db.collection(NutritionCoreConfiguration.mealPlansCollection).document()
        let mealPlan = MealPlan(id: planRef.documentID, userId: resolvedUserId, planName: planName)
        saveMealPlan(mealPlan, completion: completion)
    }

    func getAllMealPlans(for userId: String? = nil, completion: @escaping (Result<[MealPlan], Error>) -> Void) {
        getAllMealPlansIncludingInactive(for: userId, completion: { result in
            switch result {
            case .success(let pair):
                completion(.success(pair.0))
            case .failure(let error):
                completion(.failure(error))
            }
        })
    }

    func getAllMealPlansIncludingInactive(for userId: String? = nil, completion: @escaping (Result<([MealPlan], [MealPlan]), Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.mealPlansCollection)
            .whereField("userId", isEqualTo: resolvedUserId)
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

                let activePlans = plans.filter { $0.isActive }.sorted { $0.createdAt < $1.createdAt }
                let inactivePlans = plans.filter { !$0.isActive }.sorted { $0.createdAt < $1.createdAt }
                completion(.success((activePlans, inactivePlans)))
            }
    }

    func updateMealPlanName(planId: String, userId: String? = nil, newName: String, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let planRef = db.collection(NutritionCoreConfiguration.mealPlansCollection).document(planId)
        planRef.getDocument { [weak self] document, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let document, document.exists, let data = document.data() else {
                completion(.failure(NutritionCoreError.invalidDocument))
                return
            }

            var mealPlan = MealPlan(dictionary: data)
            mealPlan.id = document.documentID

            guard mealPlan.userId == resolvedUserId else {
                completion(.failure(NutritionCoreError.invalidPayload("Unauthorized: meal plan belongs to a different user.")))
                return
            }

            mealPlan.planName = newName
            mealPlan.updatedAt = Date()
            planRef.setData(mealPlan.toDictionary()) { error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.postNutritionChange()
                completion(.success(mealPlan))
            }
        }
    }

    func deleteMealPlan(planId: String, userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let planRef = db.collection(NutritionCoreConfiguration.mealPlansCollection).document(planId)
        planRef.getDocument { [weak self] document, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let document, document.exists, let data = document.data() else {
                completion(.failure(NutritionCoreError.invalidDocument))
                return
            }

            let mealPlan = MealPlan(dictionary: data)
            guard mealPlan.userId == resolvedUserId else {
                completion(.failure(NutritionCoreError.invalidPayload("Unauthorized: meal plan belongs to a different user.")))
                return
            }

            planRef.delete { error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.postNutritionChange()
                completion(.success(()))
            }
        }
    }

    func addMealToPlan(_ meal: Meal, planId: String, userId: String? = nil, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let planRef = db.collection(NutritionCoreConfiguration.mealPlansCollection).document(planId)
        planRef.getDocument { [weak self] document, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let document, document.exists, let data = document.data() else {
                completion(.failure(NutritionCoreError.invalidDocument))
                return
            }

            var mealPlan = MealPlan(dictionary: data)
            mealPlan.id = planId
            guard mealPlan.userId == resolvedUserId else {
                completion(.failure(NutritionCoreError.invalidPayload("Unauthorized: meal plan belongs to a different user.")))
                return
            }

            mealPlan.addMeal(meal)
            mealPlan.updatedAt = Date()
            planRef.setData(mealPlan.toDictionary()) { error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.postNutritionChange()
                completion(.success(mealPlan))
            }
        }
    }

    func updatePlannedMeal(_ plannedMeal: PlannedMeal, in mealPlan: MealPlan, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        var updatedMealPlan = mealPlan
        updatedMealPlan.updateMeal(plannedMeal)
        saveMealPlan(updatedMealPlan, completion: completion)
    }

    func markPlannedMealAsCompleted(_ plannedMealId: String, in mealPlan: MealPlan, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        var updatedMealPlan = mealPlan
        updatedMealPlan.markMealCompleted(withId: plannedMealId)
        saveMealPlan(updatedMealPlan, completion: completion)
    }

    func removeMealFromPlan(_ plannedMealId: String, planId: String, userId: String? = nil, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let planRef = db.collection(NutritionCoreConfiguration.mealPlansCollection).document(planId)
        planRef.getDocument { [weak self] document, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let document, document.exists, let data = document.data() else {
                completion(.failure(NutritionCoreError.invalidDocument))
                return
            }

            var mealPlan = MealPlan(dictionary: data)
            mealPlan.id = planId
            guard mealPlan.userId == resolvedUserId else {
                completion(.failure(NutritionCoreError.invalidPayload("Unauthorized: meal plan belongs to a different user.")))
                return
            }

            mealPlan.removeMeal(withId: plannedMealId)
            planRef.setData(mealPlan.toDictionary()) { error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.postNutritionChange()
                completion(.success(mealPlan))
            }
        }
    }

    func reorderMealInPlan(_ plannedMealId: String, to newOrder: Int, planId: String, userId: String? = nil, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let planRef = db.collection(NutritionCoreConfiguration.mealPlansCollection).document(planId)
        planRef.getDocument { [weak self] document, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let document, document.exists, let data = document.data() else {
                completion(.failure(NutritionCoreError.invalidDocument))
                return
            }

            var mealPlan = MealPlan(dictionary: data)
            mealPlan.id = planId
            guard mealPlan.userId == resolvedUserId else {
                completion(.failure(NutritionCoreError.invalidPayload("Unauthorized: meal plan belongs to a different user.")))
                return
            }

            mealPlan.reorderMeal(withId: plannedMealId, to: newOrder)
            planRef.setData(mealPlan.toDictionary()) { error in
                if let error {
                    completion(.failure(error))
                    return
                }
                self?.postNutritionChange()
                completion(.success(mealPlan))
            }
        }
    }

    func reactivateMealPlan(planId: String, userId: String? = nil, completion: @escaping (Result<MealPlan, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let planRef = db.collection(NutritionCoreConfiguration.mealPlansCollection).document(planId)
        planRef.getDocument { [weak self] document, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let document, document.exists, let data = document.data() else {
                completion(.failure(NutritionCoreError.invalidDocument))
                return
            }

            var mealPlan = MealPlan(dictionary: data)
            mealPlan.id = planId
            guard mealPlan.userId == resolvedUserId else {
                completion(.failure(NutritionCoreError.invalidPayload("Unauthorized: meal plan belongs to a different user.")))
                return
            }

            mealPlan.isActive = true
            mealPlan.updatedAt = Date()
            self?.saveMealPlan(mealPlan, completion: completion)
        }
    }

    // MARK: - Helpers

    private func mealLogDocumentID(for date: Date, mealId: String) -> String {
        // Loaded meals carry the full Firestore document ID as `meal.id` (e.g.
        // "04202026meal_xxx"). Re-prefixing here would produce a double prefix
        // and a non-existent doc path, causing silent no-ops on update/delete.
        // Strip any leading 8-digit `MMddyyyy` prefix before re-prefixing.
        "\(date.nutritionMealLogDocumentPrefix)\(Self.rawMealID(from: mealId))"
    }

    fileprivate static func rawMealID(from mealId: String) -> String {
        guard mealId.count > 8 else { return mealId }
        let prefixIndex = mealId.index(mealId.startIndex, offsetBy: 8)
        let prefix = mealId[mealId.startIndex..<prefixIndex]
        guard prefix.allSatisfy({ $0.isASCII && $0.isNumber }) else { return mealId }
        return String(mealId[prefixIndex..<mealId.endIndex])
    }

    private func pinnedMealDocumentID(for meal: Meal) -> String {
        meal.name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
    }

    private func dateRange(for date: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) else { return nil }
        return (start, end)
    }

    private func postNutritionChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: NutritionCoreNotification.dataDidChange, object: nil)
        }
    }

    private func log(_ level: NutritionCoreLogLevel, _ message: String, error: Error? = nil) {
        NutritionCoreLogger.log(level, message: message, error: error)
    }
}
