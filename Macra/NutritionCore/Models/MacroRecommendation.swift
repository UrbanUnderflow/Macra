import Foundation

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
        id: String = UUID().uuidString,
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
        self.id = dictionary["id"] as? String ?? UUID().uuidString
        self.userId = dictionary["userId"] as? String ?? ""
        self.calories = nutritionInt(from: dictionary["calories"])
        self.protein = nutritionInt(from: dictionary["protein"])
        self.carbs = nutritionInt(from: dictionary["carbs"])
        self.fat = nutritionInt(from: dictionary["fat"])
        self.dayOfWeek = dictionary["dayOfWeek"] as? String
        self.createdAt = nutritionDate(from: dictionary["createdAt"])
        self.updatedAt = nutritionDate(from: dictionary["updatedAt"])
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
        if let dayOfWeek { dict["dayOfWeek"] = dayOfWeek }
        return dict
    }

    func toMacroRecommendations() -> MacroRecommendations {
        MacroRecommendations(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    static func from(macroRecommendations: MacroRecommendations, userId: String) -> MacroRecommendation {
        MacroRecommendation(
            userId: userId,
            calories: macroRecommendations.calories,
            protein: macroRecommendations.protein,
            carbs: macroRecommendations.carbs,
            fat: macroRecommendations.fat
        )
    }
}

