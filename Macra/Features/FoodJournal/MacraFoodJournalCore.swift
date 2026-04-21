import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation
import SwiftUI

enum MacraFoodJournalTheme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let panel = Color(red: 0.11, green: 0.12, blue: 0.16)
    static let panelSoft = Color(red: 0.15, green: 0.16, blue: 0.21)
    static let accent = Color(red: 0.30, green: 0.84, blue: 0.52)
    static let accent2 = Color(red: 0.28, green: 0.72, blue: 0.95)
    static let accent3 = Color(red: 0.98, green: 0.67, blue: 0.23)
    static let text = Color.white
    static let textSoft = Color.white.opacity(0.82)
    static let textMuted = Color.white.opacity(0.56)
}

extension Date {
    var macraFoodJournalStartOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var macraFoodJournalDayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = .current
        formatter.dateFormat = "MMddyyyy"
        return formatter.string(from: self.macraFoodJournalStartOfDay)
    }

    var macraFoodJournalMonthKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: self.macraFoodJournalStartOfDay)
    }
}

enum MacraFoodJournalEntryMethod: String, CaseIterable, Codable, Hashable {
    case photo
    case text
    case voice
    case history
    case label
    case quickLog
    case manual
}

struct MacraFoodJournalMacroTarget: Identifiable, Hashable, Codable {
    var id: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    init(id: String = UUID().uuidString, calories: Int, protein: Int, carbs: Int, fat: Int) {
        self.id = id
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

struct MacraFoodJournalMealIngredient: Identifiable, Hashable, Codable {
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

    var netCarbs: Int {
        max(0, carbs - (fiber ?? 0) - (sugarAlcohols ?? 0))
    }

    var hasNetCarbAdjustment: Bool {
        (fiber ?? 0) > 0 || (sugarAlcohols ?? 0) > 0
    }
}

struct MacraFoodJournalMeal: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var caption: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var fiber: Int?
    var sugarAlcohols: Int?
    var imageURL: String?
    var entryMethod: MacraFoodJournalEntryMethod
    var ingredients: [MacraFoodJournalMealIngredient]
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var colorSeed: Double

    init(
        id: String = UUID().uuidString,
        name: String,
        caption: String = "",
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        fiber: Int? = nil,
        sugarAlcohols: Int? = nil,
        imageURL: String? = nil,
        entryMethod: MacraFoodJournalEntryMethod = .manual,
        ingredients: [MacraFoodJournalMealIngredient] = [],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        colorSeed: Double = Double.random(in: 0.1...0.95)
    ) {
        self.id = id
        self.name = name
        self.caption = caption
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.sugarAlcohols = sugarAlcohols
        self.imageURL = imageURL
        self.entryMethod = entryMethod
        self.ingredients = ingredients
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.colorSeed = colorSeed
    }

    var totalMacroCalories: Int {
        (protein * 4) + (carbs * 4) + (fat * 9)
    }

    var hasPhoto: Bool {
        imageURL?.isEmpty == false
    }

    var displayTime: String {
        createdAt.formatted(date: .omitted, time: .shortened)
    }

    var shortSummary: String {
        "\(calories) cal • \(protein)P \(carbs)C \(fat)F"
    }

    /// Legacy-parity net carb calc (max(0, carbs − fiber − sugarAlcohols)).
    /// Sugar-free products sweetened with sugar alcohols (erythritol, xylitol,
    /// allulose, monk fruit blends like Lakanto) have most of their carb
    /// weight absorbed here.
    var netCarbs: Int {
        max(0, carbs - (fiber ?? 0) - (sugarAlcohols ?? 0))
    }

    var hasNetCarbAdjustment: Bool {
        (fiber ?? 0) > 0 || (sugarAlcohols ?? 0) > 0
    }
}

extension MacraFoodJournalMeal {
    init(meal: Meal) {
        let mappedIngredients: [MacraFoodJournalMealIngredient]
        if let detailed = meal.detailedIngredients, !detailed.isEmpty {
            mappedIngredients = detailed.map {
                MacraFoodJournalMealIngredient(
                    id: $0.id,
                    name: $0.name,
                    quantity: $0.quantity,
                    calories: $0.calories,
                    protein: $0.protein,
                    carbs: $0.carbs,
                    fat: $0.fat,
                    fiber: $0.fiber,
                    sugarAlcohols: $0.sugarAlcohols
                )
            }
        } else {
            mappedIngredients = meal.ingredients.map {
                MacraFoodJournalMealIngredient(
                    name: $0,
                    quantity: "",
                    calories: 0,
                    protein: 0,
                    carbs: 0,
                    fat: 0
                )
            }
        }

        self.init(
            id: meal.id,
            name: meal.name,
            caption: meal.caption,
            calories: meal.calories,
            protein: meal.protein,
            carbs: meal.carbs,
            fat: meal.fat,
            fiber: meal.fiber,
            sugarAlcohols: meal.sugarAlcohols,
            imageURL: meal.image.isEmpty ? nil : meal.image,
            entryMethod: MacraFoodJournalEntryMethod(mealEntryMethod: meal.entryMethod),
            ingredients: mappedIngredients,
            notes: "",
            createdAt: meal.createdAt,
            updatedAt: meal.updatedAt
        )
    }
}

private extension MacraFoodJournalMeal {
    var historyIdentityKey: String {
        let ingredientKey = ingredients
            .map { $0.name.historyNormalizedKey }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: ",")

        return [
            name.historyNormalizedKey,
            "\(calories)",
            "\(protein)",
            "\(carbs)",
            "\(fat)",
            ingredientKey
        ].joined(separator: "|")
    }
}

private extension MacraFoodJournalEntryMethod {
    init(mealEntryMethod: MealEntryMethod) {
        switch mealEntryMethod {
        case .photo:
            self = .photo
        case .text:
            self = .text
        case .voice:
            self = .voice
        case .unknown:
            self = .manual
        }
    }
}

private extension String {
    var historyNormalizedKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}

struct MacraFoodJournalDailyInsight: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var response: String
    var query: String
    var icon: String
    var timestamp: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        response: String,
        query: String,
        icon: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.response = response
        self.query = query
        self.icon = icon
        self.timestamp = timestamp
    }
}

/// Single message in a threaded Ask Nora conversation. One doc per message so
/// the thread reconstructs chronologically from the Firestore `timestamp`
/// index, and so the user's question and Nora's reply persist independently
/// (if the network fails mid-turn we can still recover the user's prompt).
enum MacraNoraMessageRole: String, Codable, Hashable {
    case user
    case assistant
}

struct MacraNoraMessage: Identifiable, Hashable, Codable {
    var id: String
    var role: MacraNoraMessageRole
    var content: String
    var timestamp: Date
    /// `MMddyyyy` key matching `Date.macraFoodJournalDayKey`. Denormalized so
    /// per-day queries don't require timestamp range math.
    var dayKey: String
    /// Optional preset metadata for rendering the user's question bubble
    /// with a matching chip color/icon (matches the old NoraInsight preset
    /// treatment). Nil for free-form questions or for assistant replies.
    var accentHex: String?
    var iconSystemName: String?

    init(
        id: String = UUID().uuidString,
        role: MacraNoraMessageRole,
        content: String,
        timestamp: Date = Date(),
        dayKey: String,
        accentHex: String? = nil,
        iconSystemName: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.dayKey = dayKey
        self.accentHex = accentHex
        self.iconSystemName = iconSystemName
    }

    init?(id: String, dictionary: [String: Any]) {
        guard
            let roleRaw = dictionary["role"] as? String,
            let role = MacraNoraMessageRole(rawValue: roleRaw),
            let content = dictionary["content"] as? String,
            let dayKey = dictionary["dayKey"] as? String
        else { return nil }

        self.id = id
        self.role = role
        self.content = content
        self.dayKey = dayKey
        self.accentHex = dictionary["accentHex"] as? String
        self.iconSystemName = dictionary["iconSystemName"] as? String
        if let ts = dictionary["timestamp"] as? Double {
            self.timestamp = Date(timeIntervalSince1970: ts)
        } else if let ts = dictionary["timestamp"] as? Timestamp {
            self.timestamp = ts.dateValue()
        } else {
            self.timestamp = Date()
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "role": role.rawValue,
            "content": content,
            "dayKey": dayKey,
            "timestamp": timestamp.timeIntervalSince1970
        ]
        if let accentHex { dict["accentHex"] = accentHex }
        if let iconSystemName { dict["iconSystemName"] = iconSystemName }
        return dict
    }
}

struct MacraLabelConcern: Identifiable, Hashable, Codable {
    var id: String { concern }
    var concern: String
    var scientificReason: String
    var severity: String
    var relatedIngredients: [String]
}

struct MacraLabelSource: Identifiable, Hashable, Codable {
    var id: String { name + title }
    var name: String
    var type: String
    var title: String
    var url: String?
    var relevance: String

    var icon: String {
        switch type.lowercased() {
        case "government": return "building.2"
        case "international": return "globe"
        case "academic": return "graduationcap"
        case "medical": return "cross.case"
        default: return "doc.text"
        }
    }
}

struct MacraLabelDeepDiveResult: Hashable, Codable {
    var longTermEffects: [String]
    var summary: String
    var researchFindings: [String]
    var regulatoryStatus: String
    var productTitle: String?
}

struct MacraHealthierAlternative: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var reason: String
    var grade: String
    var improvements: [String]
    var whereToFind: String?
    var category: String?
    var productUrl: String?
}

struct MacraLabelGradeResult: Identifiable, Hashable, Codable {
    var id: String
    var grade: String
    var flaggedIngredients: [String]
    var summary: String
    var detailedExplanation: String
    var confidence: Double
    var concerns: [MacraLabelConcern]
    var sources: [MacraLabelSource]
    var productTitle: String?
    var calories: Int?
    var protein: Int?
    var fat: Int?
    var carbs: Int?
    var servingSize: String?
    var sugars: Int?
    var dietaryFiber: Int?
    var sugarAlcohols: Int?
    var sodium: Int?

    init(
        id: String = UUID().uuidString,
        grade: String,
        flaggedIngredients: [String],
        summary: String,
        detailedExplanation: String,
        confidence: Double,
        concerns: [MacraLabelConcern] = [],
        sources: [MacraLabelSource] = [],
        productTitle: String? = nil,
        calories: Int? = nil,
        protein: Int? = nil,
        fat: Int? = nil,
        carbs: Int? = nil,
        servingSize: String? = nil,
        sugars: Int? = nil,
        dietaryFiber: Int? = nil,
        sugarAlcohols: Int? = nil,
        sodium: Int? = nil
    ) {
        self.id = id
        self.grade = grade
        self.flaggedIngredients = flaggedIngredients
        self.summary = summary
        self.detailedExplanation = detailedExplanation
        self.confidence = confidence
        self.concerns = concerns
        self.sources = sources
        self.productTitle = productTitle
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.servingSize = servingSize
        self.sugars = sugars
        self.dietaryFiber = dietaryFiber
        self.sugarAlcohols = sugarAlcohols
        self.sodium = sodium
    }

    var hasStoredMacros: Bool {
        calories != nil || protein != nil || fat != nil || carbs != nil
    }

    var confidencePercentage: Int {
        Int((confidence * 100).rounded())
    }
}

struct MacraScannedLabel: Identifiable, Hashable, Codable {
    var id: String
    var gradeResult: MacraLabelGradeResult
    var imageURL: String?
    var createdAt: Date
    var userNotes: String
    var productTitle: String?
    var productTitleEdited: Bool
    var qaHistory: [String]
    var deepDiveResult: MacraLabelDeepDiveResult?
    var alternatives: [MacraHealthierAlternative]

    init(
        id: String = UUID().uuidString,
        gradeResult: MacraLabelGradeResult,
        imageURL: String? = nil,
        createdAt: Date = Date(),
        userNotes: String = "",
        productTitle: String? = nil,
        productTitleEdited: Bool = false,
        qaHistory: [String] = [],
        deepDiveResult: MacraLabelDeepDiveResult? = nil,
        alternatives: [MacraHealthierAlternative] = []
    ) {
        self.id = id
        self.gradeResult = gradeResult
        self.imageURL = imageURL
        self.createdAt = createdAt
        self.userNotes = userNotes
        self.productTitle = productTitle ?? gradeResult.productTitle
        self.productTitleEdited = productTitleEdited
        self.qaHistory = qaHistory
        self.deepDiveResult = deepDiveResult
        self.alternatives = alternatives
    }

    var displayTitle: String {
        (productTitle?.isEmpty == false ? productTitle : gradeResult.productTitle) ?? "Scanned Label"
    }
}

extension MacraScannedLabel {
    init(id: String, data: [String: Any]) {
        var gradeData = data["gradeResult"] as? [String: Any] ?? data
        if gradeData["productTitle"] == nil {
            gradeData["productTitle"] = data["productTitle"]
        }

        let qaHistory = (data["qaHistory"] as? [[String: Any]])?.compactMap {
            ($0["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? nutritionStringArray(from: data["qaHistory"])

        let productTitle = (data["productTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.init(
            id: id,
            gradeResult: MacraLabelGradeResult(labelData: gradeData),
            imageURL: data["imageURL"] as? String ?? data["labelImageURL"] as? String,
            createdAt: nutritionDate(from: data["createdAt"] ?? data["scannedAt"]),
            userNotes: data["userNotes"] as? String ?? data["notes"] as? String ?? "",
            productTitle: productTitle?.isEmpty == false ? productTitle : nil,
            productTitleEdited: data["productTitleEdited"] as? Bool ?? false,
            qaHistory: qaHistory,
            deepDiveResult: (data["deepDiveResult"] as? [String: Any]).map(MacraLabelDeepDiveResult.init(deepDiveData:)),
            alternatives: (data["alternatives"] as? [[String: Any]])?.map(MacraHealthierAlternative.init(alternativeData:)) ?? []
        )
    }
}

private extension MacraLabelGradeResult {
    init(labelData: [String: Any]) {
        self.init(
            grade: labelData["grade"] as? String ?? "F",
            flaggedIngredients: nutritionStringArray(from: labelData["flaggedIngredients"]),
            summary: labelData["summary"] as? String ?? "Unable to analyze label",
            detailedExplanation: labelData["detailedExplanation"] as? String ?? labelData["summary"] as? String ?? "Unable to analyze label",
            confidence: nutritionDouble(from: labelData["confidence"]),
            concerns: (labelData["concerns"] as? [[String: Any]])?.map(MacraLabelConcern.init(concernData:)) ?? [],
            sources: (labelData["sources"] as? [[String: Any]])?.map(MacraLabelSource.init(sourceData:)) ?? [],
            productTitle: labelData["productTitle"] as? String,
            calories: nutritionOptionalInt(from: labelData["calories"]),
            protein: nutritionOptionalInt(from: labelData["protein"]),
            fat: nutritionOptionalInt(from: labelData["fat"]),
            carbs: nutritionOptionalInt(from: labelData["carbs"]),
            servingSize: labelData["servingSize"] as? String,
            sugars: nutritionOptionalInt(from: labelData["sugars"]),
            dietaryFiber: nutritionOptionalInt(from: labelData["dietaryFiber"]),
            sugarAlcohols: nutritionOptionalInt(from: labelData["sugarAlcohols"]),
            sodium: nutritionOptionalInt(from: labelData["sodium"])
        )
    }
}

private extension MacraLabelConcern {
    init(concernData: [String: Any]) {
        self.init(
            concern: concernData["concern"] as? String ?? "",
            scientificReason: concernData["scientificReason"] as? String ?? "",
            severity: concernData["severity"] as? String ?? "medium",
            relatedIngredients: nutritionStringArray(from: concernData["relatedIngredients"])
        )
    }
}

private extension MacraLabelSource {
    init(sourceData: [String: Any]) {
        self.init(
            name: sourceData["name"] as? String ?? "",
            type: sourceData["type"] as? String ?? "Government",
            title: sourceData["title"] as? String ?? "",
            url: sourceData["url"] as? String,
            relevance: sourceData["relevance"] as? String ?? ""
        )
    }
}

private extension MacraLabelDeepDiveResult {
    init(deepDiveData: [String: Any]) {
        let effects = (deepDiveData["longTermEffects"] as? [[String: Any]])?.map { effect in
            [effect["effect"] as? String ?? "", effect["description"] as? String ?? ""]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: ": ")
        } ?? nutritionStringArray(from: deepDiveData["longTermEffects"])

        let findings = (deepDiveData["researchFindings"] as? [[String: Any]])?.map { finding in
            [finding["title"] as? String ?? "", finding["summary"] as? String ?? ""]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: ": ")
        } ?? nutritionStringArray(from: deepDiveData["researchFindings"])

        let nutritionalBreakdown = deepDiveData["nutritionalBreakdown"] as? [String: Any]

        let summary = [
            deepDiveData["summary"] as? String ?? "",
            nutritionalBreakdown?["macroAnalysis"] as? String ?? "",
            nutritionalBreakdown?["calorieContext"] as? String ?? "",
            findings.first ?? ""
        ]
        .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "Deep dive saved for this label."

        let regulatoryData = deepDiveData["regulatoryStatus"] as? [String: Any]
        let regulatoryStatus = regulatoryData.map {
            [$0["fdaStatus"] as? String ?? "", $0["whoGuidance"] as? String ?? ""]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " ")
        } ?? (deepDiveData["regulatoryStatus"] as? String) ?? ""

        self.init(
            longTermEffects: effects,
            summary: summary,
            researchFindings: findings,
            regulatoryStatus: regulatoryStatus.isEmpty ? "No regulatory notes saved." : regulatoryStatus,
            productTitle: deepDiveData["productTitle"] as? String
        )
    }
}

private extension MacraHealthierAlternative {
    init(alternativeData: [String: Any]) {
        self.init(
            id: alternativeData["id"] as? String ?? UUID().uuidString,
            name: alternativeData["name"] as? String ?? "",
            reason: alternativeData["reason"] as? String ?? "",
            grade: alternativeData["grade"] as? String ?? "A",
            improvements: nutritionStringArray(from: alternativeData["improvements"]),
            whereToFind: alternativeData["whereToFind"] as? String,
            category: alternativeData["category"] as? String,
            productUrl: alternativeData["productUrl"] as? String
        )
    }
}

struct MacraFoodJournalPlannedMeal: Identifiable, Hashable, Codable {
    var id: String
    var mealIDs: [String]
    var order: Int
    var notes: String?
    var isCompleted: Bool
    var completedAt: Date?
}

struct MacraFoodJournalDaySummary: Identifiable, Hashable {
    var id: String { date.macraFoodJournalDayKey }
    var date: Date
    var meals: [MacraFoodJournalMeal]
    var pinnedMeals: [MacraFoodJournalMeal]
    var macroTarget: MacraFoodJournalMacroTarget?
    var insights: [MacraFoodJournalDailyInsight]
    var labelScans: [MacraScannedLabel]
    var loggedSupplements: [LoggedSupplement] = []

    var mealCalories: Int { meals.reduce(0) { $0 + $1.calories } }
    var mealProtein: Int { meals.reduce(0) { $0 + $1.protein } }
    var mealCarbs: Int { meals.reduce(0) { $0 + $1.carbs } }
    var mealFat: Int { meals.reduce(0) { $0 + $1.fat } }

    var supplementCalories: Int { loggedSupplements.reduce(0) { $0 + $1.calories } }
    var supplementProtein: Int { loggedSupplements.reduce(0) { $0 + $1.protein } }
    var supplementCarbs: Int { loggedSupplements.reduce(0) { $0 + $1.carbs } }
    var supplementFat: Int { loggedSupplements.reduce(0) { $0 + $1.fat } }

    var totalCalories: Int { mealCalories + supplementCalories }
    var totalProtein: Int { mealProtein + supplementProtein }
    var totalCarbs: Int { mealCarbs + supplementCarbs }
    var totalFat: Int { mealFat + supplementFat }

    var hasSupplementMacros: Bool {
        supplementCalories > 0 || supplementProtein > 0 || supplementCarbs > 0 || supplementFat > 0
    }
    var mealCount: Int { meals.count }
    var hasNutritionData: Bool { !meals.isEmpty || !loggedSupplements.isEmpty }
}

struct MacraFoodJournalMonthDay: Identifiable, Hashable {
    var id: String
    var date: Date
    var mealCount: Int
    var calories: Int

    init(date: Date, mealCount: Int, calories: Int) {
        self.id = date.macraFoodJournalDayKey
        self.date = date
        self.mealCount = mealCount
        self.calories = calories
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

protocol MacraFoodJournalStoreProviding: AnyObject {
    func daySummary(for date: Date) -> MacraFoodJournalDaySummary
    func meals(on date: Date) -> [MacraFoodJournalMeal]
    func monthDays(containing date: Date) -> [MacraFoodJournalMonthDay]
    func photoHistory(limit: Int) -> [MacraFoodJournalMeal]
    func labelScans() -> [MacraScannedLabel]
    func pinnedMeals() -> [MacraFoodJournalMeal]
    func meal(with id: String) -> MacraFoodJournalMeal?
    func addMeal(_ meal: MacraFoodJournalMeal, on date: Date)
    func updateMeal(_ meal: MacraFoodJournalMeal)
    func deleteMeal(id: String, on date: Date)
    func pinMeal(_ meal: MacraFoodJournalMeal)
    func unpinMeal(id: String)
    func logAllPinnedMeals(on date: Date)
    func addDailyInsight(_ insight: MacraFoodJournalDailyInsight, for date: Date)
    func saveLabelScan(_ scan: MacraScannedLabel)
    func updateLabelScan(_ scan: MacraScannedLabel)
    func deleteLabelScan(id: String)
    func logMealFromHistory(_ meal: MacraFoodJournalMeal, on date: Date)
    func noraMessages(on date: Date) -> [MacraNoraMessage]
    func setNoraMessages(_ messages: [MacraNoraMessage], on date: Date)
    func appendNoraMessage(_ message: MacraNoraMessage)
    func datesWithLoggedMeals() -> Set<Date>
}

final class MacraFoodJournalStore: ObservableObject, MacraFoodJournalStoreProviding {
    @Published private var mealsByDay: [String: [MacraFoodJournalMeal]]
    @Published private var insightsByDay: [String: [MacraFoodJournalDailyInsight]]
    @Published private var scannedLabels: [MacraScannedLabel]
    @Published private var pinnedMealIDs: Set<String>
    @Published private var macroTargetsByDay: [String: MacraFoodJournalMacroTarget]
    @Published private var noraMessagesByDay: [String: [MacraNoraMessage]]

    init(
        mealsByDay: [String: [MacraFoodJournalMeal]] = [:],
        insightsByDay: [String: [MacraFoodJournalDailyInsight]] = [:],
        scannedLabels: [MacraScannedLabel] = [],
        pinnedMealIDs: Set<String> = [],
        macroTargetsByDay: [String: MacraFoodJournalMacroTarget] = [:],
        noraMessagesByDay: [String: [MacraNoraMessage]] = [:]
    ) {
        self.mealsByDay = mealsByDay
        self.insightsByDay = insightsByDay
        self.scannedLabels = scannedLabels
        self.pinnedMealIDs = pinnedMealIDs
        self.macroTargetsByDay = macroTargetsByDay
        self.noraMessagesByDay = noraMessagesByDay
    }

    static var preview: MacraFoodJournalStore {
        let store = MacraFoodJournalStore()
        store.seedPreviewData()
        return store
    }

    func daySummary(for date: Date) -> MacraFoodJournalDaySummary {
        let dayKey = date.macraFoodJournalDayKey
        let meals = mealsByDay[dayKey, default: []].sorted { $0.createdAt < $1.createdAt }
        let pinned = meals.filter { pinnedMealIDs.contains($0.id) }
        let insights = insightsByDay[dayKey, default: []]
        return MacraFoodJournalDaySummary(
            date: date,
            meals: meals,
            pinnedMeals: pinned,
            macroTarget: macroTargetsByDay[dayKey],
            insights: insights,
            labelScans: scannedLabels
        )
    }

    func meals(on date: Date) -> [MacraFoodJournalMeal] {
        mealsByDay[date.macraFoodJournalDayKey, default: []].sorted { $0.createdAt < $1.createdAt }
    }

    func monthDays(containing date: Date) -> [MacraFoodJournalMonthDay] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        return range.compactMap { day in
            guard let current = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else { return nil }
            let meals = meals(on: current)
            return MacraFoodJournalMonthDay(date: current, mealCount: meals.count, calories: meals.reduce(0) { $0 + $1.calories })
        }
    }

    func photoHistory(limit: Int = 24) -> [MacraFoodJournalMeal] {
        mealsByDay
            .values
            .flatMap { $0 }
            .filter { $0.hasPhoto }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { $0 }
    }

    func labelScans() -> [MacraScannedLabel] {
        scannedLabels.sorted { $0.createdAt > $1.createdAt }
    }

    func pinnedMeals() -> [MacraFoodJournalMeal] {
        mealsByDay.values
            .flatMap { $0 }
            .filter { pinnedMealIDs.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    func meal(with id: String) -> MacraFoodJournalMeal? {
        mealsByDay.values.flatMap { $0 }.first { $0.id == id }
    }

    func addMeal(_ meal: MacraFoodJournalMeal, on date: Date) {
        let key = date.macraFoodJournalDayKey
        var nextMeal = meal
        nextMeal.updatedAt = Date()
        if nextMeal.createdAt == .distantPast {
            nextMeal.createdAt = date
        }
        mealsByDay[key, default: []].append(nextMeal)
        objectWillChange.send()
    }

    func updateMeal(_ meal: MacraFoodJournalMeal) {
        let newKey = meal.createdAt.macraFoodJournalDayKey
        let currentKey = mealsByDay.first(where: { $0.value.contains(where: { $0.id == meal.id }) })?.key

        guard let currentKey else { return }

        if currentKey == newKey {
            guard var list = mealsByDay[currentKey], let index = list.firstIndex(where: { $0.id == meal.id }) else { return }
            list[index] = meal
            mealsByDay[currentKey] = list
        } else {
            mealsByDay[currentKey]?.removeAll { $0.id == meal.id }
            mealsByDay[newKey, default: []].append(meal)
        }

        objectWillChange.send()
    }

    func deleteMeal(id: String, on date: Date) {
        for key in mealsByDay.keys {
            mealsByDay[key]?.removeAll { $0.id == id }
        }
        pinnedMealIDs.remove(id)
        objectWillChange.send()
    }

    func pinMeal(_ meal: MacraFoodJournalMeal) {
        pinnedMealIDs.insert(meal.id)
        objectWillChange.send()
    }

    func unpinMeal(id: String) {
        pinnedMealIDs.remove(id)
        objectWillChange.send()
    }

    func logAllPinnedMeals(on date: Date) {
        for meal in pinnedMeals() {
            var copy = meal
            copy.id = UUID().uuidString
            copy.createdAt = date
            copy.updatedAt = date
            addMeal(copy, on: date)
        }
    }

    func addDailyInsight(_ insight: MacraFoodJournalDailyInsight, for date: Date) {
        let key = date.macraFoodJournalDayKey
        insightsByDay[key, default: []].insert(insight, at: 0)
        objectWillChange.send()
    }

    func saveLabelScan(_ scan: MacraScannedLabel) {
        scannedLabels.insert(scan, at: 0)
        objectWillChange.send()
    }

    func updateLabelScan(_ scan: MacraScannedLabel) {
        guard let index = scannedLabels.firstIndex(where: { $0.id == scan.id }) else { return }
        scannedLabels[index] = scan
        objectWillChange.send()
    }

    func deleteLabelScan(id: String) {
        scannedLabels.removeAll { $0.id == id }
        objectWillChange.send()
    }

    func logMealFromHistory(_ meal: MacraFoodJournalMeal, on date: Date) {
        var copy = meal
        copy.id = UUID().uuidString
        copy.createdAt = date
        copy.updatedAt = date
        copy.entryMethod = .history
        addMeal(copy, on: date)
    }

    func noraMessages(on date: Date) -> [MacraNoraMessage] {
        noraMessagesByDay[date.macraFoodJournalDayKey, default: []]
            .sorted { $0.timestamp < $1.timestamp }
    }

    func setNoraMessages(_ messages: [MacraNoraMessage], on date: Date) {
        let key = date.macraFoodJournalDayKey
        noraMessagesByDay[key] = messages.sorted { $0.timestamp < $1.timestamp }
        objectWillChange.send()
    }

    func appendNoraMessage(_ message: MacraNoraMessage) {
        var list = noraMessagesByDay[message.dayKey, default: []]
        if let existing = list.firstIndex(where: { $0.id == message.id }) {
            list[existing] = message
        } else {
            list.append(message)
        }
        list.sort { $0.timestamp < $1.timestamp }
        noraMessagesByDay[message.dayKey] = list
        objectWillChange.send()
    }

    func datesWithLoggedMeals() -> Set<Date> {
        let calendar = Calendar.current
        var result: Set<Date> = []
        for (_, meals) in mealsByDay where !meals.isEmpty {
            if let first = meals.first {
                result.insert(calendar.startOfDay(for: first.createdAt))
            }
        }
        return result
    }

    private func seedPreviewData() {
        let calendar = Calendar.current
        let now = Date()
        let dates = (-2...0).compactMap { calendar.date(byAdding: .day, value: $0, to: now) }

        let sampleMeals: [MacraFoodJournalMeal] = [
            MacraFoodJournalMeal(
                name: "Greek yogurt berry bowl",
                caption: "High protein breakfast",
                calories: 420,
                protein: 34,
                carbs: 32,
                fat: 15,
                imageURL: "https://images.unsplash.com/photo-1490645935967-10de6ba17061",
                entryMethod: .photo,
                ingredients: [
                    MacraFoodJournalMealIngredient(name: "Greek yogurt", quantity: "1 cup", calories: 150, protein: 22, carbs: 8, fat: 4),
                    MacraFoodJournalMealIngredient(name: "Blueberries", quantity: "3/4 cup", calories: 60, protein: 1, carbs: 14, fat: 0)
                ],
                notes: "Fast weekday breakfast"
            ),
            MacraFoodJournalMeal(
                name: "Chicken rice bowl",
                caption: "Lunch from the office",
                calories: 670,
                protein: 52,
                carbs: 62,
                fat: 24,
                imageURL: "https://images.unsplash.com/photo-1547592180-85f173990554",
                entryMethod: .text,
                ingredients: [
                    MacraFoodJournalMealIngredient(name: "Chicken breast", quantity: "6 oz", calories: 260, protein: 46, carbs: 0, fat: 6),
                    MacraFoodJournalMealIngredient(name: "Rice", quantity: "1.5 cups", calories: 330, protein: 6, carbs: 60, fat: 1)
                ],
                notes: "Extra salsa on top",
                isPinned: true
            ),
            MacraFoodJournalMeal(
                name: "Protein smoothie",
                caption: "Post workout shake",
                calories: 320,
                protein: 38,
                carbs: 24,
                fat: 6,
                imageURL: "https://images.unsplash.com/photo-1572490122747-3968b75cc699",
                entryMethod: .voice,
                ingredients: [
                    MacraFoodJournalMealIngredient(name: "Whey protein", quantity: "1 scoop", calories: 120, protein: 24, carbs: 2, fat: 1),
                    MacraFoodJournalMealIngredient(name: "Banana", quantity: "1 medium", calories: 105, protein: 1, carbs: 27, fat: 0)
                ],
                notes: "Blended with oat milk"
            ),
            MacraFoodJournalMeal(
                name: "Salmon and vegetables",
                caption: "Dinner after training",
                calories: 580,
                protein: 44,
                carbs: 30,
                fat: 28,
                imageURL: "https://images.unsplash.com/photo-1467003909585-2f8a72700288",
                entryMethod: .history,
                ingredients: [
                    MacraFoodJournalMealIngredient(name: "Salmon", quantity: "5 oz", calories: 280, protein: 32, carbs: 0, fat: 16),
                    MacraFoodJournalMealIngredient(name: "Broccoli", quantity: "1 cup", calories: 55, protein: 4, carbs: 11, fat: 1)
                ],
                notes: "Lemon and olive oil"
            )
        ]

        for (offset, date) in dates.enumerated() {
            let baseMeals = sampleMeals.enumerated().map { index, meal in
                var copy = meal
                copy.id = "\(date.macraFoodJournalDayKey)-\(index)"
                copy.createdAt = calendar.date(byAdding: .minute, value: (offset * 90) + (index * 45), to: date) ?? date
                copy.updatedAt = copy.createdAt
                copy.isPinned = meal.isPinned
                return copy
            }
            mealsByDay[date.macraFoodJournalDayKey] = baseMeals
        }

        if let insightDate = dates.last {
            let dayKey = insightDate.macraFoodJournalDayKey
            insightsByDay[dayKey] = [
                MacraFoodJournalDailyInsight(
                    title: "Protein is ahead of target",
                    response: "You are 28g ahead of your target by midday. Consider a lighter dinner if you want to stay near today's calorie ceiling.",
                    query: "How did I do today?",
                    icon: "bolt.fill",
                    timestamp: insightDate
                ),
                MacraFoodJournalDailyInsight(
                    title: "Fiber gap",
                    response: "Adding one fruit or a veggie side would close the remaining fiber gap with very little calorie cost.",
                    query: "What should I improve?",
                    icon: "leaf.fill",
                    timestamp: insightDate
                )
            ]

            macroTargetsByDay[dayKey] = MacraFoodJournalMacroTarget(calories: 2400, protein: 190, carbs: 230, fat: 80)
        }

        if let firstMeal = mealsByDay.values.flatMap({ $0 }).first {
            pinnedMealIDs.insert(firstMeal.id)
        }

        let labelResult = MacraLabelGradeResult(
            grade: "B",
            flaggedIngredients: ["Natural flavors", "Added sugar"],
            summary: "Good label overall with a few ingredients worth watching.",
            detailedExplanation: "The product is high in protein and low in saturated fat, but the added sugar and flavoring blend make it a slightly less clean option than the best-in-class alternatives.",
            confidence: 0.88,
            concerns: [
                MacraLabelConcern(
                    concern: "Added sugar",
                    scientificReason: "Repeated intake may make it harder to stay within a stable calorie target.",
                    severity: "medium",
                    relatedIngredients: ["cane sugar"]
                )
            ],
            sources: [
                MacraLabelSource(
                    name: "USDA",
                    type: "Government",
                    title: "Nutrition Facts and Ingredient Label Guidance",
                    url: nil,
                    relevance: "Supports serving-size and nutrient interpretation"
                )
            ],
            productTitle: "Protein Crunch Bar",
            calories: 210,
            protein: 20,
            fat: 7,
            carbs: 18,
            servingSize: "1 bar",
            sugars: 8,
            dietaryFiber: 5,
            sodium: 160
        )

        scannedLabels = [
            MacraScannedLabel(
                gradeResult: labelResult,
                imageURL: "https://images.unsplash.com/photo-1547592180-85f173990554",
                userNotes: "Bought after training",
                deepDiveResult: MacraLabelDeepDiveResult(
                    longTermEffects: ["Stable energy", "Slightly higher sugar load"],
                    summary: "A balanced product that works in moderation.",
                    researchFindings: ["Higher protein snacks can improve satiety."],
                    regulatoryStatus: "No immediate red flags",
                    productTitle: "Protein Crunch Bar"
                ),
                alternatives: [
                    MacraHealthierAlternative(
                        id: UUID().uuidString,
                        name: "Higher-fiber bar",
                        reason: "Similar protein with less sugar",
                        grade: "A",
                        improvements: ["Lower sugar", "More fiber"],
                        whereToFind: "Grocery aisle",
                        category: "Snack",
                        productUrl: nil
                    )
                ]
            )
        ]
    }
}

enum MacraFoodJournalSurface: String, CaseIterable, Identifiable {
    case day
    case month
    case history
    case label
    case share

    var id: String { rawValue }
}

enum MacraFoodJournalSheet: Identifiable, Hashable {
    case mealDetails(String)
    case imageConfirmation
    case foodIdentifier(String?)
    case mealNotePad
    case voiceEntry
    case scanFood
    case labelScan
    case fromHistory
    case photoGrid
    case month
    case share
    case labelHistory
    case labelDetail(String)
    case macroBreakdown(MacraFoodJournalMacroType)
    case netCarbInfo

    var id: String {
        switch self {
        case .mealDetails(let id): return "mealDetails-\(id)"
        case .imageConfirmation: return "imageConfirmation"
        case .foodIdentifier(let id): return "foodIdentifier-\(id ?? "none")"
        case .mealNotePad: return "mealNotePad"
        case .voiceEntry: return "voiceEntry"
        case .scanFood: return "scanFood"
        case .labelScan: return "labelScan"
        case .fromHistory: return "fromHistory"
        case .photoGrid: return "photoGrid"
        case .month: return "month"
        case .share: return "share"
        case .labelHistory: return "labelHistory"
        case .labelDetail(let id): return "labelDetail-\(id)"
        case .macroBreakdown(let macro): return "macroBreakdown-\(macro.rawValue)"
        case .netCarbInfo: return "netCarbInfo"
        }
    }
}

final class MacraFoodJournalViewModel: ObservableObject {
    @Published var selectedDate: Date
    @Published var selectedSurface: MacraFoodJournalSurface = .day
    @Published var activeSheet: MacraFoodJournalSheet?
    @Published var draftMealTitle: String = ""
    @Published var draftMealCaption: String = ""
    @Published var draftMealNotes: String = ""
    @Published var draftMealImage: UIImage?
    @Published var voiceTranscript: String = "Tap record to capture a spoken meal entry."
    @Published var searchQuery: String = ""
    @Published var isRecordingVoice: Bool = false
    @Published var isAnalyzing: Bool = false
    @Published var selectedLabelScanID: String?
    @Published var mealHistory: [MacraFoodJournalMeal] = []
    @Published var isLoadingHistory = false
    @Published var historyError: String?
    @Published var labelScanHistory: [MacraScannedLabel] = []
    @Published var isLoadingLabelHistory = false
    @Published var labelHistoryError: String?
    @Published var isAnalyzingLabel = false
    @Published var labelAnalysisError: String?
    @Published var loggedSupplementsByDay: [String: [LoggedSupplement]] = [:]
    var shouldReturnHomeAfterMealSave = false
    var onMealSaved: ((MacraFoodJournalMeal) -> Void)?

    let store: MacraFoodJournalStore
    private var cancellables: Set<AnyCancellable> = []
    private var supplementFetchDates: Set<String> = []

    init(store: MacraFoodJournalStore = MacraFoodJournalStore(), selectedDate: Date = Date()) {
        self.store = store
        self.selectedDate = selectedDate
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        $selectedDate
            .removeDuplicates { Calendar.current.isDate($0, inSameDayAs: $1) }
            .sink { [weak self] date in self?.loadLoggedSupplements(for: date) }
            .store(in: &cancellables)
        loadLoggedSupplements(for: selectedDate)
    }

    var daySummary: MacraFoodJournalDaySummary {
        var summary = store.daySummary(for: selectedDate)
        summary.loggedSupplements = loggedSupplementsByDay[selectedDate.macraFoodJournalDayKey] ?? []
        return summary
    }

    var loggedSupplementsForSelectedDay: [LoggedSupplement] {
        loggedSupplementsByDay[selectedDate.macraFoodJournalDayKey] ?? []
    }

    func loadLoggedSupplements(for date: Date, force: Bool = false) {
        let key = date.macraFoodJournalDayKey
        if !force, supplementFetchDates.contains(key) { return }
        supplementFetchDates.insert(key)
        SupplementService.sharedInstance.getLoggedSupplements(byDate: date) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let supplements):
                    self.loggedSupplementsByDay[key] = supplements
                case .failure:
                    // Keep whatever's already cached. A failure shouldn't wipe the
                    // rollup; the Supps tab surfaces the real error state.
                    if self.loggedSupplementsByDay[key] == nil {
                        self.loggedSupplementsByDay[key] = []
                    }
                }
            }
        }
    }

    func refreshLoggedSupplementsForSelectedDay() {
        loadLoggedSupplements(for: selectedDate, force: true)
    }

    var loggingStats: MacraFoodJournalLoggingStats {
        MacraFoodJournalLoggingStats(
            loggedDates: store.datesWithLoggedMeals(),
            referenceDate: Date()
        )
    }

    var monthDays: [MacraFoodJournalMonthDay] {
        store.monthDays(containing: selectedDate)
    }

    var mealsForSelectedDay: [MacraFoodJournalMeal] {
        store.meals(on: selectedDate)
    }

    var pinnedMeals: [MacraFoodJournalMeal] {
        store.pinnedMeals()
    }

    var labelScans: [MacraScannedLabel] {
        uniqueLabelScans(labelScanHistory + store.labelScans())
    }

    var photoHistory: [MacraFoodJournalMeal] {
        uniqueMeals(store.photoHistory(limit: 24) + mealHistory.filter(\.hasPhoto))
    }

    var allMealHistory: [MacraFoodJournalMeal] {
        uniqueMeals(mealHistory + store.photoHistory(limit: 50) + mealsForSelectedDay)
    }

    func selectToday() {
        selectedDate = Date()
        selectedSurface = .day
    }

    func nextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
    }

    func previousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
    }

    @Published var analysisError: String?

    /// Text / voice entries must go through GPT so we actually get macros.
    /// Photo / manual / history stay on the direct-save path since their data
    /// is either already analyzed upstream or captured manually.
    private func shouldAnalyzeBeforeSaving(_ entryMethod: MacraFoodJournalEntryMethod) -> Bool {
        switch entryMethod {
        case .text, .voice: return true
        case .photo, .history, .label, .quickLog, .manual: return false
        }
    }

    /// Resolves the `createdAt` timestamp for a newly-logged meal.
    ///
    /// `selectedDate` represents the day the user is *viewing*, and elsewhere
    /// in the app (notably `HomeViewModel`) it's normalized to
    /// `Calendar.current.startOfDay(for:)` — i.e. midnight. Using it verbatim
    /// as `createdAt` would stamp every new meal at 12:00 AM even when the
    /// user is logging in real time.
    ///
    /// Rules:
    /// - Viewing today → return the current wall-clock `Date()`.
    /// - Viewing a past/future day → keep that day, but stamp it with the
    ///   current time-of-day rather than midnight. Users back-filling a day
    ///   get a sensible default they can still adjust from meal details.
    private func resolvedLogTimestamp() -> Date {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDate(selectedDate, inSameDayAs: now) {
            return now
        }
        let timeOfDay = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(
            bySettingHour: timeOfDay.hour ?? 12,
            minute: timeOfDay.minute ?? 0,
            second: timeOfDay.second ?? 0,
            of: selectedDate
        ) ?? now
    }

    @discardableResult
    func addMealFromDraft(entryMethod: MacraFoodJournalEntryMethod, imageURL: String? = nil) -> MacraFoodJournalMeal {
        let title = draftMealTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = draftMealCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = draftMealNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[Macra][Journal.addMealFromDraft] entryMethod:\(entryMethod.rawValue) title:'\(title)' captionLen:\(caption.count) hasImage:\(imageURL != nil)")

        let logTimestamp = resolvedLogTimestamp()

        if shouldAnalyzeBeforeSaving(entryMethod) {
            // Kick off analysis; return a placeholder meal for the legacy
            // discardableResult callers but don't persist it until GPT returns.
            analyzeAndSaveMealFromDraft(entryMethod: entryMethod, imageURL: imageURL)
            return MacraFoodJournalMeal(
                name: title.isEmpty ? "Analyzing…" : title,
                caption: caption,
                calories: 0,
                protein: 0,
                carbs: 0,
                fat: 0,
                imageURL: imageURL,
                entryMethod: entryMethod,
                notes: notes,
                createdAt: logTimestamp,
                updatedAt: Date()
            )
        }

        let fallbackTitle = title.isEmpty ? "Untitled meal" : title
        let meal = MacraFoodJournalMeal(
            name: fallbackTitle,
            caption: caption,
            calories: 0,
            protein: 0,
            carbs: 0,
            fat: 0,
            imageURL: imageURL,
            entryMethod: entryMethod,
            notes: notes,
            createdAt: logTimestamp,
            updatedAt: Date()
        )
        print("[Macra][Journal.addMealFromDraft] Direct-save (no analysis) — saving meal id:\(meal.id) name:'\(meal.name)' at \(logTimestamp)")
        saveFoodJournalMeal(meal, on: selectedDate, detailsDestination: .foodIdentifier(meal.id))
        draftMealTitle = ""
        draftMealCaption = ""
        draftMealNotes = ""
        draftMealImage = nil
        isAnalyzing = false
        return meal
    }

    /// Runs the draft through the GPT analyzer and only persists the meal once
    /// we have real macros back. Mirrors QuickLifts' load → analyze → confirm
    /// flow for text and voice entries.
    func analyzeAndSaveMealFromDraft(entryMethod: MacraFoodJournalEntryMethod, imageURL: String? = nil) {
        let title = draftMealTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = draftMealCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = draftMealNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        // The caption is what the user typed as the meal description; fall back
        // to title when caption is empty so single-field entries still analyze.
        let analysisDescription = caption.isEmpty ? title : caption
        let analysisTitle = (caption.isEmpty ? "" : title)

        guard !analysisDescription.isEmpty else {
            print("[Macra][Journal.analyzeAndSaveMealFromDraft] ❌ both title and caption empty — refusing to analyze")
            analysisError = "Add a title or description before analyzing."
            return
        }

        print("[Macra][Journal.analyzeAndSaveMealFromDraft] ▶️ Starting — entryMethod:\(entryMethod.rawValue) title:'\(analysisTitle)' descLen:\(analysisDescription.count)")

        isAnalyzing = true
        analysisError = nil

        // Capture the log timestamp now so the analyzer's round-trip latency
        // doesn't shift the meal later in the day than when the user tapped.
        let createdAt = resolvedLogTimestamp()
        let saveDate = selectedDate
        print("[Macra][Journal.analyzeAndSaveMealFromDraft] createdAt resolved to \(createdAt) (selectedDate was \(selectedDate))")

        GPTService.sharedInstance.analyzeMealNote(title: analysisTitle, description: analysisDescription) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAnalyzing = false

                switch result {
                case .success(let analysis):
                    let resolvedName: String
                    if !title.isEmpty {
                        resolvedName = title
                    } else if !analysis.name.isEmpty {
                        resolvedName = analysis.name
                    } else {
                        resolvedName = "Untitled meal"
                    }

                    let mappedIngredients = analysis.ingredients.map {
                        MacraFoodJournalMealIngredient(
                            name: $0.name,
                            quantity: $0.quantity,
                            calories: $0.calories,
                            protein: $0.protein,
                            carbs: $0.carbs,
                            fat: $0.fat,
                            fiber: $0.fiber,
                            sugarAlcohols: $0.sugarAlcohols
                        )
                    }

                    let meal = MacraFoodJournalMeal(
                        name: resolvedName,
                        caption: caption,
                        calories: analysis.calories,
                        protein: analysis.protein,
                        carbs: analysis.carbs,
                        fat: analysis.fat,
                        fiber: analysis.fiber,
                        sugarAlcohols: analysis.sugarAlcohols,
                        imageURL: imageURL,
                        entryMethod: entryMethod,
                        ingredients: mappedIngredients,
                        notes: notes,
                        createdAt: createdAt,
                        updatedAt: Date()
                    )

                    print("[Macra][Journal.analyzeAndSaveMealFromDraft] ✅ Saving analyzed meal id:\(meal.id) name:'\(meal.name)' \(meal.calories)kcal P:\(meal.protein) C:\(meal.carbs)(net \(meal.netCarbs)) F:\(meal.fat) fiber:\(meal.fiber ?? 0) sugarAlcohols:\(meal.sugarAlcohols ?? 0) ingredients:\(meal.ingredients.count)")
                    self.saveFoodJournalMeal(meal, on: saveDate, detailsDestination: .foodIdentifier(meal.id))

                    self.draftMealTitle = ""
                    self.draftMealCaption = ""
                    self.draftMealNotes = ""
                    self.draftMealImage = nil

                case .failure(let error):
                    print("[Macra][Journal.analyzeAndSaveMealFromDraft] ❌ Analysis failed: \(error.localizedDescription) — keeping draft so user can retry")
                    self.analysisError = error.localizedDescription
                }
            }
        }
    }

    func logMealFromHistory(_ meal: MacraFoodJournalMeal) {
        var copy = meal
        copy.id = UUID().uuidString
        copy.createdAt = resolvedLogTimestamp()
        copy.updatedAt = Date()
        copy.entryMethod = .history
        print("[Macra][Journal.logMealFromHistory] Re-logging '\(copy.name)' at \(copy.createdAt)")
        saveFoodJournalMeal(copy, on: selectedDate, detailsDestination: .mealDetails(copy.id))
    }

    func saveFoodJournalMeal(
        _ meal: MacraFoodJournalMeal,
        on date: Date,
        detailsDestination: MacraFoodJournalSheet?
    ) {
        store.addMeal(meal, on: date)
        onMealSaved?(meal)
        activeSheet = shouldReturnHomeAfterMealSave ? nil : detailsDestination
    }

    func loadMealHistory(force: Bool = false) {
        guard force || mealHistory.isEmpty else { return }
        guard !isLoadingHistory else { return }

        isLoadingHistory = true
        historyError = nil

        MealService.sharedInstance.getRecentMeals(userId: UserService.sharedInstance.user?.id, limit: 60) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingHistory = false

                switch result {
                case .success(let meals):
                    self.mealHistory = self.uniqueMeals(meals.map(MacraFoodJournalMeal.init(meal:)))
                case .failure(let error):
                    self.historyError = error.localizedDescription
                }
            }
        }
    }

    func loadLabelScanHistory(force: Bool = false) {
        guard force || labelScanHistory.isEmpty else { return }
        guard !isLoadingLabelHistory else { return }

        isLoadingLabelHistory = true
        labelHistoryError = nil

        let candidateUserIDs = labelScanHistoryUserIDs()
        guard !candidateUserIDs.isEmpty else {
            isLoadingLabelHistory = false
            labelHistoryError = NutritionCoreError.missingUserId.localizedDescription
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var scansByID: [String: MacraScannedLabel] = [:]
        var errors: [String] = []

        for userId in candidateUserIDs {
            group.enter()
            print("[Macra][LabelScanHistory] Fetching users/\(userId)/labelScans")
            Firestore.firestore()
                .collection(NutritionCoreConfiguration.usersCollection)
                .document(userId)
                .collection(NutritionCoreConfiguration.labelScansCollection)
                .getDocuments { snapshot, error in
                    lock.lock()
                    if let error {
                        errors.append(error.localizedDescription)
                    } else {
                        let documents = snapshot?.documents ?? []
                        print("[Macra][LabelScanHistory] Found \(documents.count) scans for user \(userId)")
                        for document in documents {
                            scansByID[document.documentID] = MacraScannedLabel(id: document.documentID, data: document.data())
                        }
                    }
                    lock.unlock()
                    group.leave()
                }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isLoadingLabelHistory = false
            self.labelScanHistory = self.uniqueLabelScans(Array(scansByID.values))
            self.labelHistoryError = self.labelScanHistory.isEmpty ? errors.first : nil
            print("[Macra][LabelScanHistory] Returning \(self.labelScanHistory.count) parsed scans")
        }
    }

    func gradeAndSaveLabelFromImage(_ image: UIImage) {
        guard !isAnalyzingLabel else { return }
        isAnalyzingLabel = true
        labelAnalysisError = nil

        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            isAnalyzingLabel = false
            labelAnalysisError = "Could not process that photo. Try again with better lighting."
            return
        }

        let scanId = UUID().uuidString
        let userId = Auth.auth().currentUser?.uid
        let base64 = jpeg.base64EncodedString()
        let prompt = Self.labelGradePrompt
        let content: [[String: Any]] = [
            ["type": "text", "text": prompt],
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
        ]

        MacraOpenAIBridge.postChat(
            messages: [
                ["role": "system", "content": "Return ONLY valid JSON matching the requested schema, no markdown fences or commentary."],
                ["role": "user", "content": content]
            ],
            model: "gpt-4o",
            maxTokens: 2000,
            temperature: 0.1,
            responseFormat: ["type": "json_object"],
            organization: "macraLabelScan"
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let raw):
                    let gradeDict = Self.parseLabelGradeJSON(raw)
                    let createdAt = Date()
                    let macraData: [String: Any] = [
                        "gradeResult": gradeDict,
                        "createdAt": createdAt,
                        "productTitle": (gradeDict["productTitle"] as? String ?? "") as Any,
                        "productTitleEdited": false
                    ]
                    let macraLabel = MacraScannedLabel(id: scanId, data: macraData)
                    self.labelScanHistory = self.uniqueLabelScans([macraLabel] + self.labelScanHistory)
                    self.isAnalyzingLabel = false
                    self.activeSheet = .labelDetail(scanId)
                    self.persistLabelScan(
                        scanId: scanId,
                        userId: userId,
                        gradeDict: gradeDict,
                        createdAt: createdAt,
                        imageData: jpeg
                    )
                case .failure(let error):
                    self.isAnalyzingLabel = false
                    self.labelAnalysisError = error.localizedDescription
                }
            }
        }
    }

    private func persistLabelScan(
        scanId: String,
        userId: String?,
        gradeDict: [String: Any],
        createdAt: Date,
        imageData: Data
    ) {
        guard let userId, !userId.isEmpty else {
            print("[Macra][LabelScan.persist] ❌ no signed-in user; skipping Firestore save")
            return
        }
        let storageRef = Storage.storage().reference().child("label-scans/\(userId)/\(scanId).jpg")
        storageRef.putData(imageData, metadata: nil) { _, uploadError in
            if let uploadError {
                print("[Macra][LabelScan.persist] ⚠️ image upload failed: \(uploadError.localizedDescription)")
                self.writeLabelScanDocument(scanId: scanId, userId: userId, gradeDict: gradeDict, createdAt: createdAt, imageURL: nil)
                return
            }
            storageRef.downloadURL { url, urlError in
                if let urlError {
                    print("[Macra][LabelScan.persist] ⚠️ downloadURL failed: \(urlError.localizedDescription)")
                }
                self.writeLabelScanDocument(scanId: scanId, userId: userId, gradeDict: gradeDict, createdAt: createdAt, imageURL: url?.absoluteString)
            }
        }
    }

    private func writeLabelScanDocument(
        scanId: String,
        userId: String,
        gradeDict: [String: Any],
        createdAt: Date,
        imageURL: String?
    ) {
        var data: [String: Any] = [
            "gradeResult": gradeDict,
            "grade": gradeDict["grade"] as? String ?? "?",
            "summary": gradeDict["summary"] as? String ?? "",
            "detailedExplanation": gradeDict["detailedExplanation"] as? String ?? "",
            "confidence": gradeDict["confidence"] as? Double ?? 0,
            "createdAt": Timestamp(date: createdAt),
            "userId": userId,
            "productTitleEdited": false
        ]
        if let productTitle = gradeDict["productTitle"] as? String, !productTitle.isEmpty {
            data["productTitle"] = productTitle
        }
        if let imageURL, !imageURL.isEmpty {
            data["imageURL"] = imageURL
        }

        Firestore.firestore()
            .collection(NutritionCoreConfiguration.usersCollection)
            .document(userId)
            .collection(NutritionCoreConfiguration.labelScansCollection)
            .document(scanId)
            .setData(data) { error in
                if let error {
                    print("[Macra][LabelScan.persist] ❌ Firestore write failed: \(error.localizedDescription)")
                } else {
                    print("[Macra][LabelScan.persist] ✅ saved scan \(scanId)")
                }
            }
    }

    private static func parseLabelGradeJSON(_ raw: String) -> [String: Any] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let start = trimmed.firstIndex(of: "{"),
            let end = trimmed.lastIndex(of: "}"),
            start <= end,
            let data = String(trimmed[start...end]).data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = object as? [String: Any]
        else {
            return [
                "grade": "?",
                "summary": "Analysis unavailable",
                "detailedExplanation": "Macra could not parse a response for this label. Try again.",
                "confidence": 0.0
            ]
        }
        return dict
    }

    private static let labelGradePrompt: String = """
    CRITICAL: Analyze the nutrition label image and return ONLY valid JSON — no markdown, no commentary.

    You are analyzing a nutrition facts label. Extract:
    - The EXACT product name as shown on the package
    - The nutrition facts panel (calories, macros, serving size)
    - The ingredients list
    - Any health claims or certifications

    GRADING CRITERIA:
    - Grade A: Whole-food ingredients, no artificial additives, low added sugars (<5% DV), low sodium (<5% DV)
    - Grade B: Mostly whole foods, minimal processing, low added sugars (<10% DV), moderate sodium (<10% DV)
    - Grade C: Mix of whole and processed ingredients, moderate added sugars (10-20% DV), some concerning additives
    - Grade D: Heavily processed, high added sugars (>20% DV), high sodium (>20% DV), multiple concerning additives
    - Grade F: Ultra-processed, excessive added sugars/sodium, harmful additives, trans fats

    FLAG: Artificial sweeteners, artificial colors, BHA, BHT, inflammatory oils, HFCS, MSG, sodium nitrite/nitrate.

    RETURN EXACTLY THIS JSON STRUCTURE:
    {
      "productTitle": "Exact product name as printed or null",
      "grade": "A" | "B" | "C" | "D" | "F",
      "confidence": 0.0_to_1.0,
      "calories": number_or_null,
      "protein": number_or_null,
      "fat": number_or_null,
      "carbs": number_or_null,
      "servingSize": "string or null",
      "sugars": number_or_null,
      "dietaryFiber": number_or_null,
      "sodium": number_or_null,
      "summary": "Brief 1-2 sentence summary",
      "detailedExplanation": "3-5 sentence explanation referencing specific ingredients and values",
      "flaggedIngredients": ["ingredient1 (reason)", "ingredient2 (reason)"],
      "concerns": [
        {
          "concern": "Health concern name",
          "scientificReason": "2-3 sentence evidence-based explanation",
          "severity": "low" | "medium" | "high",
          "relatedIngredients": ["ingredient1", "ingredient2"]
        }
      ],
      "sources": [
        {
          "name": "FDA" | "WHO" | "USDA" | "NIH" | "Other",
          "type": "Government" | "International" | "Academic" | "Medical",
          "title": "Guideline or study name",
          "url": "https://example.com or null",
          "relevance": "How this supports the analysis"
        }
      ]
    }
    """

    private func labelScanHistoryUserIDs() -> [String] {
        var seen = Set<String>()
        return [
            UserService.sharedInstance.user?.id,
            Auth.auth().currentUser?.uid
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
    }

    private func uniqueMeals(_ meals: [MacraFoodJournalMeal]) -> [MacraFoodJournalMeal] {
        var seen = Set<String>()
        return meals
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.createdAt > rhs.createdAt
            }
            .filter { meal in
                let inserted = seen.insert(meal.historyIdentityKey)
                return inserted.inserted
            }
    }

    private func uniqueLabelScans(_ scans: [MacraScannedLabel]) -> [MacraScannedLabel] {
        var seen = Set<String>()
        return scans
            .sorted { $0.createdAt > $1.createdAt }
            .filter { scan in
                let inserted = seen.insert(scan.id)
                return inserted.inserted
            }
    }

    func savePinnedMeal(_ meal: MacraFoodJournalMeal) {
        store.pinMeal(meal)
    }

    func unpinMeal(_ meal: MacraFoodJournalMeal) {
        store.unpinMeal(id: meal.id)
    }

    func togglePin(_ meal: MacraFoodJournalMeal) {
        meal.isPinned ? unpinMeal(meal) : savePinnedMeal(meal)
    }

    func updateMeal(_ meal: MacraFoodJournalMeal) {
        store.updateMeal(meal)
    }

    func deleteMeal(_ meal: MacraFoodJournalMeal) {
        store.deleteMeal(id: meal.id, on: meal.createdAt)
    }

    func quickLogPinnedMeals() {
        store.logAllPinnedMeals(on: selectedDate)
    }

    func saveLabelScan(_ scan: MacraScannedLabel) {
        store.saveLabelScan(scan)
    }

    func updateLabelScan(_ scan: MacraScannedLabel) {
        store.updateLabelScan(scan)
    }

    func deleteLabelScan(id: String) {
        store.deleteLabelScan(id: id)
    }

    func addInsight(title: String, response: String, query: String, icon: String = "sparkles") {
        store.addDailyInsight(
            MacraFoodJournalDailyInsight(title: title, response: response, query: query, icon: icon),
            for: selectedDate
        )
    }

    func openMealDetails(_ meal: MacraFoodJournalMeal) {
        activeSheet = .mealDetails(meal.id)
    }

    func meal(for id: String?) -> MacraFoodJournalMeal? {
        guard let id else { return nil }
        return store.meal(with: id) ?? allMealHistory.first { $0.id == id }
    }

    func labelScan(for id: String?) -> MacraScannedLabel? {
        guard let id else { return nil }
        return labelScans.first(where: { $0.id == id })
    }
}
