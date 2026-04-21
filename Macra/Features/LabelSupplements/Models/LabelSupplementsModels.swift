import Foundation
import UIKit

// MARK: - Label Concern / Source / Nutrition Facts

struct LabelConcern: Codable, Identifiable {
    var id: String { concern }
    let concern: String
    let scientificReason: String
    let severity: String
    let relatedIngredients: [String]

    init(concern: String, scientificReason: String, severity: String, relatedIngredients: [String]) {
        self.concern = concern
        self.scientificReason = scientificReason
        self.severity = severity
        self.relatedIngredients = relatedIngredients
    }

    init(from dictionary: [String: Any]) {
        self.concern = dictionary["concern"] as? String ?? ""
        self.scientificReason = dictionary["scientificReason"] as? String ?? ""
        self.severity = dictionary["severity"] as? String ?? "medium"
        self.relatedIngredients = dictionary["relatedIngredients"] as? [String] ?? []
    }

    var severityLevel: SeverityLevel {
        switch severity.lowercased() {
        case "low": return .low
        case "medium": return .medium
        case "high": return .high
        default: return .medium
        }
    }

    enum SeverityLevel {
        case low, medium, high

        var displayName: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }
    }
}

struct LabelSource: Codable, Identifiable {
    var id: String { name + title }
    let name: String
    let type: String
    let title: String
    let url: String?
    let relevance: String

    init(name: String, type: String, title: String, url: String?, relevance: String) {
        self.name = name
        self.type = type
        self.title = title
        self.url = url
        self.relevance = relevance
    }

    init(from dictionary: [String: Any]) {
        self.name = dictionary["name"] as? String ?? ""
        self.type = dictionary["type"] as? String ?? "Government"
        self.title = dictionary["title"] as? String ?? ""
        self.url = dictionary["url"] as? String
        self.relevance = dictionary["relevance"] as? String ?? ""
    }

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

struct LabelNutritionFacts {
    let calories: Int?
    let protein: Int?
    let fat: Int?
    let carbs: Int?
    let servingSize: String?
    let sugars: Int?
    let dietaryFiber: Int?
    let sugarAlcohols: Int?
    let sodium: Int?

    var hasAnyMacro: Bool {
        (calories ?? 0) > 0 || (protein ?? 0) > 0 || (fat ?? 0) > 0 || (carbs ?? 0) > 0
    }
}

struct LabelGradeResult: Codable {
    let grade: String
    let flaggedIngredients: [String]
    let summary: String
    let detailedExplanation: String
    let confidence: Double
    let concerns: [LabelConcern]
    let sources: [LabelSource]
    let productTitle: String?
    let errorCode: String?
    let errorDetails: String?
    let errorCategory: String?
    let calories: Int?
    let protein: Int?
    let fat: Int?
    let carbs: Int?
    let servingSize: String?
    let sugars: Int?
    let dietaryFiber: Int?
    let sugarAlcohols: Int?
    let sodium: Int?

    var hasStoredMacros: Bool {
        calories != nil || protein != nil || fat != nil || carbs != nil
    }

    init(from dictionary: [String: Any]) {
        self.grade = dictionary["grade"] as? String ?? "F"
        self.flaggedIngredients = dictionary["flaggedIngredients"] as? [String] ?? []
        self.summary = dictionary["summary"] as? String ?? "Unable to analyze label"
        self.detailedExplanation = dictionary["detailedExplanation"] as? String ?? dictionary["summary"] as? String ?? "Unable to analyze label"
        self.confidence = dictionary["confidence"] as? Double ?? 0.0
        self.errorCode = dictionary["errorCode"] as? String
        self.errorDetails = dictionary["errorDetails"] as? String
        self.errorCategory = dictionary["errorCategory"] as? String
        let rawTitle = dictionary["productTitle"] as? String
        self.productTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rawTitle : nil
        self.calories = dictionary["calories"] as? Int
        self.protein = dictionary["protein"] as? Int
        self.fat = dictionary["fat"] as? Int
        self.carbs = dictionary["carbs"] as? Int
        let rawServing = dictionary["servingSize"] as? String
        self.servingSize = rawServing?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rawServing : nil
        self.sugars = dictionary["sugars"] as? Int
        self.dietaryFiber = dictionary["dietaryFiber"] as? Int
        self.sugarAlcohols = dictionary["sugarAlcohols"] as? Int
        self.sodium = dictionary["sodium"] as? Int
        if let concernsArray = dictionary["concerns"] as? [[String: Any]] {
            self.concerns = concernsArray.map { LabelConcern(from: $0) }
        } else {
            self.concerns = []
        }
        if let sourcesArray = dictionary["sources"] as? [[String: Any]] {
            self.sources = sourcesArray.map { LabelSource(from: $0) }
        } else {
            self.sources = []
        }
    }

    init(
        grade: String,
        flaggedIngredients: [String],
        summary: String,
        detailedExplanation: String,
        confidence: Double,
        concerns: [LabelConcern],
        sources: [LabelSource],
        productTitle: String? = nil,
        errorCode: String? = nil,
        errorDetails: String? = nil,
        errorCategory: String? = nil,
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
        self.grade = grade
        self.flaggedIngredients = flaggedIngredients
        self.summary = summary
        self.detailedExplanation = detailedExplanation
        self.confidence = confidence
        self.concerns = concerns
        self.sources = sources
        self.productTitle = productTitle
        self.errorCode = errorCode
        self.errorDetails = errorDetails
        self.errorCategory = errorCategory
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

    init(grade: String, flaggedIngredients: [String], summary: String, confidence: Double) {
        self.grade = grade
        self.flaggedIngredients = flaggedIngredients
        self.summary = summary
        self.detailedExplanation = summary
        self.confidence = confidence
        self.concerns = []
        self.sources = []
        self.productTitle = nil
        self.errorCode = nil
        self.errorDetails = nil
        self.errorCategory = nil
        self.calories = nil
        self.protein = nil
        self.fat = nil
        self.carbs = nil
        self.servingSize = nil
        self.sugars = nil
        self.dietaryFiber = nil
        self.sugarAlcohols = nil
        self.sodium = nil
    }

    var isError: Bool {
        errorCode != nil || grade == "?" || confidence == 0.0
    }

    var userFriendlyErrorMessage: String {
        if let errorCode = errorCode {
            switch errorCode {
            case "LABEL-001":
                return "Unable to process image. The label may be too blurry or partially visible."
            case "LABEL-002":
                return "Failed to parse analysis response. The AI service returned unexpected data."
            case "LABEL-003":
                return "Network error. Please check your internet connection and try again."
            case "LABEL-004":
                return "Analysis service error. Please try again in a moment."
            case "LABEL-005":
                return "Unable to process image format. Please try another photo."
            default:
                return errorDetails ?? "Unknown error"
            }
        }
        return "Unable to analyze label"
    }
}

// MARK: - Deep Dive Models

enum LabelQARole: String, Codable {
    case user
    case assistant
}

struct LabelQAMessage: Identifiable, Codable {
    let id: String
    let role: LabelQARole
    let content: String
    let timestamp: Date

    init(id: String = UUID().uuidString, role: LabelQARole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

struct SuggestedQuestion: Identifiable {
    let id: String
    let text: String
    let icon: String

    init(id: String = UUID().uuidString, text: String, icon: String = "questionmark.circle") {
        self.id = id
        self.text = text
        self.icon = icon
    }
}

struct HealthEffect: Identifiable, Codable {
    let id: String
    let effect: String
    let description: String
    let severity: String
    let timeframe: String
    let relatedIngredients: [String]

    init(id: String = UUID().uuidString, effect: String, description: String, severity: String, timeframe: String, relatedIngredients: [String]) {
        self.id = id
        self.effect = effect
        self.description = description
        self.severity = severity
        self.timeframe = timeframe
        self.relatedIngredients = relatedIngredients
    }

    init(from dictionary: [String: Any]) {
        self.id = dictionary["id"] as? String ?? UUID().uuidString
        self.effect = dictionary["effect"] as? String ?? ""
        self.description = dictionary["description"] as? String ?? ""
        self.severity = dictionary["severity"] as? String ?? "low"
        self.timeframe = dictionary["timeframe"] as? String ?? "unknown"
        self.relatedIngredients = dictionary["relatedIngredients"] as? [String] ?? []
    }
}

struct NutritionalBreakdown: Codable {
    let macroAnalysis: String
    let micronutrientNotes: String
    let calorieContext: String
    let portionGuidance: String

    init(macroAnalysis: String, micronutrientNotes: String, calorieContext: String, portionGuidance: String) {
        self.macroAnalysis = macroAnalysis
        self.micronutrientNotes = micronutrientNotes
        self.calorieContext = calorieContext
        self.portionGuidance = portionGuidance
    }

    init(from dictionary: [String: Any]) {
        self.macroAnalysis = dictionary["macroAnalysis"] as? String ?? ""
        self.micronutrientNotes = dictionary["micronutrientNotes"] as? String ?? ""
        self.calorieContext = dictionary["calorieContext"] as? String ?? ""
        self.portionGuidance = dictionary["portionGuidance"] as? String ?? ""
    }
}

struct ResearchFinding: Identifiable, Codable {
    let id: String
    let title: String
    let summary: String
    let source: String
    let year: String?
    let relevance: String

    init(id: String = UUID().uuidString, title: String, summary: String, source: String, year: String?, relevance: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.source = source
        self.year = year
        self.relevance = relevance
    }

    init(from dictionary: [String: Any]) {
        self.id = dictionary["id"] as? String ?? UUID().uuidString
        self.title = dictionary["title"] as? String ?? ""
        self.summary = dictionary["summary"] as? String ?? ""
        self.source = dictionary["source"] as? String ?? ""
        self.year = dictionary["year"] as? String
        self.relevance = dictionary["relevance"] as? String ?? ""
    }
}

struct RegulatoryInfo: Codable {
    let fdaStatus: String
    let whoGuidance: String
    let bannedIn: [String]
    let warnings: [String]

    init(fdaStatus: String, whoGuidance: String, bannedIn: [String], warnings: [String]) {
        self.fdaStatus = fdaStatus
        self.whoGuidance = whoGuidance
        self.bannedIn = bannedIn
        self.warnings = warnings
    }

    init(from dictionary: [String: Any]) {
        self.fdaStatus = dictionary["fdaStatus"] as? String ?? "No specific FDA guidance"
        self.whoGuidance = dictionary["whoGuidance"] as? String ?? "No specific WHO guidance"
        self.bannedIn = dictionary["bannedIn"] as? [String] ?? []
        self.warnings = dictionary["warnings"] as? [String] ?? []
    }
}

struct LabelDeepDiveResult: Codable {
    let longTermEffects: [HealthEffect]
    let nutritionalBreakdown: NutritionalBreakdown
    let researchFindings: [ResearchFinding]
    let regulatoryStatus: RegulatoryInfo
    let productTitle: String?

    init(longTermEffects: [HealthEffect], nutritionalBreakdown: NutritionalBreakdown, researchFindings: [ResearchFinding], regulatoryStatus: RegulatoryInfo, productTitle: String? = nil) {
        self.longTermEffects = longTermEffects
        self.nutritionalBreakdown = nutritionalBreakdown
        self.researchFindings = researchFindings
        self.regulatoryStatus = regulatoryStatus
        self.productTitle = productTitle
    }

    init(from dictionary: [String: Any]) {
        if let effectsArray = dictionary["longTermEffects"] as? [[String: Any]] {
            self.longTermEffects = effectsArray.map { HealthEffect(from: $0) }
        } else {
            self.longTermEffects = []
        }
        if let breakdownDict = dictionary["nutritionalBreakdown"] as? [String: Any] {
            self.nutritionalBreakdown = NutritionalBreakdown(from: breakdownDict)
        } else {
            self.nutritionalBreakdown = NutritionalBreakdown(macroAnalysis: "", micronutrientNotes: "", calorieContext: "", portionGuidance: "")
        }
        if let findingsArray = dictionary["researchFindings"] as? [[String: Any]] {
            self.researchFindings = findingsArray.map { ResearchFinding(from: $0) }
        } else {
            self.researchFindings = []
        }
        if let regulatoryDict = dictionary["regulatoryStatus"] as? [String: Any] {
            self.regulatoryStatus = RegulatoryInfo(from: regulatoryDict)
        } else {
            self.regulatoryStatus = RegulatoryInfo(fdaStatus: "", whoGuidance: "", bannedIn: [], warnings: [])
        }
        let rawTitle = dictionary["productTitle"] as? String
        self.productTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rawTitle : nil
    }
}

struct HealthierAlternative: Identifiable, Codable {
    let id: String
    let name: String
    let reason: String
    let grade: String
    let improvements: [String]
    let whereToFind: String?
    let category: String?
    let productUrl: String?

    init(id: String = UUID().uuidString, name: String, reason: String, grade: String, improvements: [String], whereToFind: String?, category: String? = nil, productUrl: String? = nil) {
        self.id = id
        self.name = name
        self.reason = reason
        self.grade = grade
        self.improvements = improvements
        self.whereToFind = whereToFind
        self.category = category
        self.productUrl = productUrl
    }

    init(from dictionary: [String: Any]) {
        self.id = dictionary["id"] as? String ?? UUID().uuidString
        self.name = dictionary["name"] as? String ?? ""
        self.reason = dictionary["reason"] as? String ?? ""
        self.grade = dictionary["grade"] as? String ?? "A"
        self.improvements = dictionary["improvements"] as? [String] ?? []
        self.whereToFind = dictionary["whereToFind"] as? String
        self.category = dictionary["category"] as? String
        self.productUrl = dictionary["productUrl"] as? String
    }
}

enum LabelDetailSection: String, CaseIterable {
    case askQuestion = "Ask a Question"
    case deepDive = "Deep Dive Research"
    case alternatives = "Healthier Alternatives"
}

// MARK: - Scanned Label

struct ScannedLabel: Identifiable, Hashable {
    let id: String
    let gradeResult: LabelGradeResult
    let imageData: Data?
    let imageURL: String?
    let createdAt: Date
    let userId: String?
    var productTitle: String?
    var productTitleEdited: Bool
    var qaHistory: [LabelQAMessage]
    var deepDiveResult: LabelDeepDiveResult?
    var deepDiveTimestamp: Date?
    var alternatives: [HealthierAlternative]?
    var alternativesTimestamp: Date?

    init(
        id: String,
        gradeResult: LabelGradeResult,
        imageData: Data? = nil,
        imageURL: String? = nil,
        createdAt: Date = Date(),
        userId: String? = nil,
        productTitle: String? = nil,
        productTitleEdited: Bool = false,
        qaHistory: [LabelQAMessage] = [],
        deepDiveResult: LabelDeepDiveResult? = nil,
        deepDiveTimestamp: Date? = nil,
        alternatives: [HealthierAlternative]? = nil,
        alternativesTimestamp: Date? = nil
    ) {
        self.id = id
        self.gradeResult = gradeResult
        self.imageData = imageData
        self.imageURL = imageURL
        self.createdAt = createdAt
        self.userId = userId
        self.productTitle = productTitle ?? gradeResult.productTitle
        self.productTitleEdited = productTitleEdited
        self.qaHistory = qaHistory
        self.deepDiveResult = deepDiveResult
        self.deepDiveTimestamp = deepDiveTimestamp
        self.alternatives = alternatives
        self.alternativesTimestamp = alternativesTimestamp
    }

    var thumbnailImage: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    var hasInteractionHistory: Bool {
        !qaHistory.isEmpty || deepDiveResult != nil || alternatives != nil
    }

    static func == (lhs: ScannedLabel, rhs: ScannedLabel) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Logged Supplement

struct LoggedSupplement: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var form: String
    var dosage: Double
    var unit: String
    var brand: String
    var notes: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var vitamins: [String: Int]?
    var minerals: [String: Int]?
    var imageUrl: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        form: String = "capsule",
        dosage: Double = 1,
        unit: String = "capsule(s)",
        brand: String = "",
        notes: String = "",
        calories: Int = 0,
        protein: Int = 0,
        carbs: Int = 0,
        fat: Int = 0,
        vitamins: [String: Int]? = nil,
        minerals: [String: Int]? = nil,
        imageUrl: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.form = form
        self.dosage = dosage
        self.unit = unit
        self.brand = brand
        self.notes = notes
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.vitamins = vitamins
        self.minerals = minerals
        self.imageUrl = imageUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(id: String, dictionary: [String: Any]) {
        self.id = id
        self.name = dictionary["name"] as? String ?? ""
        self.form = dictionary["form"] as? String ?? "capsule"
        self.dosage = dictionary["dosage"] as? Double ?? 1
        self.unit = dictionary["unit"] as? String ?? "capsule(s)"
        self.brand = dictionary["brand"] as? String ?? ""
        self.notes = dictionary["notes"] as? String ?? ""
        self.calories = dictionary["calories"] as? Int ?? 0
        self.protein = dictionary["protein"] as? Int ?? 0
        self.carbs = dictionary["carbs"] as? Int ?? 0
        self.fat = dictionary["fat"] as? Int ?? 0
        self.vitamins = dictionary["vitamins"] as? [String: Int]
        self.minerals = dictionary["minerals"] as? [String: Int]
        self.imageUrl = dictionary["imageUrl"] as? String
        self.createdAt = Date(timeIntervalSince1970: dictionary["createdAt"] as? Double ?? 0)
        self.updatedAt = Date(timeIntervalSince1970: dictionary["updatedAt"] as? Double ?? 0)
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "form": form,
            "dosage": dosage,
            "unit": unit,
            "brand": brand,
            "notes": notes,
            "calories": calories,
            "protein": protein,
            "carbs": carbs,
            "fat": fat,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970,
            "timestamp": Timestamp(date: createdAt)
        ]
        if let vitamins { dict["vitamins"] = vitamins }
        if let minerals { dict["minerals"] = minerals }
        if let imageUrl { dict["imageUrl"] = imageUrl }
        return dict
    }

    var dosageDescription: String {
        let cleaned = dosage == dosage.rounded() ? String(Int(dosage)) : String(dosage)
        return "\(cleaned) \(unit)"
    }

    var formIcon: String {
        switch form.lowercased() {
        case "capsule": return "capsule.fill"
        case "tablet": return "pill.fill"
        case "powder": return "spoon"
        case "softgel": return "oval.fill"
        case "liquid": return "drop.fill"
        default: return "cross.case.fill"
        }
    }

    var hasMacroContribution: Bool {
        calories > 0 || protein > 0 || carbs > 0 || fat > 0
    }

    var hasMicronutrientData: Bool {
        (vitamins != nil && !(vitamins?.isEmpty ?? true)) || (minerals != nil && !(minerals?.isEmpty ?? true))
    }

    mutating func inferMicronutrients() {
        guard !hasMicronutrientData else { return }

        let lowercaseName = name.lowercased()
        let extractedAmount = Self.extractAmountFromName(name)

        let vitaminPatterns: [(pattern: String, key: String, defaultAmount: Int)] = [
            ("vitamin a", "Vitamin A", 900),
            ("vitamin b1", "Vitamin B1", 1),
            ("thiamine", "Vitamin B1", 1),
            ("vitamin b2", "Vitamin B2", 1),
            ("riboflavin", "Vitamin B2", 1),
            ("vitamin b3", "Vitamin B3", 16),
            ("niacin", "Vitamin B3", 16),
            ("vitamin b5", "Vitamin B5", 5),
            ("pantothenic", "Vitamin B5", 5),
            ("vitamin b6", "Vitamin B6", 2),
            ("pyridoxine", "Vitamin B6", 2),
            ("vitamin b7", "Vitamin B7", 30),
            ("biotin", "Vitamin B7", 30),
            ("vitamin b9", "Vitamin B9", 400),
            ("folate", "Vitamin B9", 400),
            ("folic acid", "Vitamin B9", 400),
            ("vitamin b12", "Vitamin B12", 2),
            ("cobalamin", "Vitamin B12", 2),
            ("vitamin c", "Vitamin C", 1000),
            ("ascorbic", "Vitamin C", 1000),
            ("vitamin d3", "Vitamin D", 125),
            ("vitamin d₃", "Vitamin D", 125),
            ("vitamin d", "Vitamin D", 50),
            ("vitamin e", "Vitamin E", 15),
            ("vitamin k2", "Vitamin K", 100),
            ("vitamin k", "Vitamin K", 90)
        ]

        var inferredVitamins: [String: Int] = [:]
        for pattern in vitaminPatterns where lowercaseName.contains(pattern.pattern) {
            inferredVitamins[pattern.key] = extractedAmount ?? pattern.defaultAmount
            break
        }

        let mineralPatterns: [(pattern: String, key: String, defaultAmount: Int)] = [
            ("magnesium", "Magnesium", 250),
            ("calcium", "Calcium", 500),
            ("zinc", "Zinc", 30),
            ("iron", "Iron", 18),
            ("potassium", "Potassium", 99),
            ("selenium", "Selenium", 200),
            ("chromium", "Chromium", 200),
            ("copper", "Copper", 2),
            ("manganese", "Manganese", 2),
            ("phosphorus", "Phosphorus", 700),
            ("iodine", "Iodine", 150)
        ]

        var inferredMinerals: [String: Int] = [:]
        for pattern in mineralPatterns where lowercaseName.contains(pattern.pattern) {
            inferredMinerals[pattern.key] = extractedAmount ?? pattern.defaultAmount
            break
        }

        if lowercaseName.contains("zma") {
            inferredMinerals["Zinc"] = 30
            inferredMinerals["Magnesium"] = 450
            inferredVitamins["Vitamin B6"] = 11
        }

        if lowercaseName.contains("multivitamin") {
            inferredVitamins["Vitamin A"] = 900
            inferredVitamins["Vitamin C"] = 90
            inferredVitamins["Vitamin D"] = 50
            inferredVitamins["Vitamin E"] = 15
            inferredVitamins["Vitamin K"] = 80
            inferredVitamins["Vitamin B6"] = 2
            inferredVitamins["Vitamin B12"] = 6
            inferredMinerals["Zinc"] = 11
            inferredMinerals["Selenium"] = 55
            inferredMinerals["Chromium"] = 35
        }

        if lowercaseName.contains("omega") || lowercaseName.contains("fish oil") {
            if fat == 0 {
                if let mg = extractedAmount, mg >= 100 {
                    let grams = max(1, Int(round(Double(mg) / 1000.0)))
                    fat = grams
                    if calories == 0 { calories = grams * 9 }
                } else {
                    fat = 1
                    if calories == 0 { calories = 9 }
                }
            }
        }

        if lowercaseName.contains("mct") {
            if fat == 0 {
                if let mg = extractedAmount, mg >= 100 {
                    let grams = max(1, Int(round(Double(mg) / 1000.0)))
                    fat = grams
                    if calories == 0 { calories = grams * 9 }
                }
            }
        }

        if !inferredVitamins.isEmpty { vitamins = inferredVitamins }
        if !inferredMinerals.isEmpty { minerals = inferredMinerals }
    }

    private static func extractAmountFromName(_ name: String) -> Int? {
        let pattern = #"(\d+(\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: name.utf16.count)
        guard let match = regex.firstMatch(in: name, options: [], range: range) else { return nil }
        let result = (name as NSString).substring(with: match.range(at: 1))
        if let doubleValue = Double(result) {
            return Int(doubleValue.rounded())
        }
        return nil
    }
}

