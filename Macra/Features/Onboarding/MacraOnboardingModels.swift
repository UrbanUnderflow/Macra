import Foundation

enum BiologicalSex: String, CaseIterable, Identifiable, Hashable {
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }
}

enum ActivityLevel: String, CaseIterable, Identifiable, Hashable {
    case sedentary
    case light
    case moderate
    case veryActive
    case athlete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light: return "Lightly active"
        case .moderate: return "Moderately active"
        case .veryActive: return "Very active"
        case .athlete: return "Athlete"
        }
    }

    var subtitle: String {
        switch self {
        case .sedentary: return "Desk job, little exercise"
        case .light: return "Light exercise 1–3 days/week"
        case .moderate: return "Moderate exercise 3–5 days/week"
        case .veryActive: return "Hard exercise 6–7 days/week"
        case .athlete: return "Twice-a-day training"
        }
    }

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .veryActive: return 1.725
        case .athlete: return 1.9
        }
    }
}

enum MacraGoalDirection: String, Hashable {
    case lose
    case maintain
    case gain
}

enum GoalPace: String, CaseIterable, Identifiable, Hashable {
    case gradual
    case moderate
    case aggressive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gradual: return "Gradual"
        case .moderate: return "Balanced"
        case .aggressive: return "Aggressive"
        }
    }

    var subtitle: String {
        switch self {
        case .gradual: return "~0.4% bodyweight/week. Easiest to sustain."
        case .moderate: return "~0.6% bodyweight/week. Steady and proven."
        case .aggressive: return "~0.9% bodyweight/week. Fastest results."
        }
    }

    var weeklyBodyweightPct: Double {
        switch self {
        case .gradual: return 0.004
        case .moderate: return 0.006
        case .aggressive: return 0.009
        }
    }
}

enum DietaryPreference: String, CaseIterable, Identifiable, Hashable {
    case none
    case vegetarian
    case vegan
    case pescatarian
    case noRedMeat
    case noPork
    case keto
    case paleo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No restrictions"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .pescatarian: return "Pescatarian"
        case .noRedMeat: return "No red meat"
        case .noPork: return "No pork"
        case .keto: return "Keto / low-carb"
        case .paleo: return "Paleo"
        }
    }
}

enum BiggestStruggle: String, CaseIterable, Identifiable, Hashable {
    case consistency
    case cravings
    case portions
    case planning
    case knowledge
    case motivation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .consistency: return "Staying consistent"
        case .cravings: return "Resisting cravings"
        case .portions: return "Knowing portion sizes"
        case .planning: return "Planning meals ahead"
        case .knowledge: return "Knowing what to eat"
        case .motivation: return "Staying motivated"
        }
    }

    var subtitle: String {
        switch self {
        case .consistency: return "I start strong but fall off."
        case .cravings: return "Late-night snacks ruin my day."
        case .portions: return "I have no idea how much I should eat."
        case .planning: return "I wing it and end up ordering takeout."
        case .knowledge: return "There's too much conflicting advice."
        case .motivation: return "I lose steam after a few weeks."
        }
    }
}

struct MacraOnboardingAnswers {
    var sex: BiologicalSex?
    var birthdate: Date?
    var heightCm: Double?
    var currentWeightKg: Double?
    var goalWeightKg: Double?
    var pace: GoalPace?
    var activityLevel: ActivityLevel?
    var dietaryPreference: DietaryPreference?
    var biggestStruggle: BiggestStruggle?

    var goalDirection: MacraGoalDirection? {
        guard let current = currentWeightKg, let target = goalWeightKg else { return nil }
        let delta = target - current
        if abs(delta) < 1 { return .maintain }
        return delta < 0 ? .lose : .gain
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let sex = sex { dict["sex"] = sex.rawValue }
        if let birthdate = birthdate { dict["birthdate"] = birthdate.timeIntervalSince1970 }
        if let heightCm = heightCm { dict["heightCm"] = heightCm }
        if let currentWeightKg = currentWeightKg { dict["currentWeightKg"] = currentWeightKg }
        if let goalWeightKg = goalWeightKg { dict["goalWeightKg"] = goalWeightKg }
        if let pace = pace { dict["pace"] = pace.rawValue }
        if let activityLevel = activityLevel { dict["activityLevel"] = activityLevel.rawValue }
        if let dietaryPreference = dietaryPreference { dict["dietaryPreference"] = dietaryPreference.rawValue }
        if let biggestStruggle = biggestStruggle { dict["biggestStruggle"] = biggestStruggle.rawValue }
        if let goalDirection = goalDirection { dict["goalDirection"] = goalDirection.rawValue }
        dict["updatedAt"] = Date().timeIntervalSince1970
        return dict
    }
}

struct MacraOnboardingPrediction {
    let targetWeightKg: Double
    let estimatedGoalDate: Date
    let dailyCalorieTarget: Int
    let weeklyWeightChangeKg: Double
    let tdee: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int

    static func compute(from answers: MacraOnboardingAnswers) -> MacraOnboardingPrediction? {
        guard let sex = answers.sex,
              let birthdate = answers.birthdate,
              let heightCm = answers.heightCm,
              let currentWeightKg = answers.currentWeightKg,
              let goalWeightKg = answers.goalWeightKg,
              let activityLevel = answers.activityLevel else { return nil }

        let age = Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 30

        let base = (10 * currentWeightKg) + (6.25 * heightCm) - (5 * Double(age))
        let bmr = sex == .male ? base + 5 : base - 161
        let tdee = bmr * activityLevel.multiplier

        let delta = goalWeightKg - currentWeightKg
        let direction: MacraGoalDirection = abs(delta) < 1 ? .maintain : (delta < 0 ? .lose : .gain)

        let dailyTarget: Int
        let goalDate: Date
        let weeklyChange: Double

        if direction == .maintain {
            dailyTarget = Int(tdee.rounded())
            goalDate = Date()
            weeklyChange = 0
        } else {
            let isLoss = direction == .lose
            let paceFraction = answers.pace?.weeklyBodyweightPct ?? 0.006
            let weeklyKg = max(0.25, currentWeightKg * paceFraction)
            weeklyChange = isLoss ? -weeklyKg : weeklyKg
            let deficitPerDay = (weeklyKg * 7700) / 7 * (isLoss ? -1 : 1)
            dailyTarget = Int((tdee + deficitPerDay).rounded())

            let weeksToGoal = abs(delta) / weeklyKg
            let daysToGoal = Int((weeksToGoal * 7).rounded())
            goalDate = Calendar.current.date(byAdding: .day, value: daysToGoal, to: Date()) ?? Date()
        }

        let (protein, carbs, fat) = macroSplit(
            calories: dailyTarget,
            bodyWeightKg: currentWeightKg,
            direction: direction
        )

        return MacraOnboardingPrediction(
            targetWeightKg: goalWeightKg,
            estimatedGoalDate: goalDate,
            dailyCalorieTarget: dailyTarget,
            weeklyWeightChangeKg: weeklyChange,
            tdee: Int(tdee.rounded()),
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat
        )
    }

    private static func macroSplit(
        calories: Int,
        bodyWeightKg: Double,
        direction: MacraGoalDirection
    ) -> (protein: Int, carbs: Int, fat: Int) {
        let bodyWeightLbs = bodyWeightKg * 2.20462
        let proteinPerLb: Double
        switch direction {
        case .lose: proteinPerLb = 1.0
        case .maintain: proteinPerLb = 0.8
        case .gain: proteinPerLb = 0.9
        }
        let proteinGrams = Int((bodyWeightLbs * proteinPerLb).rounded())

        let fatCalories = Double(calories) * 0.28
        let fatGrams = Int((fatCalories / 9.0).rounded())

        let proteinCalories = Double(proteinGrams) * 4.0
        let carbsCalories = max(0, Double(calories) - proteinCalories - fatCalories)
        let carbsGrams = Int((carbsCalories / 4.0).rounded())

        return (proteinGrams, carbsGrams, fatGrams)
    }

    func toMacroRecommendation(userId: String) -> MacroRecommendation {
        MacroRecommendation(
            userId: userId,
            calories: dailyCalorieTarget,
            protein: proteinGrams,
            carbs: carbsGrams,
            fat: fatGrams
        )
    }
}

struct MacraSuggestedMealItem: Codable, Hashable, Identifiable {
    var name: String
    var quantity: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    var id: String { "\(name)-\(quantity)" }
}

struct MacraSuggestedMeal: Codable, Hashable, Identifiable {
    var title: String
    var items: [MacraSuggestedMealItem]

    var id: String { title }

    var totalCalories: Int { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Int { items.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Int { items.reduce(0) { $0 + $1.carbs } }
    var totalFat: Int { items.reduce(0) { $0 + $1.fat } }
}

struct MacraSuggestedMealPlan: Codable, Hashable {
    var meals: [MacraSuggestedMeal]
    var notes: String?
}
