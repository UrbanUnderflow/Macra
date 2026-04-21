import Foundation

enum LabelQARole: String, Codable, Hashable {
    case user
    case assistant
}

struct LabelQAMessage: Identifiable, Codable, Hashable {
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

struct SuggestedQuestion: Identifiable, Hashable {
    let id: String
    let text: String
    let icon: String

    init(id: String = UUID().uuidString, text: String, icon: String = "questionmark.circle") {
        self.id = id
        self.text = text
        self.icon = icon
    }
}

struct HealthEffect: Identifiable, Codable, Hashable {
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
        self.relatedIngredients = nutritionStringArray(from: dictionary["relatedIngredients"])
    }
}

struct NutritionalBreakdown: Codable, Hashable {
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

struct ResearchFinding: Identifiable, Codable, Hashable {
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

struct RegulatoryInfo: Codable, Hashable {
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
        self.bannedIn = nutritionStringArray(from: dictionary["bannedIn"])
        self.warnings = nutritionStringArray(from: dictionary["warnings"])
    }
}

struct LabelDeepDiveResult: Codable, Hashable {
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

struct HealthierAlternative: Identifiable, Codable, Hashable {
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
        self.improvements = nutritionStringArray(from: dictionary["improvements"])
        self.whereToFind = dictionary["whereToFind"] as? String
        self.category = dictionary["category"] as? String
        self.productUrl = dictionary["productUrl"] as? String
    }
}

enum LabelDetailSection: String, CaseIterable, Hashable {
    case askQuestion = "Ask a Question"
    case deepDive = "Deep Dive Research"
    case alternatives = "Healthier Alternatives"
}

