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
    // Extended micronutrients — FWP writes these on shared meals, so Macra
    // needs to read and round-trip them or cross-app edits lose data.
    var sugars: Int?
    var sodium: Int?
    var cholesterol: Int?
    var saturatedFat: Int?
    var unsaturatedFat: Int?
    var vitamins: [String: Int]?
    var minerals: [String: Int]?

    init(
        id: String = UUID().uuidString,
        name: String,
        quantity: String,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        fiber: Int? = nil,
        sugarAlcohols: Int? = nil,
        sugars: Int? = nil,
        sodium: Int? = nil,
        cholesterol: Int? = nil,
        saturatedFat: Int? = nil,
        unsaturatedFat: Int? = nil,
        vitamins: [String: Int]? = nil,
        minerals: [String: Int]? = nil
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
        self.sugars = sugars
        self.sodium = sodium
        self.cholesterol = cholesterol
        self.saturatedFat = saturatedFat
        self.unsaturatedFat = unsaturatedFat
        self.vitamins = vitamins
        self.minerals = minerals
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
        self.sugars = dictionary["sugars"] as? Int
        self.sodium = dictionary["sodium"] as? Int
        self.cholesterol = dictionary["cholesterol"] as? Int
        self.saturatedFat = dictionary["saturatedFat"] as? Int
        self.unsaturatedFat = dictionary["unsaturatedFat"] as? Int
        self.vitamins = dictionary["vitamins"] as? [String: Int]
        self.minerals = dictionary["minerals"] as? [String: Int]
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
        if let sugars, sugars > 0 { dict["sugars"] = sugars }
        if let sodium, sodium > 0 { dict["sodium"] = sodium }
        if let cholesterol, cholesterol > 0 { dict["cholesterol"] = cholesterol }
        if let saturatedFat, saturatedFat > 0 { dict["saturatedFat"] = saturatedFat }
        if let unsaturatedFat, unsaturatedFat > 0 { dict["unsaturatedFat"] = unsaturatedFat }
        if let vitamins, !vitamins.isEmpty { dict["vitamins"] = vitamins }
        if let minerals, !minerals.isEmpty { dict["minerals"] = minerals }
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
    // Extended micronutrients — round-tripped from the shared Firestore meals
    // collection so FWP-authored data isn't silently dropped on Macra reads.
    var sugars: Int?
    var sodium: Int?
    var cholesterol: Int?
    var saturatedFat: Int?
    var unsaturatedFat: Int?
    var vitamins: [String: Int]?
    var minerals: [String: Int]?
    var image: String
    var entryMethod: MealEntryMethod
    var servingSize: String?
    var sourceReferences: [MealSourceReference]?
    /// Which app logged this meal: "macra", "fwp", (future: "pulsecheck"). `nil` for legacy
    /// entries written before the tag existed. Preserved on edits — the creator tag is sticky.
    var sourcedFrom: String?
    /// How the photo (if any) was acquired: "camera" = real-time capture; "upload"
    /// = chosen from the photo library. `nil` for non-photo entries (text, voice,
    /// history, label) or legacy rows. Used by future scoring/incentive logic
    /// that rewards real-time captures over uploads.
    var photoCaptureSource: String?
    /// IANA timezone identifier captured at log time (e.g. "America/Los_Angeles").
    /// Anchors the meal to the calendar day the user actually ate it on, regardless
    /// of where the device travels later. `nil` for legacy rows logged before the
    /// field existed — those fall back to the device's current timezone.
    var loggedTimeZoneIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    /// Aggregated count of buddies who liked this meal. Maintained
    /// server-side via `FieldValue.increment` from `MealSocialService`;
    /// readers should treat it as eventually-consistent (the actual likes
    /// subcollection is the source of truth). Defaults to 0 for legacy
    /// meals logged before the social layer existed.
    var likeCount: Int = 0
    /// Aggregated count of buddy comments on this meal. Same maintenance
    /// pattern as `likeCount`.
    var commentCount: Int = 0

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
        sugars: Int? = nil,
        sodium: Int? = nil,
        cholesterol: Int? = nil,
        saturatedFat: Int? = nil,
        unsaturatedFat: Int? = nil,
        vitamins: [String: Int]? = nil,
        minerals: [String: Int]? = nil,
        image: String,
        entryMethod: MealEntryMethod = .unknown,
        servingSize: String? = nil,
        sourceReferences: [MealSourceReference]? = nil,
        sourcedFrom: String? = nil,
        photoCaptureSource: String? = nil,
        loggedTimeZoneIdentifier: String? = nil,
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
        self.sugars = sugars
        self.sodium = sodium
        self.cholesterol = cholesterol
        self.saturatedFat = saturatedFat
        self.unsaturatedFat = unsaturatedFat
        self.vitamins = vitamins
        self.minerals = minerals
        self.image = image
        self.entryMethod = entryMethod
        self.servingSize = servingSize
        self.sourceReferences = sourceReferences
        self.sourcedFrom = sourcedFrom
        self.photoCaptureSource = photoCaptureSource
        self.loggedTimeZoneIdentifier = loggedTimeZoneIdentifier
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
        self.sugars = dictionary["sugars"] as? Int
        self.sodium = dictionary["sodium"] as? Int
        self.cholesterol = dictionary["cholesterol"] as? Int
        self.saturatedFat = dictionary["saturatedFat"] as? Int
        self.unsaturatedFat = dictionary["unsaturatedFat"] as? Int
        self.vitamins = dictionary["vitamins"] as? [String: Int]
        self.minerals = dictionary["minerals"] as? [String: Int]
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
        self.sourcedFrom = dictionary["sourcedFrom"] as? String
        self.photoCaptureSource = dictionary["photoCaptureSource"] as? String
        self.loggedTimeZoneIdentifier = dictionary["loggedTimeZoneIdentifier"] as? String
        // Aggregated social counts. Read defensively — older meal docs
        // pre-date the social subcollections so the field will be absent.
        self.likeCount = dictionary["likeCount"] as? Int ?? 0
        self.commentCount = dictionary["commentCount"] as? Int ?? 0
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
            "updatedAt": updatedAt.timeIntervalSince1970,
            // Default new writes to "macra"; preserve whatever the model already carries for
            // entries originally logged in another Pulse app (FWP, PulseCheck).
            "sourcedFrom": sourcedFrom ?? "macra"
        ]

        if let fiber {
            dict["fiber"] = fiber
        }

        if let sugarAlcohols {
            dict["sugarAlcohols"] = sugarAlcohols
        }

        if let sugars, sugars > 0 {
            dict["sugars"] = sugars
        }

        if let sodium, sodium > 0 {
            dict["sodium"] = sodium
        }

        if let cholesterol, cholesterol > 0 {
            dict["cholesterol"] = cholesterol
        }

        if let saturatedFat, saturatedFat > 0 {
            dict["saturatedFat"] = saturatedFat
        }

        if let unsaturatedFat, unsaturatedFat > 0 {
            dict["unsaturatedFat"] = unsaturatedFat
        }

        if let vitamins, !vitamins.isEmpty {
            dict["vitamins"] = vitamins
        }

        if let minerals, !minerals.isEmpty {
            dict["minerals"] = minerals
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

        if let photoCaptureSource, !photoCaptureSource.isEmpty {
            dict["photoCaptureSource"] = photoCaptureSource
        }

        if let loggedTimeZoneIdentifier, !loggedTimeZoneIdentifier.isEmpty {
            dict["loggedTimeZoneIdentifier"] = loggedTimeZoneIdentifier
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

    /// The timezone the meal was logged in. Falls back to the device's current
    /// timezone for legacy rows that pre-date the field.
    var loggedTimeZone: TimeZone {
        if let identifier = loggedTimeZoneIdentifier, let tz = TimeZone(identifier: identifier) {
            return tz
        }
        return TimeZone.current
    }

    /// `MMddyyyy` day-key for bucketing in the meal's logged timezone — keeps
    /// the meal anchored to the calendar day the user actually ate it on, even
    /// after the device crosses timezones.
    var loggedDayKey: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = loggedTimeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = loggedTimeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMddyyyy"
        return formatter.string(from: createdAt)
    }
}

struct PlannedMeal: Identifiable, Hashable {
    var id: String
    var meals: [Meal]
    var order: Int
    var notes: String?
    var isCompleted: Bool
    var completedAt: Date?
    /// Days this meal applies to. `nil` (or empty after decode) means the
    /// meal applies every day — the default for legacy plans. When a Fri/Sat
    /// substitution or "omit on Sunday" rule is captured, callers populate
    /// the active days here so the plan view can filter by weekday.
    var daysActive: [Weekday]?

    init(
        id: String = MealPlanningIDs.make(prefix: "planned_meal"),
        meals: [Meal],
        order: Int,
        notes: String? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        daysActive: [Weekday]? = nil
    ) {
        self.id = id
        self.meals = meals
        self.order = order
        self.notes = notes
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.daysActive = Self.normalize(daysActive)
    }

    init(
        id: String = MealPlanningIDs.make(prefix: "planned_meal"),
        meal: Meal,
        order: Int,
        notes: String? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        daysActive: [Weekday]? = nil
    ) {
        self.init(id: id, meals: [meal], order: order, notes: notes, isCompleted: isCompleted, completedAt: completedAt, daysActive: daysActive)
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

        if let rawDays = dictionary["daysActive"] as? [String] {
            self.daysActive = Self.normalize(rawDays.compactMap(Weekday.from))
        } else {
            self.daysActive = nil
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

        if let daysActive, !daysActive.isEmpty {
            dict["daysActive"] = daysActive.map(\.firestoreValue)
        }

        return dict
    }

    /// `nil` and "all 7 days" both mean "applies every day" — collapse to
    /// `nil` so dictionary round-trips and equality checks stay consistent.
    private static func normalize(_ days: [Weekday]?) -> [Weekday]? {
        guard let days, !days.isEmpty else { return nil }
        let unique = Array(NSOrderedSet(array: days)) as? [Weekday] ?? days
        if Set(unique) == Set(Weekday.allCases) { return nil }
        return unique
    }

    /// True when this meal applies on the given weekday (or has no
    /// restriction set, in which case it applies every day).
    func appliesOn(_ day: Weekday) -> Bool {
        guard let daysActive, !daysActive.isEmpty else { return true }
        return daysActive.contains(day)
    }

    /// True when the meal has a non-default day scope. UI uses this to
    /// surface a "Fri/Sat only" badge.
    var hasDayScope: Bool {
        guard let daysActive else { return false }
        return !daysActive.isEmpty
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
                completedAt: nil,
                daysActive: daysActive
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

    /// Meals scheduled for `day`, sorted by `order`. Meals with no `daysActive`
    /// restriction apply every day, matching legacy single-day plan behavior.
    func orderedMeals(for day: Weekday) -> [PlannedMeal] {
        plannedMeals
            .filter { $0.appliesOn(day) }
            .sorted { $0.order < $1.order }
    }

    func totalCalories(for day: Weekday) -> Int { orderedMeals(for: day).reduce(0) { $0 + $1.calories } }
    func totalProtein(for day: Weekday) -> Int { orderedMeals(for: day).reduce(0) { $0 + $1.protein } }
    func totalCarbs(for day: Weekday) -> Int { orderedMeals(for: day).reduce(0) { $0 + $1.carbs } }
    func totalFat(for day: Weekday) -> Int { orderedMeals(for: day).reduce(0) { $0 + $1.fat } }

    /// True when at least one planned meal carries a non-default `daysActive`,
    /// signaling that the plan varies by day. Used to decide whether to
    /// render the day-toggle pill row in the plan detail view.
    var hasDayVariants: Bool {
        plannedMeals.contains(where: \.hasDayScope)
    }

    /// Distinct weekdays referenced by any meal's `daysActive`. Empty if the
    /// plan has no day-scoped meals.
    var scopedDays: [Weekday] {
        let collected = plannedMeals.flatMap { $0.daysActive ?? [] }
        let unique = Array(NSOrderedSet(array: collected)) as? [Weekday] ?? []
        return Weekday.displayOrder.filter { unique.contains($0) }
    }

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

/// Day-of-week tag used to scope `PlannedMeal.daysActive` and to derive
/// the active day for plan rendering. Raw values match the Firestore strings
/// used by `MacroRecommendation.dayOfWeek` and Nora's `scopedMacros[].days`,
/// so the same string round-trips end-to-end without translation.
enum Weekday: String, CaseIterable, Identifiable, Hashable {
    case mon, tue, wed, thu, fri, sat, sun

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        case .sun: return "Sun"
        }
    }

    var firestoreValue: String { rawValue }

    /// Parses both short ("fri") and long ("friday") forms; whitespace and
    /// case are normalized. Returns nil for anything else.
    static func from(_ raw: String?) -> Weekday? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = Weekday(rawValue: normalized) { return direct }
        return longFormMap[normalized]
    }

    private static let longFormMap: [String: Weekday] = [
        "monday": .mon,
        "tuesday": .tue,
        "tues": .tue,
        "wednesday": .wed,
        "thursday": .thu,
        "thur": .thu,
        "thurs": .thu,
        "friday": .fri,
        "saturday": .sat,
        "sunday": .sun
    ]

    static func from(date: Date, calendar: Calendar = .current) -> Weekday {
        // Calendar.component(.weekday, ...) returns 1=Sun … 7=Sat.
        switch calendar.component(.weekday, from: date) {
        case 1: return .sun
        case 2: return .mon
        case 3: return .tue
        case 4: return .wed
        case 5: return .thu
        case 6: return .fri
        case 7: return .sat
        default: return .mon
        }
    }

    /// Conventional Mon–Sun ordering used by the day-toggle pill row.
    static let displayOrder: [Weekday] = [.mon, .tue, .wed, .thu, .fri, .sat, .sun]
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
