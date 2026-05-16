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
        case .athlete: return "I play a sport regularly"
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

    var coachingFocusTitle: String {
        switch self {
        case .consistency: return "Built for consistency"
        case .cravings: return "Built around cravings"
        case .portions: return "Built for portion clarity"
        case .planning: return "Built for meal planning"
        case .knowledge: return "Built to cut through noise"
        case .motivation: return "Built to keep momentum"
        }
    }

    var coachingFocusBody: String {
        switch self {
        case .consistency:
            return "I keep your target visible and turn logging into a quick daily check-in."
        case .cravings:
            return "I watch protein, timing, and open calories so one snack does not quietly wreck the day."
        case .portions:
            return "Meal scans and labels turn guesses into calories and macros you can actually adjust."
        case .planning:
            return "I start with simple meals that fit your numbers. The more you log, the more I learn what you like, what you skip, and how to make the plan feel like yours."
        case .knowledge:
            return "I explain what matters for your body and filter out generic nutrition noise."
        case .motivation:
            return "I give you a next move each day instead of leaving you with a blank tracker."
        }
    }

    var paywallProofLine: String {
        switch self {
        case .consistency: return "Daily targets, reminders, and Nora check-ins keep the plan from fading out."
        case .cravings: return "Your plan keeps room for real life while protecting your calorie target."
        case .portions: return "Photo logging and label scanning make food math visible before it turns into guesswork."
        case .planning: return "Meal planning stays connected to your live macros, not a static PDF."
        case .knowledge: return "Ask Nora what to change and get answers grounded in your own logs."
        case .motivation: return "Macra keeps the next useful action close, from meal scans to daily coaching."
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
    var sport: String?
    var sportName: String?
    var sportPosition: String?
    var dietaryPreference: DietaryPreference?
    var biggestStruggle: BiggestStruggle?
    var notificationPreferences: MacraNotificationPreferences = .default

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
        if let sport = sport { dict["sport"] = sport }
        if let sportName = sportName { dict["sportName"] = sportName }
        if let sportPosition = sportPosition { dict["sportPosition"] = sportPosition }
        if let dietaryPreference = dietaryPreference { dict["dietaryPreference"] = dietaryPreference.rawValue }
        if let biggestStruggle = biggestStruggle { dict["biggestStruggle"] = biggestStruggle.rawValue }
        if let goalDirection = goalDirection { dict["goalDirection"] = goalDirection.rawValue }
        dict["updatedAt"] = Date().timeIntervalSince1970
        return dict
    }
}

/// User-selected push notification preferences surfaced during Macra onboarding.
/// Persisted on the root user doc under `macraNotificationPreferences` so scheduled
/// server functions (e.g. the admin notification sequences) can honor opt-outs.
struct MacraNotificationPreferences: Hashable {
    var mealReminders: Bool
    var morningLogReminder: Bool
    var endOfDayCheckin: Bool
    /// Iso-8601 hours-minutes (local), used for the morning reminder. Default 08:00.
    var morningReminderTime: TimeOfDay
    /// Iso-8601 hours-minutes (local), used for the evening check-in. Default 20:00.
    var endOfDayReminderTime: TimeOfDay
    /// Local times at which the per-meal reminders fire. Indices map to Meal 1, 2, 3, 4.
    var mealReminderTimes: [TimeOfDay]

    static let `default` = MacraNotificationPreferences(
        mealReminders: false,
        morningLogReminder: false,
        endOfDayCheckin: false,
        morningReminderTime: TimeOfDay(hour: 8, minute: 0),
        endOfDayReminderTime: TimeOfDay(hour: 20, minute: 0),
        mealReminderTimes: [
            TimeOfDay(hour: 8, minute: 0),
            TimeOfDay(hour: 12, minute: 30),
            TimeOfDay(hour: 17, minute: 0),
            TimeOfDay(hour: 20, minute: 0),
        ]
    )

    var hasAnyEnabled: Bool {
        mealReminders || morningLogReminder || endOfDayCheckin
    }

    func toDictionary() -> [String: Any] {
        return [
            "mealReminders": mealReminders,
            "morningLogReminder": morningLogReminder,
            "endOfDayCheckin": endOfDayCheckin,
            "morningReminderTime": morningReminderTime.toDictionary(),
            "endOfDayReminderTime": endOfDayReminderTime.toDictionary(),
            "mealReminderTimes": mealReminderTimes.map { $0.toDictionary() },
            "updatedAt": Date().timeIntervalSince1970,
        ]
    }

    /// Builds a preferences object from a Firestore dictionary, falling back
    /// to `.default` values for any missing fields.
    static func fromDictionary(_ dict: [String: Any]?) -> MacraNotificationPreferences {
        var prefs = MacraNotificationPreferences.default
        guard let dict = dict else { return prefs }

        if let v = dict["mealReminders"] as? Bool { prefs.mealReminders = v }
        if let v = dict["morningLogReminder"] as? Bool { prefs.morningLogReminder = v }
        if let v = dict["endOfDayCheckin"] as? Bool { prefs.endOfDayCheckin = v }
        if let morning = TimeOfDay.fromDictionary(dict["morningReminderTime"] as? [String: Any]) {
            prefs.morningReminderTime = morning
        }
        if let evening = TimeOfDay.fromDictionary(dict["endOfDayReminderTime"] as? [String: Any]) {
            prefs.endOfDayReminderTime = evening
        }
        if let times = dict["mealReminderTimes"] as? [[String: Any]] {
            let parsed = times.compactMap { TimeOfDay.fromDictionary($0) }
            if !parsed.isEmpty { prefs.mealReminderTimes = parsed }
        }
        return prefs
    }
}

/// Email sequence preferences captured during onboarding. Stored alongside push prefs
/// so the admin can show a single opt-out surface. Welcome email fires once regardless
/// of the `tips` / `winback` toggles because it's the transactional confirmation.
struct MacraEmailPreferences: Hashable {
    var tipsSeries: Bool
    var inactivityWinback: Bool

    static let `default` = MacraEmailPreferences(tipsSeries: true, inactivityWinback: true)

    static func fromDictionary(_ dict: [String: Any]?) -> MacraEmailPreferences {
        var prefs = MacraEmailPreferences.default
        guard let dict = dict else { return prefs }
        if let v = dict["tipsSeries"] as? Bool { prefs.tipsSeries = v }
        if let v = dict["inactivityWinback"] as? Bool { prefs.inactivityWinback = v }
        return prefs
    }

    func toDictionary() -> [String: Any] {
        return [
            "tipsSeries": tipsSeries,
            "inactivityWinback": inactivityWinback,
            "updatedAt": Date().timeIntervalSince1970,
        ]
    }
}

struct TimeOfDay: Hashable {
    var hour: Int
    var minute: Int

    func toDictionary() -> [String: Any] {
        return ["hour": hour, "minute": minute]
    }

    static func fromDictionary(_ dict: [String: Any]?) -> TimeOfDay? {
        guard let dict = dict,
              let hour = dict["hour"] as? Int,
              let minute = dict["minute"] as? Int else { return nil }
        return TimeOfDay(hour: hour, minute: minute)
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
    /// Set lazily by the Plan tab when a logged meal in the user's history strongly
    /// matches this item's name. Audited on every Plan tab load — bad matches clear,
    /// good ones survive. Persisted alongside the parent meal's `imageURL`.
    var imageURL: String?
    var imageMatch: MacraSuggestedMealImageMatch?

    var id: String { "\(name)-\(quantity)" }
}

struct MacraSuggestedMealImageMatch: Codable, Hashable, Identifiable {
    var imageURL: String
    var title: String
    var ingredients: [String]
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    var id: String { "\(imageURL)-\(title)" }
}

struct MacraSuggestedMeal: Codable, Hashable, Identifiable {
    var title: String
    var items: [MacraSuggestedMealItem]
    /// Meal-level trainer/user context such as "pre-gym meal" or
    /// "omit on rest days." Mirrored from Fit With Pulse `PlannedMeal.notes`
    /// and editable from Macra's Plan tab.
    var notes: String?
    /// Set lazily by the Plan tab when a logged meal in the user's history matches this
    /// suggestion's items. Persisted back to `users/{uid}/macraSuggestedMealPlans/current`
    /// under `plan.meals[*].imageURL` so we don't keep re-matching on every load.
    var imageURL: String?
    /// Composite meal-level matches. Used when no single logged photo covers every food
    /// in the planned meal, but multiple history photos cover distinct parts of it
    /// (for example egg whites/spinach in one photo and rice cakes in another).
    var imageURLs: [String]?
    var imageMatches: [MacraSuggestedMealImageMatch]?
    /// Slot in the day this meal occupies (1, 2, 3 …). When two meals share
    /// the same `order`, they're variants of the same slot — exactly one
    /// applies on a given weekday based on `daysActive`. Optional for
    /// backward compatibility with cached plans written before per-day
    /// variants existed.
    var order: Int?
    /// Weekday abbreviations ("mon"…"sun") for the days this meal applies
    /// to. `nil` means "every day" (the legacy default). Mirrored from
    /// `PlannedMeal.daysActive` when the active `MealPlan` is copied to
    /// `macraSuggestedMealPlans/current`.
    var daysActive: [String]?

    var id: String {
        if let order, let daysActive, !daysActive.isEmpty {
            return "\(order)-\(daysActive.joined(separator: "_"))-\(title)"
        }
        if let order { return "\(order)-\(title)" }
        return title
    }

    var totalCalories: Int { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Int { items.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Int { items.reduce(0) { $0 + $1.carbs } }
    var totalFat: Int { items.reduce(0) { $0 + $1.fat } }

    /// True when this meal is scheduled on the given weekday string
    /// ("mon"…"sun"). Meals without a `daysActive` restriction apply every
    /// day, matching legacy behavior.
    func appliesOn(_ day: String) -> Bool {
        guard let daysActive, !daysActive.isEmpty else { return true }
        return daysActive.contains(day.lowercased())
    }
}

struct MacraSuggestedMealPlan: Codable, Hashable {
    var meals: [MacraSuggestedMeal]
    var notes: String?

    /// Meals scheduled for `day` ("mon"…"sun"), sorted by `order`. Plans
    /// without per-day variants fall through to the legacy "every meal,
    /// every day" ordering.
    func meals(for day: String) -> [MacraSuggestedMeal] {
        guard hasDayVariants else { return meals }
        return activeMeals(for: day)
    }

    /// One meal per displayed slot for the selected weekday. A day-scoped
    /// variant replaces the broad/default variant for that slot instead of
    /// being added on top of it.
    func activeMeals(for day: String) -> [MacraSuggestedMeal] {
        guard hasDayVariants else { return meals }
        return slots.compactMap { $0.variant(for: day) }
    }

    /// True when at least one meal carries a non-default `daysActive`,
    /// signaling the plan varies by weekday.
    var hasDayVariants: Bool {
        meals.contains { meal in
            guard let days = meal.daysActive else { return false }
            return !days.isEmpty
        }
    }

    /// Distinct weekdays referenced by any meal's `daysActive`. Used to
    /// build the day-toggle pill row in the Plan tab.
    var scopedDays: [String] {
        let order = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        let collected = Set(meals.flatMap { $0.daysActive ?? [] }.map { $0.lowercased() })
        return order.filter(collected.contains)
    }

    /// Groups meals by their `order` slot so slots with multiple variants
    /// (e.g. "Meal 1 A" Mon-Thu/Sun + "Meal 1 B" Fri/Sat) render as a
    /// single swipeable card. Meals without an explicit `order` (legacy
    /// plans written before per-meal variants existed) each get their own
    /// slot keyed by position — they were never variants of each other.
    var slots: [MealSlot] {
        var buckets: [String: (displayOrder: Int, variants: [MacraSuggestedMeal])] = [:]
        var insertionOrder: [String] = []
        for (idx, meal) in meals.enumerated() {
            // Meals with `order` share a bucket so two `order: 1` rows
            // become variants. Meals without `order` are keyed by their
            // raw position, so each gets its own slot — and the display
            // number is `idx + 1` so the legacy "Meal 1, Meal 2, …" feel
            // is preserved on plans that pre-date the variant model.
            let key: String
            let displayOrder: Int
            if let order = meal.order {
                key = "ord:\(order)"
                displayOrder = order
            } else {
                key = "pos:\(idx)"
                displayOrder = idx + 1
            }
            if buckets[key] == nil {
                insertionOrder.append(key)
                buckets[key] = (displayOrder, [meal])
            } else {
                buckets[key]?.variants.append(meal)
            }
        }
        return insertionOrder.compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            // Sort variants: default (no daysActive) first, then by earliest
            // weekday index (Mon=0, Sun=6) so "Meal 1 A" lands on the
            // weekday-broadest variant for visual consistency.
            let sorted = bucket.variants.sorted { lhs, rhs in
                let lhsDays = lhs.daysActive ?? []
                let rhsDays = rhs.daysActive ?? []
                if lhsDays.isEmpty != rhsDays.isEmpty {
                    return lhsDays.isEmpty // empty (= all days) sorts first
                }
                if lhsDays.count != rhsDays.count {
                    return lhsDays.count > rhsDays.count // broader scope first
                }
                let order = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
                let lhsFirst = lhsDays.compactMap { order.firstIndex(of: $0.lowercased()) }.min() ?? Int.max
                let rhsFirst = rhsDays.compactMap { order.firstIndex(of: $0.lowercased()) }.min() ?? Int.max
                return lhsFirst < rhsFirst
            }
            return MealSlot(id: key, order: bucket.displayOrder, variants: sorted)
        }
    }
}

/// A single "Meal N" slot in the plan, optionally with multiple day-scoped
/// variants. View-only (built on demand from `MacraSuggestedMealPlan.slots`).
struct MealSlot: Identifiable, Hashable {
    /// Stable bucket key used for SwiftUI `ForEach` identity. Distinct
    /// from `order` because two slots can render the same display number
    /// only when both meals carry an explicit `order` — legacy meals
    /// without `order` get position-based keys so they never collide.
    let id: String
    /// Display number (1, 2, 3 …) used for the "Meal N" title. Mirrors
    /// `MacraSuggestedMeal.order` when set; falls back to position+1 for
    /// legacy meals.
    let order: Int
    /// Variants of this slot. Always at least one element. When count > 1,
    /// the view renders a swipeable pager with a dot indicator.
    let variants: [MacraSuggestedMeal]

    /// Returns the variant that applies on the given weekday — or `nil` if
    /// the slot is unscoped on that day. Used to default the pager to the
    /// active variant for the date the user is viewing.
    func variant(for day: String) -> MacraSuggestedMeal? {
        let key = day.lowercased()
        if let dayScoped = variants.first(where: { variant in
            guard let days = variant.daysActive, !days.isEmpty else { return false }
            return days.contains(key)
        }) {
            return dayScoped
        }
        return variants.first { ($0.daysActive ?? []).isEmpty }
            ?? variants.first { $0.appliesOn(key) }
    }
}
