import Foundation
import FirebaseFirestore

struct LoggedSupplement: Identifiable, Hashable {
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
        self.dosage = nutritionDouble(from: dictionary["dosage"])
        self.unit = dictionary["unit"] as? String ?? "capsule(s)"
        self.brand = dictionary["brand"] as? String ?? ""
        self.notes = dictionary["notes"] as? String ?? ""
        self.calories = nutritionInt(from: dictionary["calories"])
        self.protein = nutritionInt(from: dictionary["protein"])
        self.carbs = nutritionInt(from: dictionary["carbs"])
        self.fat = nutritionInt(from: dictionary["fat"])
        self.vitamins = nutritionStringIntMap(from: dictionary["vitamins"])
        self.minerals = nutritionStringIntMap(from: dictionary["minerals"])
        self.imageUrl = dictionary["imageUrl"] as? String
        self.createdAt = nutritionDate(from: dictionary["createdAt"] ?? dictionary["timestamp"])
        self.updatedAt = nutritionDate(from: dictionary["updatedAt"] ?? dictionary["timestamp"])
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
        if let vitamins, !vitamins.isEmpty { dict["vitamins"] = vitamins }
        if let minerals, !minerals.isEmpty { dict["minerals"] = minerals }
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
        !(vitamins?.isEmpty ?? true) || !(minerals?.isEmpty ?? true)
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
                } else {
                    fat = 14
                    if calories == 0 { calories = 130 }
                }
            }
        }

        if !inferredVitamins.isEmpty { vitamins = inferredVitamins }
        if !inferredMinerals.isEmpty { minerals = inferredMinerals }
    }

    private static func extractAmountFromName(_ name: String) -> Int? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(mg|mcg|g|iu|iu\.)"#
        guard let match = name.lowercased().range(of: pattern, options: .regularExpression) else { return nil }
        let raw = String(name.lowercased()[match])
        let components = raw.split(whereSeparator: { $0 == " " })
        guard let valueString = components.first, let value = Double(valueString) else { return nil }
        return Int(value.rounded())
    }

    static var sampleVitaminD = LoggedSupplement(
        id: UUID().uuidString,
        name: "Vitamin D3 5000 IU",
        form: "softgel",
        dosage: 1,
        unit: "softgel(s)",
        brand: "Example",
        notes: "",
        calories: 0,
        protein: 0,
        carbs: 0,
        fat: 0,
        vitamins: ["Vitamin D": 125]
    )

    static var sampleProteinPowder = LoggedSupplement(
        id: UUID().uuidString,
        name: "Whey Protein",
        form: "powder",
        dosage: 1,
        unit: "scoop(s)",
        brand: "Example",
        notes: "",
        calories: 120,
        protein: 24,
        carbs: 3,
        fat: 1
    )
}

