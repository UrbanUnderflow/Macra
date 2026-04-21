import Foundation

enum MealPlanningIDs {
    static func make(prefix: String? = nil) -> String {
        let prefixPart = prefix.map { "\($0)-" } ?? ""
        return "\(prefixPart)\(UUID().uuidString)-\(Int(Date().timeIntervalSince1970))"
    }
}

enum MealPlanningDates {
    static let datePrefixFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "MMddyyyy"
        return formatter
    }()

    static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let longDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

enum MealCategory: String, CaseIterable, Identifiable, Hashable {
    case grains
    case fruits
    case vegetables
    case dairy
    case meat
    case fishAndSeafood
    case eggs
    case nutsSeedAndLegumes
    case fatsAndOils
    case sweetsAndDesserts
    case snacks
    case water
    case juices
    case softDrinks
    case alcoholicDrinks
    case coffeeAndTea
    case fastFood
    case condimentsAndSauces
    case soupsAndBroths
    case processedAndPrepackagedFoods
    case ethnicOrRegionalCuisines
    case breakfastFoods
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fishAndSeafood: return "Fish & Seafood"
        case .nutsSeedAndLegumes: return "Nuts, Seeds & Legumes"
        case .fatsAndOils: return "Fats & Oils"
        case .sweetsAndDesserts: return "Sweets & Desserts"
        case .softDrinks: return "Soft Drinks"
        case .alcoholicDrinks: return "Alcoholic Drinks"
        case .coffeeAndTea: return "Coffee & Tea"
        case .fastFood: return "Fast Food"
        case .condimentsAndSauces: return "Condiments & Sauces"
        case .soupsAndBroths: return "Soups & Broths"
        case .processedAndPrepackagedFoods: return "Packaged Foods"
        case .ethnicOrRegionalCuisines: return "Regional Cuisine"
        case .breakfastFoods: return "Breakfast"
        case .unknown: return "Unknown"
        default:
            return rawValue.capitalized
        }
    }
}

enum MealEntryMethod: String, CaseIterable, Identifiable, Hashable {
    case photo
    case text
    case voice
    case unknown

    var id: String { rawValue }
}

struct MealSourceReference: Hashable {
    var title: String
    var url: String
    var domain: String?

    init(title: String, url: String, domain: String? = nil) {
        self.title = title
        self.url = url
        self.domain = domain
    }

    init?(dictionary: [String: Any]) {
        guard let title = dictionary["title"] as? String,
              let url = dictionary["url"] as? String,
              !title.isEmpty,
              !url.isEmpty else {
            return nil
        }

        self.title = title
        self.url = url
        self.domain = dictionary["domain"] as? String
    }

    func toDictionary() -> [String: Any] {
        [
            "title": title,
            "url": url,
            "domain": domain ?? ""
        ]
    }
}

struct MealIngredientDetail: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var quantity: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var fiber: Int?
    var sugarAlcohols: Int?

    init(
        id: String = UUID().uuidString,
        name: String,
        quantity: String,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        fiber: Int? = nil,
        sugarAlcohols: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugarAlcohols = sugarAlcohols
    }

    init?(dictionary: [String: Any]) {
        guard let name = dictionary["name"] as? String, !name.isEmpty else { return nil }
        self.id = dictionary["id"] as? String ?? UUID().uuidString
        self.name = name
        self.quantity = dictionary["quantity"] as? String ?? ""
        self.calories = dictionary["calories"] as? Int ?? 0
        self.protein = dictionary["protein"] as? Int ?? 0
        self.carbs = dictionary["carbs"] as? Int ?? 0
        self.fat = dictionary["fat"] as? Int ?? 0
        self.fiber = dictionary["fiber"] as? Int
        self.sugarAlcohols = dictionary["sugarAlcohols"] as? Int
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "quantity": quantity,
            "calories": calories,
            "protein": protein,
            "carbs": carbs,
            "fat": fat
        ]
        if let fiber { dict["fiber"] = fiber }
        if let sugarAlcohols { dict["sugarAlcohols"] = sugarAlcohols }
        return dict
    }

    var netCarbs: Int {
        max(0, carbs - (fiber ?? 0) - (sugarAlcohols ?? 0))
    }

    var hasNetCarbAdjustment: Bool {
        (fiber ?? 0) > 0 || (sugarAlcohols ?? 0) > 0
    }
}

struct Meal: Identifiable, Hashable {
    var id: String
    var name: String
    var categories: [MealCategory]
    var ingredients: [String]
    var detailedIngredients: [MealIngredientDetail]?
    var caption: String
    var calories: Int
    var protein: Int
    var fat: Int
    var carbs: Int
    var fiber: Int?
    var sugarAlcohols: Int?
    var image: String
    var entryMethod: MealEntryMethod
    var servingSize: String?
    var sourceReferences: [MealSourceReference]?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = MealPlanningIDs.make(prefix: "meal"),
        name: String,
        categories: [MealCategory] = [.unknown],
        ingredients: [String] = [],
        detailedIngredients: [MealIngredientDetail]? = nil,
        caption: String,
        calories: Int,
        protein: Int,
        fat: Int,
        carbs: Int,
        fiber: Int? = nil,
        sugarAlcohols: Int? = nil,
        image: String,
        entryMethod: MealEntryMethod = .unknown,
        servingSize: String? = nil,
        sourceReferences: [MealSourceReference]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categories = categories
        self.ingredients = ingredients
        self.detailedIngredients = detailedIngredients
        self.caption = caption
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.fiber = fiber
        self.sugarAlcohols = sugarAlcohols
        self.image = image
        self.entryMethod = entryMethod
        self.servingSize = servingSize
        self.sourceReferences = sourceReferences
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(id: String, dictionary: [String: Any]) {
        self.id = id
        self.name = dictionary["name"] as? String ?? ""
        self.categories = (dictionary["categories"] as? [String] ?? []).compactMap { MealCategory(rawValue: $0) }
        self.ingredients = dictionary["ingredients"] as? [String] ?? []
        if let detailed = dictionary["detailedIngredients"] as? [[String: Any]] {
            self.detailedIngredients = detailed.compactMap { MealIngredientDetail(dictionary: $0) }
        } else {
            self.detailedIngredients = nil
        }
        self.caption = dictionary["caption"] as? String ?? ""
        self.calories = dictionary["calories"] as? Int ?? 0
        self.protein = dictionary["protein"] as? Int ?? 0
        self.fat = dictionary["fat"] as? Int ?? 0
        self.carbs = dictionary["carbs"] as? Int ?? 0
        self.fiber = dictionary["fiber"] as? Int
        self.sugarAlcohols = dictionary["sugarAlcohols"] as? Int
        self.image = dictionary["image"] as? String ?? ""
        self.entryMethod = MealEntryMethod(rawValue: dictionary["entryMethod"] as? String ?? "") ?? .unknown
        self.servingSize = dictionary["servingSize"] as? String
        self.createdAt = Date(timeIntervalSince1970: dictionary["createdAt"] as? Double ?? 0)
        self.updatedAt = Date(timeIntervalSince1970: dictionary["updatedAt"] as? Double ?? 0)

        if let references = dictionary["sourceReferences"] as? [[String: Any]] {
            self.sourceReferences = references.compactMap { MealSourceReference(dictionary: $0) }
        } else {
            self.sourceReferences = nil
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "categories": categories.map { $0.rawValue },
            "ingredients": ingredients,
            "caption": caption,
            "calories": calories,
            "protein": protein,
            "fat": fat,
            "carbs": carbs,
            "image": image,
            "entryMethod": entryMethod.rawValue,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]

        if let fiber {
            dict["fiber"] = fiber
        }

        if let sugarAlcohols {
            dict["sugarAlcohols"] = sugarAlcohols
        }

        if let detailedIngredients, !detailedIngredients.isEmpty {
            dict["detailedIngredients"] = detailedIngredients.map { $0.toDictionary() }
        }

        if let servingSize {
            dict["servingSize"] = servingSize
        }

        if let sourceReferences, !sourceReferences.isEmpty {
            dict["sourceReferences"] = sourceReferences.map { $0.toDictionary() }
        }

        return dict
    }

    var hasDetailedIngredients: Bool {
        !(detailedIngredients?.isEmpty ?? true)
    }

    var primaryCategory: MealCategory {
        categories.first ?? .unknown
    }

    var macroLine: String {
        "\(calories) cal · \(protein)g P · \(carbs)g C · \(fat)g F"
    }

    var isImageEmpty: Bool {
        image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Legacy-parity net carb calc ported from Quicklifts: total carbs minus
    /// fiber and sugar alcohols, floored at zero. Sugar alcohols (erythritol,
    /// xylitol, allulose, monk fruit blends like Lakanto) don't raise blood
    /// glucose meaningfully, so a Lakanto brownie with 27g carbs reports ~0
    /// net carbs once those sugar alcohols are populated.
    var netCarbs: Int {
        max(0, carbs - (fiber ?? 0) - (sugarAlcohols ?? 0))
    }

    var hasNetCarbAdjustment: Bool {
        (fiber ?? 0) > 0 || (sugarAlcohols ?? 0) > 0
    }
}

struct PlannedMeal: Identifiable, Hashable {
    var id: String
    var meals: [Meal]
    var order: Int
    var notes: String?
    var isCompleted: Bool
    var completedAt: Date?

    init(
        id: String = MealPlanningIDs.make(prefix: "planned_meal"),
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
        id: String = MealPlanningIDs.make(prefix: "planned_meal"),
        meal: Meal,
        order: Int,
        notes: String? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil
    ) {
        self.init(id: id, meals: [meal], order: order, notes: notes, isCompleted: isCompleted, completedAt: completedAt)
    }

    init(dictionary: [String: Any]) {
        self.id = dictionary["id"] as? String ?? MealPlanningIDs.make(prefix: "planned_meal")
        self.order = dictionary["order"] as? Int ?? 1
        self.notes = dictionary["notes"] as? String
        self.isCompleted = dictionary["isCompleted"] as? Bool ?? false
        if let completedAt = dictionary["completedAt"] as? Double {
            self.completedAt = Date(timeIntervalSince1970: completedAt)
        } else {
            self.completedAt = nil
        }

        if let mealsData = dictionary["meals"] as? [[String: Any]] {
            self.meals = mealsData.map { mealData in
                let mealID = mealData["id"] as? String ?? MealPlanningIDs.make(prefix: "meal")
                return Meal(id: mealID, dictionary: mealData)
            }
        } else if let mealData = dictionary["meal"] as? [String: Any] {
            let mealID = mealData["id"] as? String ?? MealPlanningIDs.make(prefix: "meal")
            self.meals = [Meal(id: mealID, dictionary: mealData)]
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

        if let notes {
            dict["notes"] = notes
        }

        if let completedAt {
            dict["completedAt"] = completedAt.timeIntervalSince1970
        }

        return dict
    }

    var name: String {
        guard !meals.isEmpty else { return "Planned Meal" }
        if meals.count == 1 {
            return meals[0].name
        }
        return meals.map(\.name).joined(separator: " + ")
    }

    var calories: Int { meals.reduce(0) { $0 + $1.calories } }
    var protein: Int { meals.reduce(0) { $0 + $1.protein } }
    var carbs: Int { meals.reduce(0) { $0 + $1.carbs } }
    var fat: Int { meals.reduce(0) { $0 + $1.fat } }

    var imageURL: String? {
        meals.first(where: { !$0.image.isEmpty })?.image
    }

    var categories: [MealCategory] {
        Array(Set(meals.flatMap { $0.categories }))
    }

    var isCombinedMeal: Bool {
        meals.count > 1
    }

    var displayName: String {
        "Meal \(order)"
    }

    mutating func combine(with other: PlannedMeal) {
        meals.append(contentsOf: other.meals)
    }

    func separateIntoIndividualMeals(startingOrder: Int? = nil) -> [PlannedMeal] {
        let baseOrder = startingOrder ?? order
        return meals.enumerated().map { index, meal in
            PlannedMeal(
                meal: meal,
                order: baseOrder + index,
                notes: notes,
                isCompleted: false,
                completedAt: nil
            )
        }
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

    init(
        id: String = MealPlanningIDs.make(prefix: "meal_plan"),
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
        self.id = dictionary["id"] as? String ?? MealPlanningIDs.make(prefix: "meal_plan")
        self.userId = dictionary["userId"] as? String ?? ""
        if let planName = dictionary["planName"] as? String {
            self.planName = planName
        } else if let dayOfWeek = dictionary["dayOfWeek"] as? String {
            self.planName = "\(dayOfWeek.capitalized) Plan"
        } else {
            self.planName = "My Meal Plan"
        }

        self.plannedMeals = (dictionary["plannedMeals"] as? [[String: Any]] ?? []).map { PlannedMeal(dictionary: $0) }
        self.isActive = dictionary["isActive"] as? Bool ?? true
        self.challengeId = dictionary["challengeId"] as? String
        self.createdAt = Date(timeIntervalSince1970: dictionary["createdAt"] as? Double ?? 0)
        self.updatedAt = Date(timeIntervalSince1970: dictionary["updatedAt"] as? Double ?? 0)
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

        if let challengeId {
            dict["challengeId"] = challengeId
        }

        return dict
    }

    var orderedMeals: [PlannedMeal] {
        plannedMeals.sorted { $0.order < $1.order }
    }

    var completedMeals: [PlannedMeal] {
        plannedMeals.filter(\.isCompleted)
    }

    var pendingMeals: [PlannedMeal] {
        plannedMeals.filter { !$0.isCompleted }
    }

    var completionPercentage: Double {
        guard !plannedMeals.isEmpty else { return 0 }
        return Double(completedMeals.count) / Double(plannedMeals.count)
    }

    var totalCalories: Int { plannedMeals.reduce(0) { $0 + $1.calories } }
    var totalProtein: Int { plannedMeals.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Int { plannedMeals.reduce(0) { $0 + $1.carbs } }
    var totalFat: Int { plannedMeals.reduce(0) { $0 + $1.fat } }

    mutating func addMeal(_ meal: Meal) -> PlannedMeal {
        let nextOrder = (plannedMeals.map(\.order).max() ?? 0) + 1
        let plannedMeal = PlannedMeal(meal: meal, order: nextOrder)
        plannedMeals.append(plannedMeal)
        updatedAt = Date()
        return plannedMeal
    }

    mutating func addMeals(_ meals: [Meal]) -> [PlannedMeal] {
        var added: [PlannedMeal] = []
        for meal in meals {
            added.append(addMeal(meal))
        }
        updatedAt = Date()
        return added
    }

    mutating func removeMeal(withId mealId: String) {
        guard let index = plannedMeals.firstIndex(where: { $0.id == mealId }) else { return }
        let removedOrder = plannedMeals[index].order
        plannedMeals.remove(at: index)
        for index in plannedMeals.indices where plannedMeals[index].order > removedOrder {
            plannedMeals[index].order -= 1
        }
        updatedAt = Date()
    }

    mutating func reorderMeal(withId mealId: String, to newOrder: Int) {
        guard let mealIndex = plannedMeals.firstIndex(where: { $0.id == mealId }) else { return }
        guard newOrder >= 1, newOrder <= plannedMeals.count else { return }

        let oldOrder = plannedMeals[mealIndex].order
        guard oldOrder != newOrder else { return }

        if oldOrder < newOrder {
            for index in plannedMeals.indices where plannedMeals[index].order > oldOrder && plannedMeals[index].order <= newOrder {
                plannedMeals[index].order -= 1
            }
        } else {
            for index in plannedMeals.indices where plannedMeals[index].order >= newOrder && plannedMeals[index].order < oldOrder {
                plannedMeals[index].order += 1
            }
        }

        plannedMeals[mealIndex].order = newOrder
        updatedAt = Date()
    }

    mutating func updateMeal(_ plannedMeal: PlannedMeal) {
        if let index = plannedMeals.firstIndex(where: { $0.id == plannedMeal.id }) {
            plannedMeals[index] = plannedMeal
        } else {
            plannedMeals.append(plannedMeal)
        }
        validateAndFixOrdering()
        updatedAt = Date()
    }

    mutating func markMealCompleted(withId mealId: String, completedAt: Date = Date()) {
        guard let index = plannedMeals.firstIndex(where: { $0.id == mealId }) else { return }
        plannedMeals[index].isCompleted = true
        plannedMeals[index].completedAt = completedAt
        updatedAt = Date()
    }

    mutating func markMealIncomplete(withId mealId: String) {
        guard let index = plannedMeals.firstIndex(where: { $0.id == mealId }) else { return }
        plannedMeals[index].isCompleted = false
        plannedMeals[index].completedAt = nil
        updatedAt = Date()
    }

    mutating func combineMeal(withId mealId: String, into targetMealId: String) {
        guard let sourceIndex = plannedMeals.firstIndex(where: { $0.id == mealId }),
              let targetIndex = plannedMeals.firstIndex(where: { $0.id == targetMealId }),
              sourceIndex != targetIndex else {
            return
        }

        let sourceMeal = plannedMeals[sourceIndex]
        plannedMeals[targetIndex].combine(with: sourceMeal)
        plannedMeals[targetIndex].order = min(plannedMeals[targetIndex].order, sourceMeal.order)
        plannedMeals.remove(at: sourceIndex)
        validateAndFixOrdering()
        updatedAt = Date()
    }

    mutating func separateMeal(withId mealId: String) {
        guard let index = plannedMeals.firstIndex(where: { $0.id == mealId }) else { return }
        let meal = plannedMeals[index]
        guard meal.isCombinedMeal else { return }

        let replacements = meal.separateIntoIndividualMeals(startingOrder: meal.order)
        plannedMeals.remove(at: index)
        plannedMeals.insert(contentsOf: replacements, at: index)
        validateAndFixOrdering()
        updatedAt = Date()
    }

    mutating func validateAndFixOrdering() {
        for (index, meal) in plannedMeals.sorted(by: { $0.order < $1.order }).enumerated() {
            if let existingIndex = plannedMeals.firstIndex(where: { $0.id == meal.id }) {
                plannedMeals[existingIndex].order = index + 1
            }
        }
    }
}

struct MacroRecommendation: Identifiable, Hashable {
    var id: String
    var userId: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var dayOfWeek: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = MealPlanningIDs.make(prefix: "macro"),
        userId: String,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        dayOfWeek: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.dayOfWeek = dayOfWeek
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(dictionary: [String: Any]) {
        self.id = dictionary["id"] as? String ?? MealPlanningIDs.make(prefix: "macro")
        self.userId = dictionary["userId"] as? String ?? ""
        self.calories = dictionary["calories"] as? Int ?? 0
        self.protein = dictionary["protein"] as? Int ?? 0
        self.carbs = dictionary["carbs"] as? Int ?? 0
        self.fat = dictionary["fat"] as? Int ?? 0
        self.dayOfWeek = dictionary["dayOfWeek"] as? String
        self.createdAt = Date(timeIntervalSince1970: dictionary["createdAt"] as? Double ?? 0)
        self.updatedAt = Date(timeIntervalSince1970: dictionary["updatedAt"] as? Double ?? 0)
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "userId": userId,
            "calories": calories,
            "protein": protein,
            "carbs": carbs,
            "fat": fat,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]

        if let dayOfWeek {
            dict["dayOfWeek"] = dayOfWeek
        }

        return dict
    }
}

enum MacroTargetGoal: String, CaseIterable, Identifiable {
    case lose = "Lose Fat"
    case maintain = "Maintain"
    case gain = "Gain Muscle"

    var id: String { rawValue }
}

enum MacroActivityLevel: String, CaseIterable, Identifiable {
    case light = "Light"
    case moderate = "Moderate"
    case active = "Active"
    case veryActive = "Very Active"

    var id: String { rawValue }
}

enum MacroTargetScope: String, CaseIterable, Identifiable {
    case global = "Global"
    case monday = "Mon"
    case tuesday = "Tue"
    case wednesday = "Wed"
    case thursday = "Thu"
    case friday = "Fri"
    case saturday = "Sat"
    case sunday = "Sun"

    var id: String { rawValue }

    var firestoreValue: String? {
        switch self {
        case .global: return nil
        case .monday: return "mon"
        case .tuesday: return "tue"
        case .wednesday: return "wed"
        case .thursday: return "thu"
        case .friday: return "fri"
        case .saturday: return "sat"
        case .sunday: return "sun"
        }
    }

    var dayLabel: String {
        switch self {
        case .global: return "All days"
        default: return rawValue
        }
    }
}

enum MealPlanningSampleData {
    static let breakfast = Meal(
        name: "Greek Yogurt Bowl",
        categories: [.dairy, .fruits, .breakfastFoods],
        ingredients: ["Greek yogurt", "berries", "granola"],
        caption: "High protein breakfast bowl",
        calories: 420,
        protein: 32,
        fat: 12,
        carbs: 38,
        image: "",
        entryMethod: .text
    )

    static let lunch = Meal(
        name: "Chicken Rice Bowl",
        categories: [.meat, .grains, .vegetables],
        ingredients: ["Chicken breast", "rice", "broccoli"],
        caption: "Balanced lunch bowl",
        calories: 610,
        protein: 47,
        fat: 18,
        carbs: 59,
        image: "",
        entryMethod: .photo
    )

    static let dinner = Meal(
        name: "Salmon Plate",
        categories: [.fishAndSeafood, .vegetables],
        ingredients: ["Salmon", "sweet potato", "asparagus"],
        caption: "Simple dinner with omega-3s",
        calories: 540,
        protein: 38,
        fat: 24,
        carbs: 39,
        image: "",
        entryMethod: .voice
    )

    static let samplePlan: MealPlan = {
        let plan = MealPlan(
            userId: "preview-user",
            planName: "High Protein Day",
            plannedMeals: [
                PlannedMeal(meal: breakfast, order: 1),
                PlannedMeal(meal: lunch, order: 2),
                PlannedMeal(meal: dinner, order: 3)
            ]
        )
        return plan
    }()
}
