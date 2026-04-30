import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum MealPlanningScreenMode: String, CaseIterable, Identifiable {
    case plans = "Plans"
    case noraPlans = "Nora's Plans"

    var id: String { rawValue }
}

struct NoraGeneratedPlan: Identifiable, Hashable {
    let id: String
    let plan: MacraSuggestedMealPlan
    let generatedAt: Date
    let isCurrent: Bool
    let inputMacros: MacroSummary?
    let goal: String?
    let dietaryPreference: String?
    let extraContext: String?

    struct MacroSummary: Hashable {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
    }
}

final class NoraPlansViewModel: ObservableObject {
    @Published var plans: [NoraGeneratedPlan] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let userId: String

    init(userId: String) {
        self.userId = userId
    }

    func load() {
        guard !userId.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        let db = Firestore.firestore()
        let planRoot = db.collection("users").document(userId).collection("macraSuggestedMealPlans")
        let historyRef = planRoot.document("history").collection("items")

        let group = DispatchGroup()
        var collected: [NoraGeneratedPlan] = []
        var loadError: Error?

        group.enter()
        planRoot.document("current").getDocument { snapshot, error in
            defer { group.leave() }
            if let error = error {
                loadError = error
                return
            }
            guard let data = snapshot?.data() else { return }
            // User-mirrored plans (written by selectPlan) live in the same
            // doc but aren't Nora-generated — exclude them from this view.
            if (data["source"] as? String) == "user-selected" { return }
            if let plan = Self.decodePlan(from: data, docId: "current", isCurrent: true) {
                collected.append(plan)
            }
        }

        group.enter()
        historyRef.getDocuments { snapshot, error in
            defer { group.leave() }
            if let error = error {
                loadError = error
                return
            }
            guard let documents = snapshot?.documents else { return }
            for doc in documents {
                let data = doc.data()
                if (data["source"] as? String) == "user-selected" { continue }
                if let plan = Self.decodePlan(from: data, docId: doc.documentID, isCurrent: false) {
                    collected.append(plan)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isLoading = false
            if let error = loadError {
                self.errorMessage = error.localizedDescription
                return
            }
            self.plans = collected.sorted { $0.generatedAt > $1.generatedAt }
        }
    }

    private static func decodePlan(from data: [String: Any], docId: String, isCurrent: Bool) -> NoraGeneratedPlan? {
        guard let planDict = data["plan"] as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: planDict),
              let plan = try? JSONDecoder().decode(MacraSuggestedMealPlan.self, from: jsonData) else {
            return nil
        }

        let generatedAtMillis = data["generatedAt"] as? Double ?? 0
        let generatedAt = generatedAtMillis > 0 ? Date(timeIntervalSince1970: generatedAtMillis / 1000) : Date()

        var macros: NoraGeneratedPlan.MacroSummary?
        if let dict = data["inputMacros"] as? [String: Any] {
            macros = NoraGeneratedPlan.MacroSummary(
                calories: Int(dict["calories"] as? Double ?? Double(dict["calories"] as? Int ?? 0)),
                protein: Int(dict["protein"] as? Double ?? Double(dict["protein"] as? Int ?? 0)),
                carbs: Int(dict["carbs"] as? Double ?? Double(dict["carbs"] as? Int ?? 0)),
                fat: Int(dict["fat"] as? Double ?? Double(dict["fat"] as? Int ?? 0))
            )
        }

        return NoraGeneratedPlan(
            id: docId,
            plan: plan,
            generatedAt: generatedAt,
            isCurrent: isCurrent,
            inputMacros: macros,
            goal: (data["goal"] as? String)?.nonEmpty,
            dietaryPreference: (data["dietaryPreference"] as? String)?.nonEmpty,
            extraContext: (data["extraContext"] as? String)?.nonEmpty
        )
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

final class MealPlanningRootViewModel: ObservableObject {
    @Published var mealPlans: [MealPlan] = []
    @Published var recentMeals: [Meal] = []
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    let userId: String
    let store: any MealPlanningStore

    init(userId: String, store: any MealPlanningStore) {
        self.userId = userId
        self.store = store
    }

    var orderedMealPlans: [MealPlan] {
        mealPlans.sorted { $0.updatedAt > $1.updatedAt }
    }

    var activePlanCount: Int {
        mealPlans.filter { $0.isActive }.count
    }

    var totalPlannedMeals: Int {
        mealPlans.reduce(0) { $0 + $1.plannedMeals.count }
    }

    func loadInitialData() {
        loadMealPlans()
        loadRecentMeals()
    }

    func refresh() {
        loadInitialData()
    }

    func loadMealPlans() {
        isLoading = true
        print("[Macra][Playbook.load] Fetching meal plans for user \(userId)")
        store.fetchMealPlans(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let plans):
                    self.mealPlans = plans.sorted { $0.updatedAt > $1.updatedAt }
                    let activePlans = self.mealPlans.filter { $0.isActive }
                    print("[Macra][Playbook.load] Loaded \(self.mealPlans.count) plans, \(activePlans.count) active: \(activePlans.map { $0.planName })")
                    self.reconcileActivePlanWithCurrent()
                case .failure(let error):
                    print("[Macra][Playbook.load] ❌ Fetch failed: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// On every load, ensure the playbook's active plan matches what's
    /// stored at `macraSuggestedMealPlans/current` (which drives Today's fuel).
    /// If an active plan exists but the current doc was written by a different
    /// source (or doesn't reflect this plan's name), re-mirror it. This catches
    /// users whose active flag was set before the mirror code shipped.
    private func reconcileActivePlanWithCurrent() {
        guard let active = mealPlans.first(where: { $0.isActive }) else {
            print("[Macra][Playbook.reconcile] No active plan to reconcile")
            return
        }
        guard !userId.isEmpty else { return }

        let currentRef = Firestore.firestore()
            .collection("users").document(userId)
            .collection("macraSuggestedMealPlans").document("current")

        currentRef.getDocument { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                print("[Macra][Playbook.reconcile] ❌ Failed to read current doc: \(error.localizedDescription)")
                return
            }
            let data = snapshot?.data()
            let source = data?["source"] as? String ?? "<none>"
            let mirroredName = data?["planName"] as? String ?? "<none>"
            print("[Macra][Playbook.reconcile] Active plan='\(active.planName)' | current.source='\(source)' | current.planName='\(mirroredName)'")

            let needsMirror = source != "user-selected" || mirroredName != active.planName
            if needsMirror {
                print("[Macra][Playbook.reconcile] ⚠️ Mismatch detected — re-mirroring active plan to current")
                self.mirrorPlanAsCurrent(active)
            } else {
                print("[Macra][Playbook.reconcile] ✓ Already in sync")
            }
        }
    }

    func loadRecentMeals(limit: Int = 40) {
        store.fetchRecentMeals(userId: userId, limit: limit) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let meals):
                    self.recentMeals = meals.sorted { $0.createdAt > $1.createdAt }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func createPlan(name: String, sourceMeals: [Meal] = [], completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a plan name."
            completion?(.failure(MealPlanningStoreError.invalidData))
            return
        }

        isLoading = true
        store.createMealPlan(userId: userId, planName: name, sourceMeals: sourceMeals) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let plan):
                    self.mealPlans.append(plan)
                    self.statusMessage = "Created \(plan.planName)."
                    completion?(.success(plan))
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    completion?(.failure(error))
                }
            }
        }
    }

    func createPlanFromDate(_ date: Date, name: String? = nil, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        store.fetchMeals(for: date, userId: userId) { [weak self] result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.errorMessage = error.localizedDescription
                    completion?(.failure(error))
                }
            case .success(let meals):
                let defaultName = name ?? "\(MealPlanningDates.longDateFormatter.string(from: date)) Plan"
                self?.createPlan(name: defaultName, sourceMeals: meals, completion: completion)
            }
        }
    }

    func renamePlan(planId: String, newName: String, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        store.updateMealPlanName(planId: planId, userId: userId, newName: newName) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let updatedPlan):
                    if let index = self.mealPlans.firstIndex(where: { $0.id == planId }) {
                        self.mealPlans[index] = updatedPlan
                    }
                    self.statusMessage = "Renamed plan."
                    completion?(.success(updatedPlan))
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    completion?(.failure(error))
                }
            }
        }
    }

    func deletePlan(planId: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        store.deleteMealPlan(planId: planId, userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.mealPlans.removeAll { $0.id == planId }
                    self.statusMessage = "Deleted meal plan."
                    completion?(.success(()))
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    completion?(.failure(error))
                }
            }
        }
    }

    func addMealsToPlan(_ meals: [Meal], planId: String, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        guard !meals.isEmpty else {
            completion?(.failure(MealPlanningStoreError.invalidData))
            return
        }

        guard let plan = plan(with: planId) else {
            completion?(.failure(MealPlanningStoreError.notFound))
            return
        }

        var updatedPlan = plan
        updatedPlan.addMeals(meals)

        persistPlan(updatedPlan, completion: completion)
    }

    func removePlannedMeal(plannedMealId: String, planId: String, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        guard let plan = plan(with: planId) else {
            completion?(.failure(MealPlanningStoreError.notFound))
            return
        }

        var updatedPlan = plan
        updatedPlan.removeMeal(withId: plannedMealId)
        persistPlan(updatedPlan, completion: completion)
    }

    func reorderPlannedMeal(plannedMealId: String, to newOrder: Int, planId: String, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        guard let plan = plan(with: planId) else {
            completion?(.failure(MealPlanningStoreError.notFound))
            return
        }

        var updatedPlan = plan
        updatedPlan.reorderMeal(withId: plannedMealId, to: newOrder)
        persistPlan(updatedPlan, completion: completion)
    }

    func markPlannedMealCompleted(plannedMealId: String, planId: String, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        guard let plan = plan(with: planId) else {
            completion?(.failure(MealPlanningStoreError.notFound))
            return
        }

        var updatedPlan = plan
        updatedPlan.markMealCompleted(withId: plannedMealId)
        persistPlan(updatedPlan, completion: completion)
    }

    func markPlannedMealIncomplete(plannedMealId: String, planId: String, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        guard let plan = plan(with: planId) else {
            completion?(.failure(MealPlanningStoreError.notFound))
            return
        }

        var updatedPlan = plan
        updatedPlan.markMealIncomplete(withId: plannedMealId)
        persistPlan(updatedPlan, completion: completion)
    }

    func combinePlannedMeal(primaryPlannedMealId: String, secondaryPlannedMealId: String, planId: String, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        guard let plan = plan(with: planId) else {
            completion?(.failure(MealPlanningStoreError.notFound))
            return
        }

        var updatedPlan = plan
        updatedPlan.combineMeal(withId: secondaryPlannedMealId, into: primaryPlannedMealId)
        persistPlan(updatedPlan, completion: completion)
    }

    func separatePlannedMeal(plannedMealId: String, planId: String, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        guard let plan = plan(with: planId) else {
            completion?(.failure(MealPlanningStoreError.notFound))
            return
        }

        var updatedPlan = plan
        updatedPlan.separateMeal(withId: plannedMealId)
        persistPlan(updatedPlan, completion: completion)
    }

    func logPlannedMeal(plannedMeal: PlannedMeal, planId: String, at date: Date, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let mealsToLog = plannedMeal.meals.map { meal -> Meal in
            var copy = meal
            copy.id = MealPlanningIDs.make(prefix: "meal")
            copy.createdAt = date
            copy.updatedAt = Date()
            return copy
        }

        store.logMeals(mealsToLog, userId: userId, at: date) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.markPlannedMealCompleted(plannedMealId: plannedMeal.id, planId: planId)
                    self.statusMessage = "Logged \(plannedMeal.name)."
                    completion?(.success(()))
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    completion?(.failure(error))
                }
            }
        }
    }

    func selectPlan(planId: String, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        guard let target = plan(with: planId) else {
            print("[Macra][Playbook.selectPlan] ❌ Plan not found: \(planId)")
            completion?(.failure(MealPlanningStoreError.notFound))
            return
        }
        print("[Macra][Playbook.selectPlan] ▶︎ Selecting '\(target.planName)' (id=\(planId))")

        let group = DispatchGroup()
        var saveError: Error?
        let lock = NSLock()
        var updatedActive: MealPlan = target

        // Deactivate every other plan that's currently active so only one
        // playbook plan reads as active at a time.
        for var other in mealPlans where other.isActive && other.id != planId {
            other.isActive = false
            other.updatedAt = Date()
            group.enter()
            store.saveMealPlan(other) { result in
                if case .failure(let error) = result {
                    lock.lock(); if saveError == nil { saveError = error }; lock.unlock()
                }
                group.leave()
            }
        }

        var promoted = target
        promoted.isActive = true
        promoted.updatedAt = Date()
        group.enter()
        store.saveMealPlan(promoted) { result in
            switch result {
            case .success(let saved):
                updatedActive = saved
            case .failure(let error):
                lock.lock(); if saveError == nil { saveError = error }; lock.unlock()
            }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if let saveError {
                self.errorMessage = saveError.localizedDescription
                completion?(.failure(saveError))
                return
            }
            self.mealPlans = self.mealPlans.map { existing in
                if existing.id == updatedActive.id { return updatedActive }
                if existing.isActive { var copy = existing; copy.isActive = false; return copy }
                return existing
            }
            self.statusMessage = "Selected \(updatedActive.planName)."
            // Mirror the selected plan to `macraSuggestedMealPlans/current` so
            // Today's fuel actually reflects the user's choice. Without this,
            // selectPlan would only flip the playbook flag and the daily plan
            // screen would keep showing the old Nora plan.
            self.mirrorPlanAsCurrent(updatedActive)
            completion?(.success(updatedActive))
        }
    }

    private func mirrorPlanAsCurrent(_ plan: MealPlan) {
        guard !userId.isEmpty else {
            print("[Macra][Playbook.mirror] ❌ No userId, skipping mirror")
            return
        }
        let db = Firestore.firestore()
        let planRoot = db.collection("users").document(userId).collection("macraSuggestedMealPlans")
        let currentRef = planRoot.document("current")

        let now = Date().timeIntervalSince1970 * 1000
        let suggestedDict = Self.suggestedPlanDict(from: plan)
        let mealCount = (suggestedDict["meals"] as? [[String: Any]])?.count ?? 0

        print("[Macra][Playbook.mirror] ▶︎ Mirroring '\(plan.planName)' to macraSuggestedMealPlans/current — \(mealCount) meals, \(plan.totalCalories) cal")

        let payload: [String: Any] = [
            "userId": userId,
            "plan": suggestedDict,
            "inputMacros": [
                "calories": plan.totalCalories,
                "protein": plan.totalProtein,
                "carbs": plan.totalCarbs,
                "fat": plan.totalFat
            ],
            "generatedAt": now,
            "source": "user-selected",
            "planName": plan.planName
        ]

        // Archive the current doc to history before overwriting, mirroring
        // the netlify generator's behavior so prior plans aren't lost.
        currentRef.getDocument { snapshot, _ in
            if let data = snapshot?.data(), data["plan"] != nil {
                let archiveTimestamp = (data["generatedAt"] as? Double) ?? now
                let historyId = String(Int(archiveTimestamp))
                let priorSource = data["source"] as? String ?? "nora"
                let priorName = data["planName"] as? String ?? "<unnamed>"
                print("[Macra][Playbook.mirror] Archiving prior current (source='\(priorSource)', name='\(priorName)') → history/\(historyId)")
                var archived = data
                archived["archivedAt"] = now
                planRoot.document("history").collection("items")
                    .document(historyId)
                    .setData(archived, merge: false)
            } else {
                print("[Macra][Playbook.mirror] No prior current doc to archive")
            }
            currentRef.setData(payload, merge: false) { writeError in
                if let writeError {
                    print("[Macra][Playbook.mirror] ❌ Write failed: \(writeError.localizedDescription)")
                } else {
                    print("[Macra][Playbook.mirror] ✓ Wrote new current doc — broadcasting activePlanDidChange")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NutritionCoreNotification.activePlanDidChange, object: nil)
                    }
                }
            }
        }
    }

    private static func suggestedPlanDict(from plan: MealPlan) -> [String: Any] {
        let meals: [[String: Any]] = plan.orderedMeals.map { plannedMeal in
            let title: String
            if plannedMeal.meals.count == 1, let firstName = plannedMeal.meals.first?.name, !firstName.isEmpty {
                title = firstName
            } else {
                title = "Meal \(plannedMeal.order)"
            }
            let items: [[String: Any]] = plannedMeal.meals.map { meal in
                [
                    "name": meal.name,
                    "quantity": meal.ingredients.joined(separator: ", "),
                    "calories": meal.calories,
                    "protein": meal.protein,
                    "carbs": meal.carbs,
                    "fat": meal.fat
                ]
            }
            return [
                "title": title,
                "items": items
            ]
        }
        return [
            "meals": meals,
            "notes": ""
        ]
    }

    private func persistPlan(_ plan: MealPlan, completion: ((Result<MealPlan, Error>) -> Void)? = nil) {
        store.saveMealPlan(plan) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let updatedPlan):
                    if let index = self.mealPlans.firstIndex(where: { $0.id == updatedPlan.id }) {
                        self.mealPlans[index] = updatedPlan
                    } else {
                        self.mealPlans.append(updatedPlan)
                    }
                    // Keep Today's fuel in sync with edits to the active plan.
                    if updatedPlan.isActive {
                        self.mirrorPlanAsCurrent(updatedPlan)
                    }
                    completion?(.success(updatedPlan))
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    completion?(.failure(error))
                }
            }
        }
    }

    private func plan(with id: String) -> MealPlan? {
        mealPlans.first { $0.id == id }
    }
}

final class MacroTargetsViewModel: ObservableObject {
    @Published var currentRecommendation: MacroRecommendation?
    @Published var recommendations: [MacroRecommendation] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    /// Deduplicates recommendations with identical macro values + dayOfWeek, keeping only the
    /// most recently updated instance of each unique combination. Also drops any recommendation
    /// that matches the current target (to avoid showing it twice). Sorted newest-first.
    var deduplicatedRecommendations: [MacroRecommendation] {
        struct Key: Hashable {
            let calories: Int
            let protein: Int
            let carbs: Int
            let fat: Int
            let dayOfWeek: String?
        }

        var latest: [Key: MacroRecommendation] = [:]
        for recommendation in recommendations {
            let key = Key(
                calories: recommendation.calories,
                protein: recommendation.protein,
                carbs: recommendation.carbs,
                fat: recommendation.fat,
                dayOfWeek: recommendation.dayOfWeek
            )
            if let existing = latest[key] {
                if recommendation.updatedAt > existing.updatedAt {
                    latest[key] = recommendation
                }
            } else {
                latest[key] = recommendation
            }
        }

        let currentKey = currentRecommendation.map {
            Key(
                calories: $0.calories,
                protein: $0.protein,
                carbs: $0.carbs,
                fat: $0.fat,
                dayOfWeek: $0.dayOfWeek
            )
        }

        return latest
            .filter { key, _ in key != currentKey }
            .values
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @Published var scope: MacroTargetScope = .global
    @Published var goal: MacroTargetGoal = .maintain
    @Published var activity: MacroActivityLevel = .moderate
    @Published var bodyWeightLbs: Double = 180
    @Published var calories: Int = 2400
    @Published var protein: Int = 180
    @Published var carbs: Int = 240
    @Published var fat: Int = 70

    // MARK: - Nora assess-macros state

    /// Free-form text the user feeds Nora — can be a goal description, a
    /// paste of a plan, preferences, etc. Combined with any attached images
    /// when we call the analyzer.
    @Published var noraPrompt: String = ""

    /// Optional image attachments (e.g. screenshots of a meal plan from
    /// another app, a coach's whiteboard photo, a grocery haul). Sent to
    /// Nora's vision model as inline JPEGs.
    @Published var noraImages: [UIImage] = []

    /// True while the analyzer request is in flight — drives the UI spinner
    /// and disables the Generate button.
    @Published var isGeneratingWithNora: Bool = false

    /// The most recent Nora result. Set to non-nil to present the confirmation
    /// sheet; set back to nil to dismiss it.
    @Published var noraResult: GPTService.NoraMacroAnalysis?

    let userId: String
    let store: any MealPlanningStore

    init(userId: String, store: any MealPlanningStore) {
        self.userId = userId
        self.store = store
    }

    func load() {
        isLoading = true

        store.fetchCurrentMacroRecommendation(userId: userId, dayOfWeek: nil) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let recommendation):
                    self.currentRecommendation = recommendation
                    if let recommendation {
                        self.calories = recommendation.calories
                        self.protein = recommendation.protein
                        self.carbs = recommendation.carbs
                        self.fat = recommendation.fat
                        UserService.sharedInstance.currentMacroTarget = recommendation
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isLoading = false
            }
        }

        store.fetchMacroRecommendations(userId: userId) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let recommendations):
                    self.recommendations = recommendations
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func generateRecommendation() {
        let baseCalories = bodyWeightLbs * activity.calorieMultiplier
        let adjustedCalories: Double

        switch goal {
        case .lose:
            adjustedCalories = baseCalories - 275
        case .maintain:
            adjustedCalories = baseCalories
        case .gain:
            adjustedCalories = baseCalories + 225
        }

        let suggestedProtein: Double
        switch goal {
        case .lose:
            suggestedProtein = bodyWeightLbs * 1.05
        case .maintain:
            suggestedProtein = bodyWeightLbs * 0.9
        case .gain:
            suggestedProtein = bodyWeightLbs * 1.0
        }

        let proteinCalories = suggestedProtein * 4
        let fatCalories = adjustedCalories * 0.28
        let suggestedFat = max(45, fatCalories / 9.0)
        let carbCalories = max(0, adjustedCalories - proteinCalories - (suggestedFat * 9))
        let suggestedCarbs = carbCalories / 4.0

        calories = max(1200, Int(adjustedCalories.rounded()))
        protein = max(60, Int(suggestedProtein.rounded()))
        fat = max(35, Int(suggestedFat.rounded()))
        carbs = max(50, Int(suggestedCarbs.rounded()))
        statusMessage = "Generated a macro target from your assessment."
    }

    func saveRecommendation() {
        let recommendation = MacroRecommendation(
            userId: userId,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            dayOfWeek: scope.firestoreValue
        )

        isSaving = true
        store.saveMacroRecommendation(recommendation) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSaving = false
                switch result {
                case .success(let saved):
                    if let index = self.recommendations.firstIndex(where: { $0.id == saved.id }) {
                        self.recommendations[index] = saved
                    } else {
                        self.recommendations.insert(saved, at: 0)
                    }
                    if saved.dayOfWeek == nil {
                        self.currentRecommendation = saved
                        UserService.sharedInstance.currentMacroTarget = saved
                    }
                    self.statusMessage = "Saved macro targets."
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Nora AI assessment

    /// Calls Nora through the server bridge with whatever context the user
    /// assembled (text prompt + optional images + their current inputs) and
    /// publishes the result as `noraResult`. The result sheet reads that
    /// published value to drive the confirmation flow.
    func analyzeWithNora() {
        let trimmed = noraPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty || !noraImages.isEmpty else {
            errorMessage = "Add a prompt or an image so Nora has something to work with."
            return
        }

        isGeneratingWithNora = true
        statusMessage = nil

        let bodyContext: String = {
            let goalText: String = {
                switch goal {
                case .lose: return "lose fat"
                case .maintain: return "maintain"
                case .gain: return "gain muscle"
                }
            }()
            let activityText = activity.rawValue.lowercased()
            let weightLine = "Body weight: \(Int(bodyWeightLbs)) lb."
            return "Goal: \(goalText). Activity level: \(activityText). \(weightLine)"
        }()

        let promptCopy = trimmed
        let imagesCopy = noraImages

        GPTService.sharedInstance.analyzeMacrosWithNora(
            prompt: promptCopy,
            images: imagesCopy,
            bodyContext: bodyContext
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isGeneratingWithNora = false
                switch result {
                case .success(let analysis):
                    self.noraResult = analysis
                    // Pre-populate the editor's macro fields so the user can
                    // tweak after they close the result sheet without losing
                    // Nora's numbers.
                    self.calories = analysis.macros.calories
                    self.protein = analysis.macros.protein
                    self.carbs = analysis.macros.carbs
                    self.fat = analysis.macros.fat

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// User answered "yes" to both questions: persist Nora's macros AND
    /// replace the active meal plan with the one Nora suggested.
    func applyNoraResult(_ result: GPTService.NoraMacroAnalysis, onComplete: @escaping () -> Void) {
        print("[Macra][MacroTargets.applyNoraResult] Saving macros + meal plan")
        saveMacroTargets(from: result) { [weak self] macroError in
            if let macroError {
                self?.errorMessage = macroError.localizedDescription
                onComplete()
                return
            }

            self?.replaceActiveMealPlan(with: result) { [weak self] planError in
                if let planError {
                    self?.errorMessage = planError.localizedDescription
                }
                onComplete()
            }
        }
    }

    /// User answered "no" to the meal plan, then "yes" to macros: keep Nora's
    /// macro numbers but don't touch their plan.
    func applyNoraMacrosOnly(from result: GPTService.NoraMacroAnalysis, onComplete: (() -> Void)? = nil) {
        print("[Macra][MacroTargets.applyNoraMacrosOnly] Saving macros only")
        saveMacroTargets(from: result) { _ in
            onComplete?()
        }
    }

    private func saveMacroTargets(from analysis: GPTService.NoraMacroAnalysis, completion: @escaping (Error?) -> Void) {
        let targets = Self.macroRecommendations(from: analysis, userId: userId)
        guard !targets.isEmpty else {
            completion(nil)
            return
        }

        calories = analysis.macros.calories
        protein = analysis.macros.protein
        carbs = analysis.macros.carbs
        fat = analysis.macros.fat

        isSaving = true
        let group = DispatchGroup()
        let lock = NSLock()
        var savedTargets: [MacroRecommendation] = []
        var saveError: Error?

        for target in targets {
            group.enter()
            store.saveMacroRecommendation(target) { result in
                lock.lock()
                switch result {
                case .success(let saved):
                    savedTargets.append(saved)
                case .failure(let error):
                    if saveError == nil {
                        saveError = error
                    }
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isSaving = false

            if let saveError {
                self.errorMessage = saveError.localizedDescription
                completion(saveError)
                return
            }

            for saved in savedTargets {
                if let index = self.recommendations.firstIndex(where: { $0.id == saved.id }) {
                    self.recommendations[index] = saved
                } else {
                    self.recommendations.insert(saved, at: 0)
                }

                if saved.dayOfWeek == nil {
                    self.currentRecommendation = saved
                    UserService.sharedInstance.currentMacroTarget = saved
                }
            }

            self.recommendations = self.deduplicatedRecommendations
            self.statusMessage = Self.noraSaveStatus(for: analysis)
            completion(nil)
        }
    }

    private static func macroRecommendations(from analysis: GPTService.NoraMacroAnalysis, userId: String) -> [MacroRecommendation] {
        var keyedTargets: [String: MacroRecommendation] = [
            "global": MacroRecommendation(
                userId: userId,
                calories: analysis.macros.calories,
                protein: analysis.macros.protein,
                carbs: analysis.macros.carbs,
                fat: analysis.macros.fat,
                dayOfWeek: nil
            )
        ]

        for scoped in analysis.scopedMacros {
            for day in scoped.days {
                guard let normalizedDay = normalizedDayOfWeek(day) else { continue }
                keyedTargets[normalizedDay] = MacroRecommendation(
                    userId: userId,
                    calories: scoped.macros.calories,
                    protein: scoped.macros.protein,
                    carbs: scoped.macros.carbs,
                    fat: scoped.macros.fat,
                    dayOfWeek: normalizedDay
                )
            }
        }

        let dayOrder = ["global", "mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        return dayOrder.compactMap { keyedTargets[$0] }
    }

    private static func normalizedDayOfWeek(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
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
            return nil
        }
    }

    private static func noraSaveStatus(for analysis: GPTService.NoraMacroAnalysis) -> String {
        let scopedDays = analysis.scopedMacros
            .flatMap(\.days)
            .compactMap(normalizedDayOfWeek)
            .removeDuplicates()

        guard !scopedDays.isEmpty else {
            return "Saved macro targets."
        }

        let labels = scopedDays.map { $0.uppercased() }.joined(separator: ", ")
        return "Saved macro targets for all days + \(labels)."
    }

    /// Deactivates every currently active meal plan for the user and saves a
    /// new plan built from Nora's meals. A "plan" here is one day's schedule —
    /// matches the pattern `MealPlanningStore.saveMealPlan` expects.
    private func replaceActiveMealPlan(
        with analysis: GPTService.NoraMacroAnalysis,
        completion: @escaping (Error?) -> Void
    ) {
        store.fetchMealPlans(userId: userId) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let existing):
                let group = DispatchGroup()
                var deactivateError: Error?

                // Deactivate (rather than delete) existing plans so history
                // is preserved and the user can revert if they want to.
                for var plan in existing where plan.isActive {
                    plan.isActive = false
                    plan.updatedAt = Date()
                    group.enter()
                    self.store.saveMealPlan(plan) { saveResult in
                        if case .failure(let err) = saveResult { deactivateError = err }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    if let deactivateError {
                        completion(deactivateError)
                        return
                    }

                    let newPlan = Self.mealPlan(from: analysis, userId: self.userId)
                    self.store.saveMealPlan(newPlan) { saveResult in
                        DispatchQueue.main.async {
                            switch saveResult {
                            case .success:
                                self.statusMessage = "Saved Nora's plan as your active meal plan."
                                completion(nil)
                            case .failure(let error):
                                completion(error)
                            }
                        }
                    }
                }

            case .failure(let error):
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    /// Builds a persistable `MealPlan` from Nora's analysis. Each
    /// `PlanMeal` becomes a single `Meal` (macros summed) so the user's plan
    /// stays readable, and the component items land in the meal's
    /// `ingredients` list for transparency.
    private static func mealPlan(from analysis: GPTService.NoraMacroAnalysis, userId: String) -> MealPlan {
        let plannedMeals: [PlannedMeal] = analysis.meals.enumerated().map { index, planMeal in
            let ingredientLines = planMeal.items.map { item -> String in
                let qty = item.quantity.isEmpty ? item.name : "\(item.quantity) \(item.name)"
                return qty
            }

            let meal = Meal(
                name: planMeal.title,
                categories: [.unknown],
                ingredients: ingredientLines,
                caption: planMeal.notes ?? "",
                calories: planMeal.totalCalories,
                protein: planMeal.totalProtein,
                fat: planMeal.totalFat,
                carbs: planMeal.totalCarbs,
                image: "",
                entryMethod: .unknown
            )

            return PlannedMeal(
                meal: meal,
                order: index + 1,
                notes: planMeal.notes
            )
        }

        return MealPlan(
            userId: userId,
            planName: analysis.planName.isEmpty ? "Nora's plan" : analysis.planName,
            plannedMeals: plannedMeals
        )
    }

    func recommendation(for scope: MacroTargetScope) -> MacroRecommendation? {
        switch scope {
        case .global:
            return recommendations.first(where: { $0.dayOfWeek == nil })
        case .monday:
            return recommendations.first(where: { $0.dayOfWeek?.lowercased() == "mon" })
        case .tuesday:
            return recommendations.first(where: { $0.dayOfWeek?.lowercased() == "tue" })
        case .wednesday:
            return recommendations.first(where: { $0.dayOfWeek?.lowercased() == "wed" })
        case .thursday:
            return recommendations.first(where: { $0.dayOfWeek?.lowercased() == "thu" })
        case .friday:
            return recommendations.first(where: { $0.dayOfWeek?.lowercased() == "fri" })
        case .saturday:
            return recommendations.first(where: { $0.dayOfWeek?.lowercased() == "sat" })
        case .sunday:
            return recommendations.first(where: { $0.dayOfWeek?.lowercased() == "sun" })
        }
    }
}

extension MacroActivityLevel {
    var calorieMultiplier: Double {
        switch self {
        case .light: return 12.5
        case .moderate: return 14.0
        case .active: return 15.5
        case .veryActive: return 16.5
        }
    }
}
