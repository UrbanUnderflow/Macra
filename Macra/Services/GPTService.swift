import FirebaseAuth
import Foundation
import UIKit

class GPTService {
    static let sharedInstance = GPTService()
    static let testing = true

    /// Default model identifier passed to the server-side OpenAI bridge. Kept
    /// in sync with the `generate-macra-meal-plan` / `nora-nutrition-chat`
    /// Netlify functions so all analyzer traffic uses the same cheap, fast
    /// model unless a specific call overrides it.
    private let bridgeModel: String = "gpt-4o-mini"

    private init() {}

    private static let mealAnalyzerSystemPrompt = "You are Macra's precise nutrition analyzer. You return ONLY valid JSON matching the requested schema, no prose, no markdown fences."

    private static let mealAnalyzerAccuracyRules = """
    - Split every meal into individual food items. Never put "egg whites + rice cake + almond butter" into one item; create one ingredient/item per food with its own quantity and macros.
    - Use quantity-based nutrition math for each ingredient before summing the meal. Use standard USDA-style values when no brand label is provided.
    - If portion sizes are not specified, use realistic defaults and reflect that assumption in the `quantity` field.
    - For prep-style plans, assume meat/fish ounces are cooked edible weight, rice/potato grams are cooked weight unless explicitly raw/dry, cream of rice grams/scoops are dry, egg whites are liquid volume, and "1 scoop" protein powder is one standard scoop unless a brand label is shown.
    - Use these reference anchors when the source does not provide a label: 1 cup liquid egg whites = 126 kcal/26P/2C/0F; 1 large whole egg = 70 kcal/6P/0C/5F; 35g or 1 scoop cream of rice = 130 kcal/2P/28C/0F; 1 plain rice cake = 35 kcal/1P/7C/0F; 1 tbsp almond butter = 98 kcal/3P/3C/9F; cooked chicken breast 1 oz = 47 kcal/9P/0C/1F; cooked white fish 1 oz = 32 kcal/7P/0C/0F; cooked jasmine/white rice 100g = 130 kcal/3P/28C/0F; cooked white potato 100g = 87 kcal/2P/20C/0F.
    - Do not include vitamin/mineral supplement-only lines as meals. Count calorie-containing oils only when they materially affect daily fats.
    - For each ingredient/item and meal, calories should be consistent with protein/carbs/fat using 4/4/9 math within normal rounding.
    """

    func analyzeFood(_ foodEntry: String, completion: @escaping (Result<FoodJournalFeedback, Error>) -> Void) {
        let fetchedPrompt = "Imagine you are a certified nutritionist and personal trainer. Analyze a given food journal entry, estimating the overall caloric intake and macronutrient breakdown. Identify any potentially unhealthy or harmful food items and offer healthier alternatives. Consider the user's stated goal and provide personalized feedback based on that goal. Lastly, if there are any unhealthy or harmful ingredients, suggest healthier alternatives.  To provide more consistent results, the macronutrient analysis will use standard macronutrient values for common food categories. Since precise portion sizes are not specified, the macronutrient values will be given as a range within 20 grams to give the user a better understanding of the ballpark figures.   Structure your response in the following format:  - Total Calories: [calorie range] - Carbohydrates: [carb range] grams - Protein: [protein range] grams - Fat: [fat range] grams - Food Evaluation: [Comment on the healthiness of each food item, noting any potential issues] - Personalized Feedback: [Provide insights and recommendations based on the user's goal] - Unhealthy/Harmful Ingredients: [Identify any unhealthy or potentially harmful ingredients, if any, and suggest healthier alternatives] - Sentiment Score: [Provide a sentiment score (0-100)] - Sentiment: [Provide an overall sentiment analysis (positive, neutral, or negative)]  With this prompt, you can expect a response that includes the requested structure for analyzing the food journal entry, evaluating the healthiness of the food items, providing personalized feedback based on the user's goal, identifying and suggesting alternatives for any unhealthy or harmful ingredients, and the macronutrient analysis with narrower ranges for the values.   With this in mind, analyze the following journal entry: \"\(foodEntry)\""
        let prompt = fetchedPrompt.replacingOccurrences(of: "foodEntry", with: foodEntry)

        print("[Macra][GPTService.analyzeFood] ▶️ routing through bridge — entryLen:\(foodEntry.count)")

        MacraOpenAIBridge.postChat(
            messages: [
                ["role": "system", "content": "You are a helpful nutrition coach. Follow the user's requested output format exactly."],
                ["role": "user", "content": prompt]
            ],
            model: bridgeModel,
            maxTokens: 1500,
            temperature: 0.2,
            responseFormat: nil,
            organization: "macraFoodJournalFeedback"
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let content):
                let analysis = self.parseDietAnalysisResponse(content)
                let feedback = FoodJournalFeedback(id: UUID().uuidString,
                                                   calories: analysis.calories,
                                                   carbs: analysis.carbs,
                                                   protein: analysis.protein,
                                                   fat: analysis.fat,
                                                   foodEvaluation: analysis.foodEvaluation,
                                                   personalizedFeedback: analysis.personalizedFeedback,
                                                   unhealthyItems: analysis.unhealthyItems,
                                                   score: analysis.score,
                                                   sentiment: analysis.sentiment,
                                                   journalEntry: foodEntry)
                print("[Macra][GPTService.analyzeFood] ✅ parsed feedback — calories:'\(analysis.calories)' sentiment:'\(analysis.sentiment)'")
                completion(.success(feedback))

            case .failure(let error):
                print("[Macra][GPTService.analyzeFood] ❌ bridge error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    func parseDietAnalysisResponse(_ response: String) -> (calories: String, carbs: String, protein: String, fat: String, foodEvaluation: String, personalizedFeedback: String, unhealthyItems: String, score: Int, sentiment: String) {
        // Split the response by newline characters
        let components = response.split(separator: "\n")

        // Ensure there are enough components
        guard components.count >= 9 else {
            return (calories: "", carbs: "", protein: "", fat: "", foodEvaluation: "", personalizedFeedback: "", unhealthyItems: "", score: 0, sentiment: "")
        }

        // Parse each component
        let calories = parseComponentValue(components[0])
        let carbs = parseComponentValue(components[1])
        let protein = parseComponentValue(components[2])
        let fat = parseComponentValue(components[3])
        let foodEvaluation = parseComponentValue(components[4])
        let personalizedFeedback = parseComponentValue(components[5])
        let unhealthyItems = parseComponentValue(components[6])

        // Parse sentiment
        let scoreString = parseComponentValue(components[7])

        // Parse score
        let sentiment = parseComponentValue(components[8])
        let score = Int(scoreString) ?? 0

        return (calories: calories, carbs: carbs, protein: protein, fat: fat, foodEvaluation: foodEvaluation, personalizedFeedback: personalizedFeedback, unhealthyItems: unhealthyItems, score: score, sentiment: sentiment)
    }

    func parseComponentValue(_ component: Substring) -> String {
        let parts = component.split(separator: ":")
        guard parts.count >= 2 else {
            return ""
        }

        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return String(value)
    }

    // MARK: - Structured meal analysis (journal note / voice entry)

    struct MealAnalysisIngredient {
        let name: String
        let quantity: String
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let fiber: Int?
        let sugarAlcohols: Int?
    }

    struct MealAnalysis {
        let name: String
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let fiber: Int?
        let sugarAlcohols: Int?
        let ingredients: [MealAnalysisIngredient]
    }

    enum MealAnalysisError: LocalizedError {
        case parsingFailed(String)
        case zeroMacros

        var errorDescription: String? {
            switch self {
            case .parsingFailed(let detail): return "Couldn't parse the analyzer response: \(detail)"
            case .zeroMacros: return "The analyzer couldn't estimate macros for that. Try adding portion sizes (e.g. '1 cup', '3 oz') or more detail."
            }
        }
    }

    /// Turns a journal-note style description into structured macros +
    /// ingredient breakdown. Routes through `MacraOpenAIBridge` so the real
    /// OpenAI key stays on the server and the client only sends a Firebase ID
    /// token.
    func analyzeMealNote(title: String, description: String, completion: @escaping (Result<MealAnalysis, Error>) -> Void) {
        print("[Macra][GPTService.analyzeMealNote] Starting — title:'\(title)' descLen:\(description.count)")

        let systemPrompt = Self.mealAnalyzerSystemPrompt
        let userPrompt = """
        Analyze the meal below and return JSON with this exact shape:

        {
          "name": "short descriptive meal name",
          "calories": integer_total_kcal,
          "protein": integer_grams,
          "carbs": integer_grams,
          "fat": integer_grams,
          "fiber": integer_grams_or_null,
          "sugarAlcohols": integer_grams_or_null,
          "ingredients": [
            {
              "name": "ingredient name",
              "quantity": "amount with unit, e.g. '1 cup', '3 oz', '1 slice'",
              "calories": integer_kcal,
              "protein": integer_grams,
              "carbs": integer_grams,
              "fat": integer_grams,
              "fiber": integer_grams_or_null,
              "sugarAlcohols": integer_grams_or_null
            }
          ]
        }

        Shared Macra nutrition accuracy rules:
        \(Self.mealAnalyzerAccuracyRules)

        Journal-specific rules:
        - All macro fields are integers (round if needed).
        - Meal totals must equal the sum of ingredient macros within ±5%.
        - If the input is ambiguous, estimate with standard USDA-style values instead of returning zeros.
        - Populate `fiber` whenever a food realistically contains dietary fiber (fruits, vegetables, legumes, whole grains, nuts, seeds).
        - Populate `sugarAlcohols` for any food/ingredient containing sugar alcohols — common in sugar-free products, keto/low-carb baked goods, protein bars, and items sweetened with erythritol, xylitol, maltitol, sorbitol, isomalt, allulose, or monk-fruit blends (e.g. Lakanto). If a product is explicitly labeled "sugar free" or "no sugar added" and has meaningful carbs, assume the bulk of those carbs are sugar alcohols and populate the field accordingly.
        - `fiber` and `sugarAlcohols` are OPTIONAL — omit or use null if truly zero; never invent fiber/sugar alcohols for foods that don't contain them (e.g. plain meats, oils).
        - Meal-level `fiber` and `sugarAlcohols` should equal the sum of the corresponding ingredient fields.
        - Return only the JSON object — no commentary.

        Title: "\(title)"
        Description: "\(description)"
        """

        MacraOpenAIBridge.postChat(
            messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            model: bridgeModel,
            maxTokens: 1500,
            temperature: 0.2,
            responseFormat: ["type": "json_object"],
            organization: "macraMealNote"
        ) { result in
            switch result {
            case .success(let content):
                print("[Macra][GPTService.analyzeMealNote] ✅ bridge returned content (\(content.count) chars)")
                do {
                    let analysis = try Self.parseMealAnalysisJSON(content)
                    if analysis.calories == 0, analysis.protein == 0, analysis.carbs == 0, analysis.fat == 0 {
                        print("[Macra][GPTService.analyzeMealNote] ⚠️ analyzer returned all-zero macros for '\(analysis.name)' — rejecting")
                        completion(.failure(MealAnalysisError.zeroMacros))
                        return
                    }
                    print("[Macra][GPTService.analyzeMealNote] ✅ parsed — name:'\(analysis.name)' \(analysis.calories)kcal P:\(analysis.protein) C:\(analysis.carbs) F:\(analysis.fat) ingredients:\(analysis.ingredients.count)")
                    completion(.success(analysis))
                } catch {
                    print("[Macra][GPTService.analyzeMealNote] ❌ parse error: \(error.localizedDescription)")
                    completion(.failure(error))
                }

            case .failure(let error):
                print("[Macra][GPTService.analyzeMealNote] ❌ bridge error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    static func parseMealAnalysisJSON(_ raw: String) throws -> MealAnalysis {
        let dict: [String: Any]
        do {
            dict = try Self.jsonObjectDictionary(fromOpenAIContent: raw)
        } catch let error as JSONContentParseError {
            throw MealAnalysisError.parsingFailed(error.detail)
        } catch {
            throw MealAnalysisError.parsingFailed("JSON deserialization failed: \(error.localizedDescription)")
        }

        let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let calories = intValue(dict["calories"])
        let protein = intValue(dict["protein"])
        let carbs = intValue(dict["carbs"])
        let fat = intValue(dict["fat"])
        let fiber = optionalIntValue(dict["fiber"])
        let sugarAlcohols = optionalIntValue(dict["sugarAlcohols"])

        var ingredients: [MealAnalysisIngredient] = []
        if let rawIngredients = dict["ingredients"] as? [[String: Any]] {
            ingredients = rawIngredients.flatMap(mealAnalysisIngredients)
        }

        let resolvedCalories = ingredients.isEmpty ? calories : ingredients.reduce(0) { $0 + $1.calories }
        let resolvedProtein = ingredients.isEmpty ? protein : ingredients.reduce(0) { $0 + $1.protein }
        let resolvedCarbs = ingredients.isEmpty ? carbs : ingredients.reduce(0) { $0 + $1.carbs }
        let resolvedFat = ingredients.isEmpty ? fat : ingredients.reduce(0) { $0 + $1.fat }

        // If the model populated ingredient-level fiber/sugarAlcohols but
        // forgot the meal-level totals, derive them so netCarbs still works.
        let resolvedFiber: Int? = {
            if let fiber { return fiber }
            let sum = ingredients.compactMap { $0.fiber }.reduce(0, +)
            let anyPresent = ingredients.contains(where: { $0.fiber != nil })
            return anyPresent ? sum : nil
        }()

        let resolvedSugarAlcohols: Int? = {
            if let sugarAlcohols { return sugarAlcohols }
            let sum = ingredients.compactMap { $0.sugarAlcohols }.reduce(0, +)
            let anyPresent = ingredients.contains(where: { $0.sugarAlcohols != nil })
            return anyPresent ? sum : nil
        }()

        return MealAnalysis(
            name: name,
            calories: resolvedCalories,
            protein: resolvedProtein,
            carbs: resolvedCarbs,
            fat: resolvedFat,
            fiber: resolvedFiber,
            sugarAlcohols: resolvedSugarAlcohols,
            ingredients: ingredients
        )
    }

    private static func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d.rounded()) }
        if let s = any as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = Int(trimmed) { return i }
            if let d = Double(trimmed) { return Int(d.rounded()) }
        }
        return 0
    }

    /// Like `intValue` but returns nil for null/missing/unparseable fields so
    /// we can distinguish "no fiber data" from "zero grams of fiber" on fields
    /// like `fiber` and `sugarAlcohols`.
    private static func optionalIntValue(_ any: Any?) -> Int? {
        guard let any else { return nil }
        if any is NSNull { return nil }
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d.rounded()) }
        if let s = any as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.lowercased() == "null" { return nil }
            if let i = Int(trimmed) { return i }
            if let d = Double(trimmed) { return Int(d.rounded()) }
        }
        return nil
    }

    // MARK: - Nora assess-macros analysis

    /// Result of a Nora-driven macro assessment: target macros + an optional
    /// meal plan the user can accept in place of their existing plan.
    struct NoraMacroAnalysis {
        struct Macros {
            let calories: Int
            let protein: Int
            let carbs: Int
            let fat: Int
            let rationale: String
        }

        struct ScopedMacros {
            let label: String
            let days: [String]
            let macros: Macros
        }

        struct PlanItem {
            let name: String
            let quantity: String
            let calories: Int
            let protein: Int
            let carbs: Int
            let fat: Int
        }

        struct PlanMeal {
            let title: String
            let notes: String?
            let items: [PlanItem]

            var totalCalories: Int { items.reduce(0) { $0 + $1.calories } }
            var totalProtein: Int { items.reduce(0) { $0 + $1.protein } }
            var totalCarbs: Int { items.reduce(0) { $0 + $1.carbs } }
            var totalFat: Int { items.reduce(0) { $0 + $1.fat } }
        }

        let summary: String
        let macros: Macros
        let scopedMacros: [ScopedMacros]
        let planName: String
        let meals: [PlanMeal]
    }

    enum NoraMacroAnalysisError: LocalizedError {
        case parsingFailed(String)
        case emptyInput

        var errorDescription: String? {
            switch self {
            case .parsingFailed(let detail): return "Nora couldn't parse that: \(detail)"
            case .emptyInput: return "Add a prompt or an image so Nora has something to work with."
            }
        }
    }

    /// Asks Nora for a macro target + matching meal plan. Either or both of
    /// `prompt` and `images` can be provided. Images should already be
    /// compressed — we base64-encode them inline for the vision model, so
    /// multi-megabyte originals will inflate the request significantly.
    ///
    /// Routes through `MacraOpenAIBridge` with the `gpt-4o` model so vision
    /// content parts are supported, and tags the call with
    /// `openai-organization: macraAssessMacros` for server-side routing.
    func analyzeMacrosWithNora(
        prompt: String,
        images: [UIImage],
        bodyContext: String,
        completion: @escaping (Result<NoraMacroAnalysis, Error>) -> Void
    ) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPrompt.isEmpty || !images.isEmpty else {
            completion(.failure(NoraMacroAnalysisError.emptyInput))
            return
        }

        print("[Macra][Nora.analyzeMacros] ▶️ promptLen:\(trimmedPrompt.count) images:\(images.count)")

        let systemPrompt = """
        You are Nora, Macra's performance nutrition coach specializing in physique athletes and serious macro tracking. When a user gives you context — a text description of their goals, a screenshot of a meal plan from another source, or both — you produce:
        1. A daily macro target that fits their stated goals.
        2. A single-day meal plan with 3–5 meals whose totals sum to those macros (±5%).

        If the user's input is a meal plan screenshot/image or pasted coach plan, transcribe the exact meals first, then calculate macros from the stated quantities. Do not invent meals that aren't present in the source. If you have to infer calories or macros for an image item, note that in the meal's `notes` field.

        Reasoning order:
        - First classify the user's context: general user, off-season, contest prep, peak week, post-show reverse, or unknown.
        - User-provided macro targets, screenshots, and numbers are inputs to audit, not automatic truth.
        - If targets look inconsistent with body weight, timeline, division, conditioning, or stated goal, make the `macros.rationale` flag that mismatch.
        - For physique competitors within 8 weeks of a show, prioritize stage-readiness, digestion consistency, visual predictability, and adherence over generic health advice.
        - In near-show physique context, do not casually add fruit, whole grains, high-variance foods, or generic starchy vegetables. Favor predictable prep foods such as rice, cream of rice, potatoes, already-tolerated oats, and lean proteins.
        - Recommend gradual adjustments only. If increasing carbs, think in small moves such as 25–50g unless the user explicitly asks for a full reset.

        Return ONLY valid JSON matching this schema exactly — no markdown, no prose:

        {
          "summary": "one-sentence explanation of the plan (under 140 chars)",
          "macros": {
            "calories": int,
            "protein": int,
            "carbs": int,
            "fat": int,
            "rationale": "one-sentence why these numbers (under 140 chars)"
          },
          "scopedMacros": [
            {
              "label": "Fri & Sat substitution",
              "days": ["fri", "sat"],
              "macros": {
                "calories": int,
                "protein": int,
                "carbs": int,
                "fat": int,
                "rationale": "one-sentence why this day differs (under 140 chars)"
              }
            }
          ],
          "mealPlan": {
            "name": "short plan name (under 40 chars)",
            "meals": [
              {
                "title": "Meal 1",
                "notes": "optional short notes or null",
                "items": [
                  {
                    "name": "food item",
                    "quantity": "amount with unit (e.g. '1 cup', '4 oz')",
                    "calories": int,
                    "protein": int,
                    "carbs": int,
                    "fat": int
                  }
                ]
              }
            ]
          }
        }

        Rules:
        - Use "Meal 1", "Meal 2" labels; NEVER breakfast/lunch/dinner/snack.
        \(Self.mealAnalyzerAccuracyRules)
        - If the plan has explicit day-specific substitutions or variants (for example "Fri & Sat, Sub", "Monday/Thursday high carb", "rest day swap"), calculate `macros` from the default/all-days plan and add `scopedMacros` entries for the affected weekdays.
        - `scopedMacros[].macros` must be the full-day total for that scoped day after applying substitutions, not the macro delta.
        - Use weekday abbreviations only in `scopedMacros[].days`: "mon", "tue", "wed", "thu", "fri", "sat", "sun". Omit variants without explicit weekdays from `scopedMacros`.
        - If there are no explicit weekday variants, return `scopedMacros: []`.
        - Use realistic whole-food ingredients; no novelty items.
        - Match food choices to the user's phase; do not default to general wellness foods when the user is in prep, peak week, or post-show reverse.
        - All numeric fields are integers (round).
        - Meal totals must sum close to the meal plan totals; plan totals must sum close to the daily macros (±5%).
        """

        // Compose the user message as a mixed content payload (text + images)
        // so the vision model can see both the prompt and any attached
        // screenshots in the same turn.
        var content: [[String: Any]] = []

        var userText = "User body/goal context: \(bodyContext)"
        if !trimmedPrompt.isEmpty {
            userText += "\n\nUser prompt:\n\(trimmedPrompt)"
        }
        if !images.isEmpty {
            userText += "\n\nThe user attached \(images.count) image\(images.count == 1 ? "" : "s"). If any of them look like a meal plan or nutrition breakdown, transcribe those meals faithfully into the `mealPlan` field."
        }
        content.append(["type": "text", "text": userText])

        for image in images {
            guard let jpeg = image.jpegData(compressionQuality: 0.6) else { continue }
            let base64 = jpeg.base64EncodedString()
            content.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
            ])
        }

        MacraOpenAIBridge.postChat(
            messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": content]
            ],
            model: "gpt-4o",
            maxTokens: 2500,
            temperature: 0.3,
            responseFormat: ["type": "json_object"],
            organization: "macraAssessMacros"
        ) { result in
            switch result {
            case .success(let raw):
                do {
                    let analysis = try Self.parseNoraAnalysisJSON(raw)
                    print("[Macra][Nora.analyzeMacros] ✅ \(analysis.macros.calories)kcal · plan:'\(analysis.planName)' meals:\(analysis.meals.count)")
                    completion(.success(analysis))
                } catch {
                    print("[Macra][Nora.analyzeMacros] raw preview: \(Self.debugPreview(raw))")
                    print("[Macra][Nora.analyzeMacros] ❌ parse error: \(error.localizedDescription)")
                    completion(.failure(error))
                }

            case .failure(let error):
                print("[Macra][Nora.analyzeMacros] ❌ bridge error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    static func parseNoraAnalysisJSON(_ raw: String) throws -> NoraMacroAnalysis {
        let dict: [String: Any]
        do {
            dict = try Self.jsonObjectDictionary(fromOpenAIContent: raw)
        } catch let error as JSONContentParseError {
            if let fallback = Self.fallbackNoraMacroAnalysis(from: raw) {
                return fallback
            }
            throw NoraMacroAnalysisError.parsingFailed(error.detail)
        } catch {
            if let fallback = Self.fallbackNoraMacroAnalysis(from: raw) {
                return fallback
            }
            throw NoraMacroAnalysisError.parsingFailed("JSON deserialize failed: \(error.localizedDescription)")
        }

        let summary = (dict["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let macrosDict = dict["macros"] as? [String: Any] else {
            throw NoraMacroAnalysisError.parsingFailed("missing `macros` object")
        }
        let macros = NoraMacroAnalysis.Macros(
            calories: intValue(macrosDict["calories"]),
            protein: intValue(macrosDict["protein"]),
            carbs: intValue(macrosDict["carbs"]),
            fat: intValue(macrosDict["fat"]),
            rationale: (macrosDict["rationale"] as? String) ?? ""
        )
        let scopedMacros = parseScopedMacros(from: dict)

        let planDict = dict["mealPlan"] as? [String: Any] ?? [:]
        let planName = ((planDict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Nora's plan"

        let rawMeals = planDict["meals"] as? [[String: Any]] ?? []
        let meals: [NoraMacroAnalysis.PlanMeal] = rawMeals.enumerated().map { index, mealDict in
            let title = (mealDict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (mealDict["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawItems = mealDict["items"] as? [[String: Any]] ?? []
            let items = rawItems.flatMap(planItems)
            return NoraMacroAnalysis.PlanMeal(
                title: (title?.isEmpty == false ? title! : "Meal \(index + 1)"),
                notes: notes?.isEmpty == false ? notes : nil,
                items: items
            )
        }

        return NoraMacroAnalysis(
            summary: summary,
            macros: macros,
            scopedMacros: scopedMacros,
            planName: planName,
            meals: meals
        )
    }

    private enum JSONContentParseError: Error {
        case noJSONObject
        case invalidUTF8
        case deserializeFailed(String)
        case rootIsNotObject
        case nestingLimit

        var detail: String {
            switch self {
            case .noJSONObject:
                return "no JSON object found"
            case .invalidUTF8:
                return "invalid UTF-8"
            case .deserializeFailed(let detail):
                return "JSON deserialize failed: \(detail)"
            case .rootIsNotObject:
                return "root is not an object"
            case .nestingLimit:
                return "JSON response was nested too deeply"
            }
        }
    }

    /// Extracts the JSON object returned by the OpenAI bridge. The model is
    /// asked for a bare object, but in practice responses can be wrapped in a
    /// markdown fence, a full chat-completion envelope, or even a JSON string
    /// containing an escaped object. This keeps those transport quirks out of
    /// the feature parsers.
    private static func jsonObjectDictionary(fromOpenAIContent raw: String, depth: Int = 0) throws -> [String: Any] {
        guard depth < 4 else {
            throw JSONContentParseError.nestingLimit
        }

        var lastError: JSONContentParseError?
        for candidate in jsonObjectCandidates(from: raw) {
            do {
                let value = try jsonValue(from: candidate)
                if let dict = try normalizedJSONObject(from: value, depth: depth) {
                    return dict
                }
                lastError = .rootIsNotObject
            } catch let error as JSONContentParseError {
                lastError = error
            } catch {
                lastError = .deserializeFailed(error.localizedDescription)
            }
        }

        throw lastError ?? JSONContentParseError.noJSONObject
    }

    private static func normalizedJSONObject(from value: Any, depth: Int) throws -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if let nestedContent = openAIMessageContent(from: dict),
               let nestedDict = try? jsonObjectDictionary(fromOpenAIContent: nestedContent, depth: depth + 1) {
                return nestedDict
            }
            return dict
        }

        if let string = value as? String {
            return try jsonObjectDictionary(fromOpenAIContent: string, depth: depth + 1)
        }

        return nil
    }

    private static func jsonValue(from candidate: String) throws -> Any {
        var lastError: JSONContentParseError?

        for repairedCandidate in repairedJSONCandidates(from: candidate) {
            guard let data = repairedCandidate.data(using: .utf8) else {
                throw JSONContentParseError.invalidUTF8
            }

            do {
                return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            } catch {
                lastError = .deserializeFailed(error.localizedDescription)
            }

            do {
                return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed, .json5Allowed])
            } catch {
                lastError = .deserializeFailed(error.localizedDescription)
            }
        }

        throw lastError ?? JSONContentParseError.noJSONObject
    }

    private static func openAIMessageContent(from dict: [String: Any]) -> String? {
        if let choices = dict["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }

        if let message = dict["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }

        return nil
    }

    private static func jsonObjectCandidates(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates = [trimmed]
        candidates.append(contentsOf: fencedJSONCandidates(from: trimmed))
        candidates.append(contentsOf: balancedJSONObjectSubstrings(in: trimmed))

        var seen = Set<String>()
        return candidates.filter { candidate in
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }

    private static func fencedJSONCandidates(from text: String) -> [String] {
        var candidates: [String] = []
        var buffer: [String] = []
        var isInsideFence = false

        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
                if isInsideFence {
                    let candidate = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        candidates.append(candidate)
                    }
                    buffer.removeAll()
                    isInsideFence = false
                } else {
                    isInsideFence = true
                }
            } else if isInsideFence {
                buffer.append(line)
            }
        }

        return candidates
    }

    private static func balancedJSONObjectSubstrings(in text: String) -> [String] {
        var substrings: [String] = []
        var objectStart: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    if depth == 0 {
                        objectStart = index
                    }
                    depth += 1
                } else if character == "}", depth > 0 {
                    depth -= 1
                    if depth == 0, let start = objectStart {
                        substrings.append(String(text[start...index]))
                        objectStart = nil
                    }
                }
            }

            index = text.index(after: index)
        }

        return substrings
    }

    private static func repairedJSONCandidates(from candidate: String) -> [String] {
        let controlEscaped = escapingControlCharactersInsideStrings(candidate)
        let trailingCommaRemoved = removingTrailingCommas(candidate)
        let fullyRepaired = removingTrailingCommas(controlEscaped)

        var seen = Set<String>()
        return [candidate, controlEscaped, trailingCommaRemoved, fullyRepaired].filter { value in
            guard !seen.contains(value) else { return false }
            seen.insert(value)
            return true
        }
    }

    private static func escapingControlCharactersInsideStrings(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)

        var isInsideString = false
        var isEscaped = false

        for scalar in text.unicodeScalars {
            if isInsideString {
                if isEscaped {
                    output.unicodeScalars.append(scalar)
                    isEscaped = false
                    continue
                }

                if scalar == "\\" {
                    output.unicodeScalars.append(scalar)
                    isEscaped = true
                    continue
                }

                if scalar == "\"" {
                    output.unicodeScalars.append(scalar)
                    isInsideString = false
                    continue
                }

                switch scalar.value {
                case 0x08:
                    output += "\\b"
                case 0x09:
                    output += "\\t"
                case 0x0A:
                    output += "\\n"
                case 0x0C:
                    output += "\\f"
                case 0x0D:
                    output += "\\r"
                case 0x00..<0x20:
                    output += String(format: "\\u%04X", scalar.value)
                default:
                    output.unicodeScalars.append(scalar)
                }
            } else {
                output.unicodeScalars.append(scalar)
                if scalar == "\"" {
                    isInsideString = true
                }
            }
        }

        return output
    }

    private static func removingTrailingCommas(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var output = ""
        output.reserveCapacity(text.count)

        var isInsideString = false
        var isEscaped = false
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            if isInsideString {
                output.unicodeScalars.append(scalar)
                if isEscaped {
                    isEscaped = false
                } else if scalar == "\\" {
                    isEscaped = true
                } else if scalar == "\"" {
                    isInsideString = false
                }
                index += 1
                continue
            }

            if scalar == "\"" {
                isInsideString = true
                output.unicodeScalars.append(scalar)
                index += 1
                continue
            }

            if scalar == "," {
                var lookahead = index + 1
                while lookahead < scalars.count,
                      CharacterSet.whitespacesAndNewlines.contains(scalars[lookahead]) {
                    lookahead += 1
                }

                if lookahead < scalars.count,
                   scalars[lookahead] == "}" || scalars[lookahead] == "]" {
                    index += 1
                    continue
                }
            }

            output.unicodeScalars.append(scalar)
            index += 1
        }

        return output
    }

    private static func fallbackNoraMacroAnalysis(from raw: String) -> NoraMacroAnalysis? {
        for candidate in jsonObjectCandidates(from: raw) {
            guard let macrosText = jsonObjectString(forKey: "macros", in: candidate) else {
                continue
            }

            let macrosDict = (try? jsonObjectDictionary(fromOpenAIContent: macrosText)) ?? [:]
            let calories = intValue(macrosDict["calories"]) > 0
                ? intValue(macrosDict["calories"])
                : firstIntValue(forKey: "calories", in: macrosText)
            let protein = intValue(macrosDict["protein"]) > 0
                ? intValue(macrosDict["protein"])
                : firstIntValue(forKey: "protein", in: macrosText)
            let carbs = intValue(macrosDict["carbs"]) > 0
                ? intValue(macrosDict["carbs"])
                : firstIntValue(forKey: "carbs", in: macrosText)
            let fat = intValue(macrosDict["fat"]) > 0
                ? intValue(macrosDict["fat"])
                : firstIntValue(forKey: "fat", in: macrosText)

            guard calories > 0 else { continue }

            let rationale = (macrosDict["rationale"] as? String)
                ?? firstStringValue(forKey: "rationale", in: macrosText)
                ?? ""
            let summary = firstStringValue(forKey: "summary", in: candidate)
                ?? "Nora generated a macro target."
            let planName = jsonObjectString(forKey: "mealPlan", in: candidate)
                .flatMap { firstStringValue(forKey: "name", in: $0) }
                ?? "Nora's plan"

            print("[Macra][Nora.analyzeMacros] ⚠️ salvaged macro target from malformed JSON; meal plan omitted")
            return NoraMacroAnalysis(
                summary: summary,
                macros: NoraMacroAnalysis.Macros(
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    rationale: rationale
                ),
                scopedMacros: [],
                planName: planName,
                meals: []
            )
        }

        return nil
    }

    private static func jsonObjectString(forKey key: String, in text: String) -> String? {
        guard let keyRange = text.range(of: "\"\(key)\"") else { return nil }
        guard let colonRange = text[keyRange.upperBound...].range(of: ":") else { return nil }

        var index = colonRange.upperBound
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }

        guard index < text.endIndex, text[index] == "{" else { return nil }

        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var cursor = index

        while cursor < text.endIndex {
            let character = text[cursor]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[index...cursor])
                    }
                }
            }

            cursor = text.index(after: cursor)
        }

        return nil
    }

    private static func firstIntValue(forKey key: String, in text: String) -> Int {
        let pattern = #""\#(key)"\s*:\s*"?(-?\d[\d,]*(?:\.\d+)?)"?"#
        guard let match = firstMatch(pattern: pattern, in: text),
              let range = Range(match.range(at: 1), in: text) else {
            return 0
        }

        let number = String(text[range]).replacingOccurrences(of: ",", with: "")
        if let int = Int(number) { return int }
        if let double = Double(number) { return Int(double.rounded()) }
        return 0
    }

    private static func firstStringValue(forKey key: String, in text: String) -> String? {
        let pattern = #""\#(key)"\s*:\s*"((?:\\.|[^"\\])*)"#
        guard let match = firstMatch(pattern: pattern, in: text),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let escapedValue = String(text[range])
        let quotedValue = "\"\(escapedValue)\""
        if let data = quotedValue.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return escapedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range)
    }

    private static func debugPreview(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .prefix(900)
            .description
    }

    private struct MacroEstimate {
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double

        func scaled(by multiplier: Double) -> MacroEstimate {
            MacroEstimate(
                calories: calories * multiplier,
                protein: protein * multiplier,
                carbs: carbs * multiplier,
                fat: fat * multiplier
            )
        }
    }

    private static func mealAnalysisIngredients(from item: [String: Any]) -> [MealAnalysisIngredient] {
        let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return [] }

        let quantity = (item["quantity"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if quantity.isEmpty, let splitIngredients = splitKnownMealAnalysisIngredients(from: name) {
            return splitIngredients
        }

        return [
            normalizedMealAnalysisIngredient(
                name: name,
                quantity: quantity,
                rawCalories: intValue(item["calories"]),
                rawProtein: intValue(item["protein"]),
                rawCarbs: intValue(item["carbs"]),
                rawFat: intValue(item["fat"]),
                rawFiber: optionalIntValue(item["fiber"]),
                rawSugarAlcohols: optionalIntValue(item["sugarAlcohols"])
            )
        ]
    }

    private static func splitKnownMealAnalysisIngredients(from text: String) -> [MealAnalysisIngredient]? {
        let parts = splitFoodComponents(text)
        guard parts.count > 1 else { return nil }

        let ingredients = parts.compactMap { part -> MealAnalysisIngredient? in
            guard let estimate = estimateKnownFoodMacros(name: part, quantity: "") else {
                return nil
            }

            return mealAnalysisIngredient(name: part, quantity: "", estimate: estimate)
        }

        return ingredients.count == parts.count ? ingredients : nil
    }

    private static func normalizedMealAnalysisIngredient(
        name: String,
        quantity: String,
        rawCalories: Int,
        rawProtein: Int,
        rawCarbs: Int,
        rawFat: Int,
        rawFiber: Int?,
        rawSugarAlcohols: Int?
    ) -> MealAnalysisIngredient {
        if let estimate = estimateKnownFoodMacros(name: name, quantity: quantity) {
            return mealAnalysisIngredient(
                name: name,
                quantity: quantity,
                estimate: estimate,
                fiber: rawFiber,
                sugarAlcohols: rawSugarAlcohols
            )
        }

        return MealAnalysisIngredient(
            name: name,
            quantity: quantity,
            calories: normalizedCalories(rawCalories, protein: rawProtein, carbs: rawCarbs, fat: rawFat),
            protein: rawProtein,
            carbs: rawCarbs,
            fat: rawFat,
            fiber: rawFiber,
            sugarAlcohols: rawSugarAlcohols
        )
    }

    private static func mealAnalysisIngredient(
        name: String,
        quantity: String,
        estimate: MacroEstimate,
        fiber: Int? = nil,
        sugarAlcohols: Int? = nil
    ) -> MealAnalysisIngredient {
        MealAnalysisIngredient(
            name: name,
            quantity: quantity,
            calories: max(0, Int(estimate.calories.rounded())),
            protein: max(0, Int(estimate.protein.rounded())),
            carbs: max(0, Int(estimate.carbs.rounded())),
            fat: max(0, Int(estimate.fat.rounded())),
            fiber: fiber,
            sugarAlcohols: sugarAlcohols
        )
    }

    private static func planItems(from item: [String: Any]) -> [NoraMacroAnalysis.PlanItem] {
        let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return [] }

        let quantity = (item["quantity"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if quantity.isEmpty, let splitItems = splitKnownPlanItems(from: name) {
            return splitItems
        }

        return [
            normalizedPlanItem(
                name: name,
                quantity: quantity,
                rawCalories: intValue(item["calories"]),
                rawProtein: intValue(item["protein"]),
                rawCarbs: intValue(item["carbs"]),
                rawFat: intValue(item["fat"])
            )
        ]
    }

    private static func splitKnownPlanItems(from text: String) -> [NoraMacroAnalysis.PlanItem]? {
        let parts = splitFoodComponents(text)
        guard parts.count > 1 else { return nil }

        let items = parts.compactMap { part -> NoraMacroAnalysis.PlanItem? in
            guard let estimate = estimateKnownFoodMacros(name: part, quantity: "") else {
                return nil
            }

            return planItem(name: part, quantity: "", estimate: estimate)
        }

        return items.count == parts.count ? items : nil
    }

    private static func splitFoodComponents(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "/", with: "+")
            .components(separatedBy: CharacterSet(charactersIn: "+,;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedPlanItem(
        name: String,
        quantity: String,
        rawCalories: Int,
        rawProtein: Int,
        rawCarbs: Int,
        rawFat: Int
    ) -> NoraMacroAnalysis.PlanItem {
        if let estimate = estimateKnownFoodMacros(name: name, quantity: quantity) {
            return planItem(name: name, quantity: quantity, estimate: estimate)
        }

        return NoraMacroAnalysis.PlanItem(
            name: name,
            quantity: quantity,
            calories: normalizedCalories(rawCalories, protein: rawProtein, carbs: rawCarbs, fat: rawFat),
            protein: rawProtein,
            carbs: rawCarbs,
            fat: rawFat
        )
    }

    private static func planItem(
        name: String,
        quantity: String,
        estimate: MacroEstimate
    ) -> NoraMacroAnalysis.PlanItem {
        NoraMacroAnalysis.PlanItem(
            name: name,
            quantity: quantity,
            calories: max(0, Int(estimate.calories.rounded())),
            protein: max(0, Int(estimate.protein.rounded())),
            carbs: max(0, Int(estimate.carbs.rounded())),
            fat: max(0, Int(estimate.fat.rounded()))
        )
    }

    private static func normalizedCalories(_ rawCalories: Int, protein: Int, carbs: Int, fat: Int) -> Int {
        let macroCalories = macroCalories(protein: protein, carbs: carbs, fat: fat)
        guard macroCalories > 0 else { return max(0, rawCalories) }
        guard rawCalories > 0 else { return macroCalories }

        let tolerance = max(20, Int(Double(max(rawCalories, macroCalories)) * 0.15))
        return abs(rawCalories - macroCalories) > tolerance ? macroCalories : rawCalories
    }

    private static func macroCalories(protein: Int, carbs: Int, fat: Int) -> Int {
        protein * 4 + carbs * 4 + fat * 9
    }

    private static func estimateKnownFoodMacros(name: String, quantity: String) -> MacroEstimate? {
        let text = normalizedNutritionText("\(quantity) \(name)")
        guard !text.isEmpty else { return nil }

        if text.contains("fish oil") || text.contains("multivitamin") || text.contains("multi vitamin") ||
            text.contains("vitamin ") || text.contains("magnesium") || text.contains("potassium") ||
            text.contains("taurine") || text.contains("zma") || text.contains("cla") {
            return nil
        }

        if text.contains("egg white") {
            let cups = amount(in: text, units: ["cups", "cup"], defaultAmount: 1)
            if let cups {
                return MacroEstimate(calories: 126, protein: 26, carbs: 2, fat: 0).scaled(by: cups)
            }
        }

        if text.contains("whole egg") || text.contains("large egg") || text == "egg" || text.contains(" egg") {
            let eggs = amount(in: text, units: ["whole eggs", "whole egg", "large eggs", "large egg", "eggs", "egg"], defaultAmount: 1)
            if let eggs {
                return MacroEstimate(calories: 70, protein: 6, carbs: 0, fat: 5).scaled(by: eggs)
            }
        }

        if text.contains("cream of rice") {
            let grams = amount(in: text, units: ["grams", "gram", "g"])
                ?? amount(in: text, units: ["scoops", "scoop"], defaultAmount: 1).map { $0 * 35 }
            if let grams {
                return MacroEstimate(calories: 130, protein: 2, carbs: 28, fat: 0).scaled(by: grams / 35)
            }
        }

        if text.contains("rice cake") {
            let cakes = amount(in: text, units: ["plain rice cakes", "plain rice cake", "rice cakes", "rice cake"], defaultAmount: 1)
            if let cakes {
                return MacroEstimate(calories: 35, protein: 1, carbs: 7, fat: 0).scaled(by: cakes)
            }
        }

        if text.contains("almond butter") {
            let tablespoons = amount(in: text, units: ["tablespoons", "tablespoon", "tbsp", "tbsps"], defaultAmount: 1)
            if let tablespoons {
                return MacroEstimate(calories: 98, protein: 3, carbs: 3, fat: 9).scaled(by: tablespoons)
            }
        }

        if text.contains("almonds") || text.contains(" almond") {
            let almonds = amount(in: text, units: ["almonds", "almond"], defaultAmount: 1)
            if let almonds {
                return MacroEstimate(calories: 7, protein: 0.26, carbs: 0.26, fat: 0.61).scaled(by: almonds)
            }
        }

        if text.contains("protein shake") || text.contains("protein powder") || text.contains("whey") {
            let scoops = amount(in: text, units: ["scoops", "scoop"], defaultAmount: 1) ?? 1
            return MacroEstimate(calories: 120, protein: 25, carbs: 3, fat: 2).scaled(by: scoops)
        }

        if text.contains("chicken breast") || text.contains("chicken") {
            if let ounces = ouncesAmount(in: text) {
                return MacroEstimate(calories: 47, protein: 9, carbs: 0, fat: 1).scaled(by: ounces)
            }
        }

        if text.contains("ground turkey") {
            if let ounces = ouncesAmount(in: text) {
                return MacroEstimate(calories: 43, protein: 7, carbs: 0, fat: 2).scaled(by: ounces)
            }
        }

        if text.contains("white fish") || text.contains("cod") || text.contains("tilapia") {
            if let ounces = ouncesAmount(in: text) {
                return MacroEstimate(calories: 32, protein: 7, carbs: 0, fat: 0.3).scaled(by: ounces)
            }
        }

        if text.contains("jasmine rice") || text.contains("white rice") || (text.contains(" rice") && !text.contains("rice cake") && !text.contains("cream of rice")) {
            let isDry = text.contains("dry") || text.contains("uncooked") || text.contains("raw")
            if let grams = amount(in: text, units: ["grams", "gram", "g"]) {
                let per100 = isDry
                    ? MacroEstimate(calories: 365, protein: 7, carbs: 80, fat: 1)
                    : MacroEstimate(calories: 130, protein: 2.7, carbs: 28.2, fat: 0.3)
                return per100.scaled(by: grams / 100)
            }
            if let cups = amount(in: text, units: ["cups", "cup"], defaultAmount: 1) {
                return MacroEstimate(calories: 205, protein: 4.3, carbs: 44.5, fat: 0.4).scaled(by: cups)
            }
        }

        if text.contains("white potato") || text.contains("potato") {
            if let grams = amount(in: text, units: ["grams", "gram", "g"]) {
                return MacroEstimate(calories: 87, protein: 1.9, carbs: 20.1, fat: 0.1).scaled(by: grams / 100)
            }
        }

        if text.contains("asparagus") {
            if let ounces = ouncesAmount(in: text) {
                return MacroEstimate(calories: 6, protein: 0.6, carbs: 1.1, fat: 0).scaled(by: ounces)
            }
        }

        if text.contains("vegetables") || text.contains("veggies") {
            if let ounces = ouncesAmount(in: text) {
                return MacroEstimate(calories: 10, protein: 0.5, carbs: 2, fat: 0).scaled(by: ounces)
            }
        }

        if text.contains("spinach") {
            let cups = amount(in: text, units: ["cups", "cup"], defaultAmount: 1) ?? 1
            return MacroEstimate(calories: 7, protein: 1, carbs: 1, fat: 0).scaled(by: cups)
        }

        return nil
    }

    private static func ouncesAmount(in text: String) -> Double? {
        if let ounces = amount(in: text, units: ["ounces", "ounce", "oz"]) {
            return ounces
        }
        if let grams = amount(in: text, units: ["grams", "gram", "g"]) {
            return grams / 28.3495
        }
        return nil
    }

    private static func amount(in text: String, units: [String], defaultAmount: Double? = nil) -> Double? {
        let escapedUnits = units
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern = #"(?i)(?:(\d+(?:\.\d+)?|\d+\s*/\s*\d+)\s*)?(?:\#(escapedUnits))\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }

        if match.range(at: 1).location != NSNotFound,
           let amountRange = Range(match.range(at: 1), in: text) {
            return nutritionAmount(from: String(text[amountRange]))
        }

        return defaultAmount
    }

    private static func nutritionAmount(from text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: " ", with: "")
        if normalized.contains("/") {
            let pieces = normalized.split(separator: "/")
            guard pieces.count == 2,
                  let numerator = Double(pieces[0]),
                  let denominator = Double(pieces[1]),
                  denominator != 0 else {
                return nil
            }
            return numerator / denominator
        }
        return Double(normalized)
    }

    private static func normalizedNutritionText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseScopedMacros(from dict: [String: Any]) -> [NoraMacroAnalysis.ScopedMacros] {
        let rawEntries = dict["scopedMacros"] as? [[String: Any]]
            ?? dict["dayMacros"] as? [[String: Any]]
            ?? dict["macroVariants"] as? [[String: Any]]
            ?? []

        return rawEntries.compactMap { entry in
            let rawDays = (entry["days"] as? [Any] ?? entry["dayOfWeek"] as? [Any] ?? [])
                .compactMap { $0 as? String }
            let singleDay = (entry["day"] as? String) ?? (entry["dayOfWeek"] as? String)
            let days = (rawDays + [singleDay].compactMap { $0 })
                .compactMap(normalizedMacroDay)
                .removingDuplicates()

            guard !days.isEmpty else { return nil }

            let macrosDict = entry["macros"] as? [String: Any] ?? entry
            let macros = NoraMacroAnalysis.Macros(
                calories: intValue(macrosDict["calories"]),
                protein: intValue(macrosDict["protein"]),
                carbs: intValue(macrosDict["carbs"]),
                fat: intValue(macrosDict["fat"]),
                rationale: (macrosDict["rationale"] as? String)
                    ?? (entry["rationale"] as? String)
                    ?? ""
            )

            guard macros.calories > 0 else { return nil }

            let label = ((entry["label"] as? String) ?? days.map { $0.uppercased() }.joined(separator: ", "))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return NoraMacroAnalysis.ScopedMacros(
                label: label.isEmpty ? days.map { $0.uppercased() }.joined(separator: ", ") : label,
                days: days,
                macros: macros
            )
        }
    }

    private static func normalizedMacroDay(_ rawValue: String) -> String? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mon", "monday":
            return "mon"
        case "tue", "tues", "tuesday":
            return "tue"
        case "wed", "wednesday":
            return "wed"
        case "thu", "thur", "thurs", "thursday":
            return "thu"
        case "fri", "friday":
            return "fri"
        case "sat", "saturday":
            return "sat"
        case "sun", "sunday":
            return "sun"
        default:
            return nil
        }
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Shared OpenAI bridge client

/// Routes all Macra OpenAI traffic through the fitwithpulse.ai server bridge at
/// `/api/openai/v1/chat/completions`. The bridge holds the real OpenAI API key;
/// the client authenticates with a short-lived Firebase ID token so we never
/// ship an `OPENAI_API_KEY` in the app bundle.
///
/// Mirrors the request shape the `generate-macra-meal-plan` and
/// `nora-nutrition-chat` Netlify functions already use.
enum MacraOpenAIBridge {

    enum BridgeError: LocalizedError {
        case notAuthenticated
        case invalidURL(String)
        case invalidRequestBody(Error)
        case transport(Error)
        case nonHTTPResponse
        case httpError(status: Int, body: String)
        case emptyContent

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "You need to be signed in to use the AI analyzer."
            case .invalidURL(let base): return "Analyzer endpoint misconfigured (base: \(base))."
            case .invalidRequestBody(let error): return "Failed to encode request body: \(error.localizedDescription)"
            case .transport(let error): return error.localizedDescription
            case .nonHTTPResponse: return "Unexpected non-HTTP response from analyzer bridge."
            case .httpError(let status, let body):
                let trimmed = body.prefix(180)
                return "Analyzer bridge returned \(status): \(trimmed)"
            case .emptyContent: return "Analyzer bridge returned empty content."
            }
        }
    }

    /// POSTs an OpenAI-style chat completions payload to the bridge and
    /// returns the assistant message text on success.
    ///
    /// - Parameters:
    ///   - messages: standard OpenAI chat messages (each a `[String: Any]`).
    ///     Vision calls should pass `content` as an array of content parts.
    ///   - model: OpenAI model id the bridge should forward to.
    ///   - maxTokens: maps to `max_tokens` on the chat completions request.
    ///   - temperature: maps to `temperature`.
    ///   - responseFormat: optional `response_format` override, e.g.
    ///     `["type": "json_object"]`. Pass `nil` to omit.
    ///   - organization: value forwarded in the `openai-organization` header.
    ///     Useful for server-side routing/rate-limiting by feature.
    ///   - completion: called on an arbitrary queue — hop back to the main
    ///     queue if you touch `@Published` state.
    static func postChat(
        messages: [[String: Any]],
        model: String,
        maxTokens: Int,
        temperature: Double,
        responseFormat: [String: Any]? = nil,
        organization: String,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 45,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let user = Auth.auth().currentUser else {
            print("[Macra][Bridge] ❌ no signed-in Firebase user (org:\(organization))")
            completion(.failure(BridgeError.notAuthenticated))
            return
        }

        let base = ConfigManager.shared.getWebsiteBaseURL()
        guard let url = URL(string: "\(base)/api/openai/v1/chat/completions") else {
            print("[Macra][Bridge] ❌ invalid bridge URL from base '\(base)'")
            completion(.failure(BridgeError.invalidURL(base)))
            return
        }

        user.getIDToken { token, error in
            if let error {
                print("[Macra][Bridge] ❌ getIDToken failed (org:\(organization)): \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            guard let token, !token.isEmpty else {
                print("[Macra][Bridge] ❌ getIDToken returned empty token (org:\(organization))")
                completion(.failure(BridgeError.notAuthenticated))
                return
            }

            var payload: [String: Any] = [
                "model": model,
                "messages": messages,
                "max_tokens": maxTokens,
                "temperature": temperature
            ]
            if let responseFormat {
                payload["response_format"] = responseFormat
            }

            let bodyData: Data
            do {
                bodyData = try JSONSerialization.data(withJSONObject: payload, options: [])
            } catch {
                print("[Macra][Bridge] ❌ failed to encode payload (org:\(organization)): \(error.localizedDescription)")
                completion(.failure(BridgeError.invalidRequestBody(error)))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(organization, forHTTPHeaderField: "openai-organization")
            request.httpBody = bodyData
            request.timeoutInterval = timeoutInterval

            print("[Macra][Bridge] ▶️ POST \(url.absoluteString) org:\(organization) model:\(model) msgs:\(messages.count)")

            session.dataTask(with: request) { data, response, error in
                if let error {
                    print("[Macra][Bridge] ❌ transport error (org:\(organization)): \(error.localizedDescription)")
                    completion(.failure(BridgeError.transport(error)))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("[Macra][Bridge] ❌ non-HTTP response (org:\(organization))")
                    completion(.failure(BridgeError.nonHTTPResponse))
                    return
                }

                let data = data ?? Data()

                guard (200..<300).contains(httpResponse.statusCode) else {
                    let bodyString = String(data: data, encoding: .utf8) ?? ""
                    print("[Macra][Bridge] ❌ HTTP \(httpResponse.statusCode) (org:\(organization)): \(bodyString.prefix(300))")
                    completion(.failure(BridgeError.httpError(status: httpResponse.statusCode, body: bodyString)))
                    return
                }

                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let choices = json["choices"] as? [[String: Any]],
                    let firstChoice = choices.first,
                    let message = firstChoice["message"] as? [String: Any],
                    let content = message["content"] as? String,
                    !content.isEmpty
                else {
                    print("[Macra][Bridge] ❌ could not extract message.content (org:\(organization))")
                    completion(.failure(BridgeError.emptyContent))
                    return
                }

                print("[Macra][Bridge] ✅ \(httpResponse.statusCode) (org:\(organization)) — content:\(content.count) chars")
                completion(.success(content))
            }.resume()
        }
    }
}
