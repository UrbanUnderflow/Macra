import Foundation

struct LabelConcern: Codable, Identifiable, Hashable {
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
        self.relatedIngredients = nutritionStringArray(from: dictionary["relatedIngredients"])
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

struct LabelSource: Codable, Identifiable, Hashable {
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

struct LabelNutritionFacts: Codable, Hashable {
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

struct LabelGradeResult: Codable, Hashable {
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
        self.flaggedIngredients = nutritionStringArray(from: dictionary["flaggedIngredients"])
        self.summary = dictionary["summary"] as? String ?? "Unable to analyze label"
        self.detailedExplanation = dictionary["detailedExplanation"] as? String ?? dictionary["summary"] as? String ?? "Unable to analyze label"
        self.confidence = dictionary["confidence"] as? Double ?? 0.0
        self.errorCode = dictionary["errorCode"] as? String
        self.errorDetails = dictionary["errorDetails"] as? String
        self.errorCategory = dictionary["errorCategory"] as? String

        let rawTitle = dictionary["productTitle"] as? String
        self.productTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rawTitle : nil

        self.calories = nutritionOptionalInt(from: dictionary["calories"])
        self.protein = nutritionOptionalInt(from: dictionary["protein"])
        self.fat = nutritionOptionalInt(from: dictionary["fat"])
        self.carbs = nutritionOptionalInt(from: dictionary["carbs"])
        self.servingSize = (dictionary["servingSize"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sugars = nutritionOptionalInt(from: dictionary["sugars"])
        self.dietaryFiber = nutritionOptionalInt(from: dictionary["dietaryFiber"])
        self.sugarAlcohols = nutritionOptionalInt(from: dictionary["sugarAlcohols"])
        self.sodium = nutritionOptionalInt(from: dictionary["sodium"])

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
        self.init(
            grade: grade,
            flaggedIngredients: flaggedIngredients,
            summary: summary,
            detailedExplanation: summary,
            confidence: confidence,
            concerns: [],
            sources: []
        )
    }

    var isError: Bool {
        errorCode != nil || grade == "?" || confidence == 0.0
    }

    var userFriendlyErrorMessage: String {
        if let errorCode {
            switch errorCode {
            case "LABEL-001":
                return "Unable to process image. The label may be too blurry or partially visible."
            case "LABEL-002":
                return "Failed to parse analysis response. The AI service returned unexpected data."
            case "LABEL-003":
                return "Network error. Please check your internet connection and try again."
            case "LABEL-004":
                return "API service error. The analysis service is temporarily unavailable."
            case "LABEL-005":
                return "Image format error. Please try taking a clearer photo of the label."
            case "LABEL-006":
                return "Label not detected. Please ensure the nutrition facts panel is clearly visible."
            default:
                return detailedExplanation.isEmpty ? summary : detailedExplanation
            }
        }
        return detailedExplanation.isEmpty ? summary : detailedExplanation
    }
}

