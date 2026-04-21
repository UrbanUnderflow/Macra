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

        let systemPrompt = "You are a precise nutrition analyzer. You return ONLY valid JSON matching the requested schema, no prose, no markdown fences."
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

        Rules:
        1. All macro fields are integers (round if needed).
        2. Meal totals must equal the sum of ingredient macros within ±5%.
        3. If portion sizes aren't specified, use realistic defaults (e.g. "1 medium", "1 cup") and reflect that in the `quantity` field.
        4. If the input is ambiguous, estimate with standard USDA-style values instead of returning zeros.
        5. Populate `fiber` whenever a food realistically contains dietary fiber (fruits, vegetables, legumes, whole grains, nuts, seeds).
        6. Populate `sugarAlcohols` for any food/ingredient containing sugar alcohols — common in sugar-free products, keto/low-carb baked goods, protein bars, and items sweetened with erythritol, xylitol, maltitol, sorbitol, isomalt, allulose, or monk-fruit blends (e.g. Lakanto). If a product is explicitly labeled "sugar free" or "no sugar added" and has meaningful carbs, assume the bulk of those carbs are sugar alcohols and populate the field accordingly.
        7. `fiber` and `sugarAlcohols` are OPTIONAL — omit or use null if truly zero; never invent fiber/sugar alcohols for foods that don't contain them (e.g. plain meats, oils).
        8. Meal-level `fiber` and `sugarAlcohols` should equal the sum of the corresponding ingredient fields.
        9. Return only the JSON object — no commentary.

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

    private static func parseMealAnalysisJSON(_ raw: String) throws -> MealAnalysis {
        // GPT occasionally wraps JSON in ```json fences or prose — extract the
        // outermost {...} block before decoding.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let start = trimmed.firstIndex(of: "{"),
            let end = trimmed.lastIndex(of: "}"),
            start <= end
        else {
            throw MealAnalysisError.parsingFailed("no JSON object found")
        }

        let jsonSlice = String(trimmed[start...end])
        guard let data = jsonSlice.data(using: .utf8) else {
            throw MealAnalysisError.parsingFailed("invalid UTF-8")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw MealAnalysisError.parsingFailed("JSON deserialization failed: \(error.localizedDescription)")
        }

        guard let dict = object as? [String: Any] else {
            throw MealAnalysisError.parsingFailed("root is not an object")
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
            ingredients = rawIngredients.compactMap { item in
                let iname = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !iname.isEmpty else { return nil }
                return MealAnalysisIngredient(
                    name: iname,
                    quantity: (item["quantity"] as? String) ?? "",
                    calories: intValue(item["calories"]),
                    protein: intValue(item["protein"]),
                    carbs: intValue(item["carbs"]),
                    fat: intValue(item["fat"]),
                    fiber: optionalIntValue(item["fiber"]),
                    sugarAlcohols: optionalIntValue(item["sugarAlcohols"])
                )
            }
        }

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
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
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

        If the user's input is a meal plan screenshot/image, do your best to transcribe the exact meals and their macros before you suggest anything. Do not invent meals that aren't present in the image. If you have to infer calories or macros for an image item, note that in the meal's `notes` field.

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
                    print("[Macra][Nora.analyzeMacros] ❌ parse error: \(error.localizedDescription)")
                    completion(.failure(error))
                }

            case .failure(let error):
                print("[Macra][Nora.analyzeMacros] ❌ bridge error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    private static func parseNoraAnalysisJSON(_ raw: String) throws -> NoraMacroAnalysis {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let start = trimmed.firstIndex(of: "{"),
            let end = trimmed.lastIndex(of: "}"),
            start <= end
        else {
            throw NoraMacroAnalysisError.parsingFailed("no JSON object found")
        }
        let jsonSlice = String(trimmed[start...end])
        guard let data = jsonSlice.data(using: .utf8) else {
            throw NoraMacroAnalysisError.parsingFailed("invalid UTF-8")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw NoraMacroAnalysisError.parsingFailed("JSON deserialize failed: \(error.localizedDescription)")
        }

        guard let dict = object as? [String: Any] else {
            throw NoraMacroAnalysisError.parsingFailed("root is not an object")
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

        let planDict = dict["mealPlan"] as? [String: Any] ?? [:]
        let planName = ((planDict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? "Nora's plan"

        let rawMeals = planDict["meals"] as? [[String: Any]] ?? []
        let meals: [NoraMacroAnalysis.PlanMeal] = rawMeals.enumerated().map { index, mealDict in
            let title = (mealDict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (mealDict["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawItems = mealDict["items"] as? [[String: Any]] ?? []
            let items: [NoraMacroAnalysis.PlanItem] = rawItems.compactMap { item in
                let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { return nil }
                return NoraMacroAnalysis.PlanItem(
                    name: name,
                    quantity: (item["quantity"] as? String) ?? "",
                    calories: intValue(item["calories"]),
                    protein: intValue(item["protein"]),
                    carbs: intValue(item["carbs"]),
                    fat: intValue(item["fat"])
                )
            }
            return NoraMacroAnalysis.PlanMeal(
                title: (title?.isEmpty == false ? title! : "Meal \(index + 1)"),
                notes: notes?.isEmpty == false ? notes : nil,
                items: items
            )
        }

        return NoraMacroAnalysis(
            summary: summary,
            macros: macros,
            planName: planName,
            meals: meals
        )
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
