import Foundation

struct PlannedMeal: Identifiable, Hashable {
    var id: String
    var meals: [Meal]
    var order: Int
    var notes: String?
    var isCompleted: Bool
    var completedAt: Date?

    init(
        id: String = generateUniqueID(prefix: "planned_meal"),
        meals: [Meal],
        order: Int,
        notes: String? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.meals = meals
        self.order = order
        self.notes = notes
        self.isCompleted = isCompleted
        self.completedAt = completedAt
    }

    init(
        id: String = generateUniqueID(prefix: "planned_meal"),
        meal: Meal,
        order: Int,
        notes: String? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.init(id: id, meals: [meal], order: order, notes: notes, isCompleted: isCompleted, completedAt: completedAt)
    }

    init(dictionary: [String: Any]) {
        self.id = dictionary["id"] as? String ?? generateUniqueID(prefix: "planned_meal")
        self.order = nutritionInt(from: dictionary["order"])
        self.notes = dictionary["notes"] as? String
        self.isCompleted = dictionary["isCompleted"] as? Bool ?? false
        self.completedAt = nutritionOptionalDate(from: dictionary["completedAt"])

        if let mealsData = dictionary["meals"] as? [[String: Any]] {
            self.meals = mealsData.map { mealData in
                let mealId = mealData["id"] as? String ?? generateUniqueID(prefix: "meal")
                return Meal(id: mealId, dictionary: mealData)
            }
        } else if let mealData = dictionary["meal"] as? [String: Any] {
            let mealId = mealData["id"] as? String ?? generateUniqueID(prefix: "meal")
            self.meals = [Meal(id: mealId, dictionary: mealData)]
        } else {
            self.meals = []
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "meals": meals.map { $0.toDictionary() },
            "order": order,
            "isCompleted": isCompleted
        ]

        if let notes { dict["notes"] = notes }
        if let completedAt { dict["completedAt"] = completedAt.timeIntervalSince1970 }
        return dict
    }

    var name: String {
        if meals.count == 1 {
            return meals.first?.name ?? "Unknown Meal"
        }
        return meals.map(\.name).joined(separator: " + ")
    }

    var calories: Int { meals.reduce(0) { $0 + $1.calories } }
    var protein: Int { meals.reduce(0) { $0 + $1.protein } }
    var carbs: Int { meals.reduce(0) { $0 + $1.carbs } }
    var fat: Int { meals.reduce(0) { $0 + $1.fat } }

    var sugars: Int { meals.reduce(0) { $0 + ($1.sugars ?? 0) } }
    var dietaryFiber: Int { meals.reduce(0) { $0 + ($1.dietaryFiber ?? 0) } }
    var sugarAlcohols: Int { meals.reduce(0) { $0 + ($1.sugarAlcohols ?? 0) } }
    var sodium: Int { meals.reduce(0) { $0 + ($1.sodium ?? 0) } }
    var cholesterol: Int { meals.reduce(0) { $0 + ($1.cholesterol ?? 0) } }
    var saturatedFat: Int { meals.reduce(0) { $0 + ($1.saturatedFat ?? 0) } }
    var unsaturatedFat: Int { meals.reduce(0) { $0 + ($1.unsaturatedFat ?? 0) } }

    var accurateCalories: Int { meals.reduce(0) { $0 + $1.accurateCalories } }
    var accurateProtein: Int { meals.reduce(0) { $0 + $1.accurateProtein } }
    var accurateCarbs: Int { meals.reduce(0) { $0 + $1.accurateCarbs } }
    var accurateFat: Int { meals.reduce(0) { $0 + $1.accurateFat } }

    var vitamins: [String: Int] {
        var totals: [String: Int] = [:]
        for meal in meals {
            for (key, value) in meal.accurateVitamins {
                totals[key, default: 0] += value
            }
        }
        return totals
    }

    var minerals: [String: Int] {
        var totals: [String: Int] = [:]
        for meal in meals {
            for (key, value) in meal.accurateMinerals {
                totals[key, default: 0] += value
            }
        }
        return totals
    }

    var categories: [FoodIcons] {
        Array(Set(meals.flatMap { $0.categories }))
    }

    var imageURL: String? {
        meals.first { !$0.image.isEmpty }?.image
    }

    var imageURLs: [String] {
        meals.compactMap { $0.image.isEmpty ? nil : $0.image }
    }

    var isCombinedMeal: Bool { meals.count > 1 }
    var displayName: String { "Meal \(order)" }

    mutating func combineWith(_ otherPlannedMeal: PlannedMeal) {
        meals.append(contentsOf: otherPlannedMeal.meals)
    }

    func separateIntoIndividualMeals() -> [PlannedMeal] {
        meals.enumerated().map { index, meal in
            PlannedMeal(
                id: generateUniqueID(prefix: "planned_meal"),
                meal: meal,
                order: order + index,
                notes: notes,
                isCompleted: false,
                completedAt: nil
            )
        }
    }

    static func from(meal: Meal, order: Int) -> PlannedMeal {
        PlannedMeal(meal: meal, order: order)
    }

    static func from(meals: [Meal], order: Int) -> PlannedMeal {
        PlannedMeal(meals: meals, order: order)
    }
}

struct MealPlan: Identifiable, Hashable {
    var id: String
    var userId: String
    var planName: String
    var plannedMeals: [PlannedMeal]
    var isActive: Bool
    var challengeId: String?
    var createdAt: Date
    var updatedAt: Date

    var isSharedPlan: Bool { challengeId != nil }

    init(
        id: String = generateUniqueID(prefix: "meal_plan"),
        userId: String,
        planName: String,
        plannedMeals: [PlannedMeal] = [],
        isActive: Bool = true,
        challengeId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.planName = planName
        self.plannedMeals = plannedMeals
        self.isActive = isActive
        self.challengeId = challengeId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(dictionary: [String: Any]) {
        self.id = dictionary["id"] as? String ?? generateUniqueID(prefix: "meal_plan")
        self.userId = dictionary["userId"] as? String ?? ""

        if let planName = dictionary["planName"] as? String {
            self.planName = planName
        } else if let dayOfWeek = dictionary["dayOfWeek"] as? String {
            self.planName = "\(dayOfWeek.capitalized) Plan"
        } else {
            self.planName = "My Plan"
        }

        self.isActive = dictionary["isActive"] as? Bool ?? true
        self.challengeId = dictionary["challengeId"] as? String
        self.createdAt = nutritionDate(from: dictionary["createdAt"])
        self.updatedAt = nutritionDate(from: dictionary["updatedAt"])

        if let plannedMealsData = dictionary["plannedMeals"] as? [[String: Any]] {
            self.plannedMeals = plannedMealsData.map { PlannedMeal(dictionary: $0) }
        } else {
            self.plannedMeals = []
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "userId": userId,
            "planName": planName,
            "plannedMeals": plannedMeals.map { $0.toDictionary() },
            "isActive": isActive,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        if let challengeId { dict["challengeId"] = challengeId }
        return dict
    }

    mutating func shareWithChallenge(_ challengeId: String) {
        self.challengeId = challengeId
        updatedAt = Date()
    }

    mutating func unshareFromChallenge() {
        challengeId = nil
        updatedAt = Date()
    }

    func canEdit(currentUserId: String) -> Bool {
        userId == currentUserId
    }

    func isAccessibleTo(userId: String, userChallengeId: String? = nil) -> Bool {
        if challengeId == nil { return self.userId == userId }
        if let challengeId, let userChallengeId {
            return challengeId == userChallengeId
        }
        return self.userId == userId
    }

    var totalCalories: Int { plannedMeals.reduce(0) { $0 + $1.calories } }
    var totalProtein: Int { plannedMeals.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Int { plannedMeals.reduce(0) { $0 + $1.carbs } }
    var totalFat: Int { plannedMeals.reduce(0) { $0 + $1.fat } }
    var totalSugars: Int { plannedMeals.reduce(0) { $0 + $1.sugars } }
    var totalDietaryFiber: Int { plannedMeals.reduce(0) { $0 + $1.dietaryFiber } }
    var totalSodium: Int { plannedMeals.reduce(0) { $0 + $1.sodium } }
    var totalCholesterol: Int { plannedMeals.reduce(0) { $0 + $1.cholesterol } }
    var totalSaturatedFat: Int { plannedMeals.reduce(0) { $0 + $1.saturatedFat } }
    var totalUnsaturatedFat: Int { plannedMeals.reduce(0) { $0 + $1.unsaturatedFat } }

    var totalVitamins: [String: Int] {
        var totals: [String: Int] = [:]
        for plannedMeal in plannedMeals {
            for (key, value) in plannedMeal.vitamins {
                totals[key, default: 0] += value
            }
        }
        return totals
    }

    var totalMinerals: [String: Int] {
        var totals: [String: Int] = [:]
        for plannedMeal in plannedMeals {
            for (key, value) in plannedMeal.minerals {
                totals[key, default: 0] += value
            }
        }
        return totals
    }

    var completedMeals: [PlannedMeal] { plannedMeals.filter { $0.isCompleted } }
    var pendingMeals: [PlannedMeal] { plannedMeals.filter { !$0.isCompleted } }
    var isCompleteForDay: Bool { !plannedMeals.isEmpty && plannedMeals.allSatisfy { $0.isCompleted } }
    var completionPercentage: Double {
        guard !plannedMeals.isEmpty else { return 0.0 }
        return Double(completedMeals.count) / Double(plannedMeals.count)
    }

    var orderedMeals: [PlannedMeal] {
        plannedMeals.sorted { $0.order < $1.order }
    }

    mutating func addMeal(_ meal: Meal) -> PlannedMeal {
        let nextOrder = (plannedMeals.map(\.order).max() ?? 0) + 1
        let plannedMeal = PlannedMeal.from(meal: meal, order: nextOrder)
        plannedMeals.append(plannedMeal)
        updatedAt = Date()
        return plannedMeal
    }

    mutating func removeMeal(withId mealId: String) {
        guard let index = plannedMeals.firstIndex(where: { $0.id == mealId }) else { return }
        plannedMeals.remove(at: index)
        normalizeOrders()
        updatedAt = Date()
    }

    mutating func reorderMeal(withId mealId: String, to newOrder: Int) {
        guard let index = plannedMeals.firstIndex(where: { $0.id == mealId }) else { return }
        let clampedOrder = max(1, min(newOrder, plannedMeals.count))
        guard index != clampedOrder - 1 else { return }

        let meal = plannedMeals.remove(at: index)
        plannedMeals.insert(meal, at: clampedOrder - 1)
        normalizeOrders()
        updatedAt = Date()
    }

    mutating func updateMeal(_ plannedMeal: PlannedMeal) {
        if let index = plannedMeals.firstIndex(where: { $0.id == plannedMeal.id }) {
            plannedMeals[index] = plannedMeal
        } else {
            plannedMeals.append(plannedMeal)
        }
        normalizeOrders()
        updatedAt = Date()
    }

    mutating func markMealCompleted(withId mealId: String) {
        guard let index = plannedMeals.firstIndex(where: { $0.id == mealId }) else { return }
        plannedMeals[index].isCompleted = true
        plannedMeals[index].completedAt = Date()
        updatedAt = Date()
    }

    private mutating func normalizeOrders() {
        for (index, _) in plannedMeals.enumerated() {
            plannedMeals[index].order = index + 1
        }
    }
}
