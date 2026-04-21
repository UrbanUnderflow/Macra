import Foundation
import UIKit

final class LabelSupplementsAIService {
    static let shared = LabelSupplementsAIService()

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Label grading

    func gradeNutritionLabel(image: UIImage, completion: @escaping (Result<LabelGradeResult, Error>) -> Void) {
        guard let base64Image = image.toBase64() else {
            completion(.success(LabelGradeResult(
                grade: "?",
                flaggedIngredients: [],
                summary: "Unable to process image",
                detailedExplanation: "The image could not be converted for analysis. Please try taking a new photo with better lighting.",
                confidence: 0.0,
                concerns: [],
                sources: [],
                errorCode: "LABEL-005",
                errorDetails: "Image to base64 conversion failed. Image may be corrupted or in unsupported format.",
                errorCategory: "image"
            )))
            return
        }

        let prompt = """
        CRITICAL: You MUST analyze the nutrition label image provided and return ONLY valid JSON. Do not provide any explanatory text, markdown, or code blocks. Return ONLY the JSON object.

        You are analyzing a nutrition facts label image. Look at the ENTIRE image carefully and extract:
        - The EXACT product name as shown on the package
        - The nutrition facts panel (calories, macros, vitamins, minerals)
        - The ingredients list
        - Any health claims or certifications

        Based on what you see in the image, provide a letter grade (A-F) and detailed analysis.

        GRADING CRITERIA:
        - Grade A: Whole food ingredients, no artificial additives, low added sugars (<5% DV), low sodium (<5% DV)
        - Grade B: Mostly whole foods, minimal processing, low added sugars (<10% DV), moderate sodium (<10% DV)
        - Grade C: Mix of whole and processed ingredients, moderate added sugars (10-20% DV), some concerning additives
        - Grade D: Heavily processed, high added sugars (>20% DV), high sodium (>20% DV), multiple concerning additives
        - Grade F: Ultra-processed, excessive added sugars/sodium, harmful additives, trans fats

        INGREDIENTS TO FLAG: Artificial sweeteners, artificial colors, preservatives (BHA, BHT), inflammatory oils, high fructose corn syrup, MSG, sodium nitrite/nitrate.

        RETURN ONLY THIS JSON STRUCTURE (no other text):
        {
          "productTitle": "Exact product name as printed on the package or null",
          "grade": "A" | "B" | "C" | "D" | "F",
          "confidence": 0.0_to_1.0,
          "calories": number_or_null,
          "protein": number_or_null,
          "fat": number_or_null,
          "carbs": number_or_null,
          "servingSize": "string or null",
          "sugars": number_or_null,
          "dietaryFiber": number_or_null,
          "sugarAlcohols": number_or_null,
          "sodium": number_or_null,
          "summary": "Brief 1-2 sentence summary",
          "detailedExplanation": "3-5 sentence explanation referencing specific ingredients and values from the label",
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
              "relevance": "How this source supports the analysis"
            }
          ]
        }
        """

        sendVisionCompletion(prompt: prompt, base64Image: base64Image, maxTokens: 2000, temperature: 0.1) { [weak self] result in
            switch result {
            case .success(let responseText):
                let gradeResult = self?.parseLabelGradeResponse(responseText) ?? LabelGradeResult(
                    grade: "?",
                    flaggedIngredients: [],
                    summary: "Analysis unavailable",
                    detailedExplanation: "The AI service returned no result.",
                    confidence: 0.0,
                    concerns: [],
                    sources: [],
                    errorCode: "LABEL-004",
                    errorDetails: "Missing response content",
                    errorCategory: "api"
                )
                completion(.success(gradeResult))
            case .failure(let error):
                completion(.success(self?.errorLabelResult(for: error) ?? LabelGradeResult(
                    grade: "?",
                    flaggedIngredients: [],
                    summary: "Analysis service unavailable",
                    detailedExplanation: error.localizedDescription,
                    confidence: 0.0,
                    concerns: [],
                    sources: [],
                    errorCode: "LABEL-004",
                    errorDetails: error.localizedDescription,
                    errorCategory: "api"
                )))
            }
        }
    }

    // MARK: - Label macros

    func parseMacrosFromLabelImage(image: UIImage, completion: @escaping (Result<LabelNutritionFacts, Error>) -> Void) {
        guard let base64Image = image.toBase64() else {
            completion(.failure(NSError(domain: "LabelSupplementsAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to base64"])))
            return
        }

        let prompt = """
        Look at this nutrition label image and extract ONLY the nutrition facts.
        TRANSCRIBE THE EXACT NUMBERS you see on the label. Do not infer or guess; if a digit is unclear, use null for that field.
        Return a JSON object with these keys (use numbers only; use null if not visible):
        - calories
        - protein
        - fat
        - carbs
        - servingSize
        - sugars
        - dietaryFiber
        - sugarAlcohols (grams — found on "sugar free" / "keto" / "low carb" products; list as-is. Common sources: erythritol, xylitol, maltitol, sorbitol, allulose, monk fruit blends like Lakanto. Use null only if truly not on the label)
        - sodium
        Return ONLY the JSON object, no other text.
        """

        sendVisionCompletion(prompt: prompt, base64Image: base64Image, maxTokens: 500, temperature: 0.1) { [weak self] result in
            switch result {
            case .success(let responseText):
                let facts = self?.parseMacrosResponse(responseText) ?? LabelNutritionFacts(calories: nil, protein: nil, fat: nil, carbs: nil, servingSize: nil, sugars: nil, dietaryFiber: nil, sugarAlcohols: nil, sodium: nil)
                completion(.success(facts))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Supplement analysis

    func analyzeSupplementLabel(image: UIImage, completion: @escaping (Result<LoggedSupplement, Error>) -> Void) {
        guard let base64Image = image.toBase64() else {
            completion(.failure(NSError(domain: "LabelSupplementsAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to convert image to base64"])))
            return
        }

        let prompt = """
        Analyze this image of a supplement bottle, label, or container. Extract the relevant information to build a supplement log entry.
        Return ONLY a JSON object with the following exact structure:
        {
          "name": "full product name",
          "brand": "brand name if visible, else empty string",
          "form": "capsule, tablet, powder, softgel, liquid, or other",
          "dosage": numeric_amount_per_serving,
          "unit": "capsule(s), mg, g, scoop(s), etc",
          "calories": numeric_or_0,
          "protein": numeric_grams_or_0,
          "carbs": numeric_grams_or_0,
          "fat": numeric_grams_or_0
        }
        """

        sendVisionCompletion(prompt: prompt, base64Image: base64Image, maxTokens: 500, temperature: 0.1) { [weak self] result in
            switch result {
            case .success(let responseText):
                let jsonString = self?.extractJSONFromResponse(responseText) ?? responseText
                guard let data = jsonString.data(using: .utf8),
                      let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    completion(.failure(NSError(domain: "LabelSupplementsAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])))
                    return
                }

                var supplement = LoggedSupplement(
                    id: UUID().uuidString,
                    name: dict["name"] as? String ?? "Unknown Supplement",
                    form: dict["form"] as? String ?? "capsule",
                    dosage: dict["dosage"] as? Double ?? Double(dict["dosage"] as? Int ?? 1),
                    unit: dict["unit"] as? String ?? "capsule(s)",
                    brand: dict["brand"] as? String ?? "",
                    notes: "",
                    calories: dict["calories"] as? Int ?? 0,
                    protein: dict["protein"] as? Int ?? 0,
                    carbs: dict["carbs"] as? Int ?? 0,
                    fat: dict["fat"] as? Int ?? 0,
                    imageUrl: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                supplement.inferMicronutrients()
                completion(.success(supplement))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func refineSupplementDetails(
        supplementName: String,
        imageUrl: String?,
        correctionPrompt: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let userContext = correctionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let correctionInstruction = userContext.isEmpty ? "" : "\n\nIMPORTANT USER CORRECTION: \"\(userContext)\""
        let prompt = """
        You are re-analyzing a supplement called "\(supplementName)".\(correctionInstruction)

        Return a JSON object with:
        {
          "name": "corrected full product name",
          "brand": "brand name or empty string",
          "form": "capsule | tablet | powder | softgel | liquid | other",
          "dosage": numeric_serving_amount,
          "unit": "capsule(s) | tablet(s) | scoop(s) | mg | g | mcg | IU | mL | drop(s)",
          "calories": numeric_or_0,
          "protein": numeric_grams_or_0,
          "carbs": numeric_grams_or_0,
          "fat": numeric_grams_or_0,
          "vitamins": {"Vitamin Name": amount_in_mcg, ...},
          "minerals": {"Mineral Name": amount_in_mg, ...},
          "notes": "any helpful usage notes"
        }
        Return ONLY the JSON object.
        """

        if let imageUrl, !imageUrl.isEmpty, let url = URL(string: imageUrl), let imageData = try? Data(contentsOf: url), let image = UIImage(data: imageData), let base64 = image.toBase64() {
            sendVisionCompletion(prompt: prompt, base64Image: base64, maxTokens: 800, temperature: 0.2) { [weak self] result in
                self?.handleRefineResult(result, completion: completion)
            }
        } else {
            sendTextCompletion(prompt: prompt, maxTokens: 800, temperature: 0.2) { [weak self] result in
                self?.handleRefineResult(result, completion: completion)
            }
        }
    }

    // MARK: - Label Q&A / deep dive / alternatives

    func askLabelQuestion(
        gradeResult: LabelGradeResult,
        question: String,
        conversationHistory: [LabelQAMessage],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let systemPrompt = """
        You are a nutrition expert assistant helping users understand a scanned nutrition label.

        CONTEXT - Previous Analysis:
        - Grade: \(gradeResult.grade)
        - Summary: \(gradeResult.summary)
        - Detailed Analysis: \(gradeResult.detailedExplanation)
        - Flagged Ingredients: \(gradeResult.flaggedIngredients.joined(separator: ", "))
        - Concerns: \(gradeResult.concerns.map { "\($0.concern) (\($0.severity) severity)" }.joined(separator: "; "))

        INSTRUCTIONS:
        - Answer questions based on the analysis above
        - Be helpful, clear, and evidence-based
        - If asked about health conditions, provide general guidance but recommend consulting healthcare providers
        - Keep responses concise but comprehensive (2-4 paragraphs max)
        - Use simple language that anyone can understand
        - If you don't have enough information from the analysis, say so clearly
        """

        var messages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        for message in conversationHistory.suffix(10) {
            messages.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }
        messages.append(["role": "user", "content": question])

        sendChatCompletion(messages: messages, model: "gpt-4o", maxTokens: 1000, temperature: 0.7) { result in
            switch result {
            case .success(let content):
                completion(.success(content))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func deepDiveLabelAnalysis(
        gradeResult: LabelGradeResult,
        completion: @escaping (Result<LabelDeepDiveResult, Error>) -> Void
    ) {
        let prompt = """
        Based on the following nutrition label analysis, provide a comprehensive deep dive research report.

        ORIGINAL ANALYSIS:
        - Grade: \(gradeResult.grade)
        - Summary: \(gradeResult.summary)
        - Detailed Explanation: \(gradeResult.detailedExplanation)
        - Flagged Ingredients: \(gradeResult.flaggedIngredients.joined(separator: ", "))
        - Concerns: \(gradeResult.concerns.map { "\($0.concern): \($0.scientificReason)" }.joined(separator: "; "))

        REQUIRED: You MUST include "productTitle". From the summary and detailed explanation above, extract or infer the full product name.

        PROVIDE THE FOLLOWING IN JSON FORMAT:
        {
            "productTitle": "Full product name or descriptive type",
            "longTermEffects": [{ "effect": "", "description": "", "severity": "low|medium|high", "timeframe": "short-term|long-term|cumulative", "relatedIngredients": [] }],
            "nutritionalBreakdown": {
                "macroAnalysis": "",
                "micronutrientNotes": "",
                "calorieContext": "",
                "portionGuidance": ""
            },
            "researchFindings": [{ "title": "", "summary": "", "source": "", "year": "2024", "relevance": "" }],
            "regulatoryStatus": {
                "fdaStatus": "",
                "whoGuidance": "",
                "bannedIn": [],
                "warnings": []
            }
        }
        Return ONLY valid JSON, no other text.
        """

        sendChatCompletion(
            messages: [
                ["role": "system", "content": "You are a nutrition research expert. Return ONLY valid JSON with no additional text or markdown."],
                ["role": "user", "content": prompt]
            ],
            model: "gpt-4o",
            maxTokens: 2500,
            temperature: 0.3
        ) { [weak self] result in
            switch result {
            case .success(let content):
                let jsonString = self?.extractJSONFromResponse(content) ?? content
                guard let data = jsonString.data(using: .utf8),
                      let jsonObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    completion(.failure(NSError(domain: "LabelSupplementsAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse deep dive response"])))
                    return
                }
                completion(.success(LabelDeepDiveResult(from: jsonObject)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func inferProductTitle(
        gradeResult: LabelGradeResult,
        imageBase64: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        if let imageBase64, !imageBase64.isEmpty {
            let prompt = """
            Look at this nutrition label / product package image. Your task is to identify the EXACT product name as it appears on the package.
            Return ONLY valid JSON with no other text: {"productTitle": "Exact product name as shown on package"}
            If no product name is visible in the image, return: {"productTitle": null}
            """
            sendVisionCompletion(prompt: prompt, base64Image: imageBase64, maxTokens: 200, temperature: 0.1) { [weak self] result in
                switch result {
                case .success(let responseText):
                    let jsonString = self?.extractJSONFromResponse(responseText) ?? responseText
                    if let data = jsonString.data(using: .utf8),
                       let jsonObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                       let title = jsonObject["productTitle"] as? String,
                       !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        completion(.success(title.trimmingCharacters(in: .whitespacesAndNewlines)))
                    } else {
                        completion(.failure(NSError(domain: "LabelSupplementsAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No productTitle in response"])))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } else {
            let prompt = """
            From the nutrition label analysis below, determine the ACTUAL product name. Use every clue: summary, detailed explanation, flagged ingredients, and concerns. Prefer the exact product name if mentioned; otherwise a specific product type.
            Return ONLY valid JSON: {"productTitle": "Product name here"}

            Summary: \(gradeResult.summary)
            Detailed: \(gradeResult.detailedExplanation)
            Flagged: \(gradeResult.flaggedIngredients.prefix(5).joined(separator: ", "))
            Concerns: \(gradeResult.concerns.map { $0.concern }.prefix(3).joined(separator: ", "))
            """
            sendTextCompletion(prompt: prompt, maxTokens: 150, temperature: 0.3) { [weak self] result in
                switch result {
                case .success(let responseText):
                    let jsonString = self?.extractJSONFromResponse(responseText) ?? responseText
                    if let data = jsonString.data(using: .utf8),
                       let jsonObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                       let title = jsonObject["productTitle"] as? String,
                       !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        completion(.success(title.trimmingCharacters(in: .whitespacesAndNewlines)))
                    } else {
                        completion(.failure(NSError(domain: "LabelSupplementsAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No productTitle in response"])))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func findHealthierAlternatives(
        gradeResult: LabelGradeResult,
        completion: @escaping (Result<([HealthierAlternative], productTitle: String?), Error>) -> Void
    ) {
        let prompt = """
        Based on the following nutrition label analysis, recommend healthier alternatives.

        ORIGINAL PRODUCT ANALYSIS:
        - Grade: \(gradeResult.grade)
        - Summary: \(gradeResult.summary)
        - Issues: \(gradeResult.detailedExplanation)
        - Flagged Ingredients: \(gradeResult.flaggedIngredients.joined(separator: ", "))
        - Key Concerns: \(gradeResult.concerns.map { $0.concern }.joined(separator: ", "))

        If you know the original product name from context, include it as "productTitle" at the top level.
        For each alternative, when possible include "productUrl": "https://www.amazon.com/..." so users can find it.

        PROVIDE 3-5 HEALTHIER ALTERNATIVES IN JSON FORMAT:
        {
            "productTitle": "Original product name if identifiable, or null",
            "alternatives": [
                {
                    "name": "Specific product or brand name",
                    "reason": "Why this is a healthier choice",
                    "grade": "Expected grade (A or B)",
                    "improvements": ["Specific improvement 1", "Specific improvement 2"],
                    "whereToFind": "Where to purchase",
                    "category": "Product category",
                    "productUrl": "https://www.amazon.com/dp/ASIN or Amazon search URL if known, or null"
                }
            ]
        }
        Return ONLY valid JSON, no other text.
        """

        sendChatCompletion(
            messages: [
                ["role": "system", "content": "You are a nutrition expert helping people find healthier food alternatives. Return ONLY valid JSON with no additional text or markdown."],
                ["role": "user", "content": prompt]
            ],
            model: "gpt-4o",
            maxTokens: 1500,
            temperature: 0.5
        ) { [weak self] result in
            switch result {
            case .success(let content):
                let jsonString = self?.extractJSONFromResponse(content) ?? content
                guard let data = jsonString.data(using: .utf8),
                      let jsonObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let alternativesArray = jsonObject["alternatives"] as? [[String: Any]] else {
                    completion(.failure(NSError(domain: "LabelSupplementsAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse alternatives response"])))
                    return
                }
                let alternatives = alternativesArray.map { HealthierAlternative(from: $0) }
                let rawTitle = jsonObject["productTitle"] as? String
                let productTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rawTitle : nil
                completion(.success((alternatives, productTitle: productTitle)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Request helpers

    private func sendTextCompletion(prompt: String, maxTokens: Int, temperature: Double, completion: @escaping (Result<String, Error>) -> Void) {
        let messages: [[String: Any]] = [
            ["role": "system", "content": "Return only the requested JSON or plain answer, with no markdown unless asked."],
            ["role": "user", "content": prompt]
        ]
        sendChatCompletion(messages: messages, model: "gpt-4o", maxTokens: maxTokens, temperature: temperature, completion: completion)
    }

    private func sendVisionCompletion(prompt: String, base64Image: String, maxTokens: Int, temperature: Double, completion: @escaping (Result<String, Error>) -> Void) {
        let messages: [[String: Any]] = [
            [
                "role": "system",
                "content": "You are a precise nutrition and supplement analysis assistant. Return only what the user requested."
            ],
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                ]
            ]
        ]
        sendChatCompletion(messages: messages, model: "gpt-4o", maxTokens: maxTokens, temperature: temperature, completion: completion)
    }

    private func sendChatCompletion(
        messages: [[String: Any]],
        model: String,
        maxTokens: Int,
        temperature: Double,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Route every Label/Supplements call through the shared server bridge
        // instead of hitting api.openai.com directly — the real OpenAI key
        // lives on the server and the client only sends a Firebase ID token.
        MacraOpenAIBridge.postChat(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            responseFormat: nil,
            organization: "macraLabelSupplements",
            session: session,
            completion: completion
        )
    }

    // MARK: - Parsing helpers

    private func extractJSONFromResponse(_ response: String) -> String {
        guard let startIndex = response.firstIndex(of: "{"),
              let endIndex = response.lastIndex(of: "}") else {
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(response[startIndex...endIndex])
    }

    private func parseMacrosResponse(_ response: String) -> LabelNutritionFacts {
        let jsonString = extractJSONFromResponse(response)
        guard let data = jsonString.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return LabelNutritionFacts(calories: nil, protein: nil, fat: nil, carbs: nil, servingSize: nil, sugars: nil, dietaryFiber: nil, sugarAlcohols: nil, sodium: nil)
        }

        func intOrNil(_ key: String) -> Int? {
            if let value = object[key] as? Int { return value }
            if let value = object[key] as? Double { return Int(value) }
            return nil
        }

        let servingSize = (object["servingSize"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LabelNutritionFacts(
            calories: intOrNil("calories"),
            protein: intOrNil("protein"),
            fat: intOrNil("fat"),
            carbs: intOrNil("carbs"),
            servingSize: (servingSize?.isEmpty == false) ? servingSize : nil,
            sugars: intOrNil("sugars"),
            dietaryFiber: intOrNil("dietaryFiber"),
            sugarAlcohols: intOrNil("sugarAlcohols"),
            sodium: intOrNil("sodium")
        )
    }

    private func handleRefineResult(_ result: Result<String, Error>, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        switch result {
        case .success(let responseText):
            let jsonString = extractJSONFromResponse(responseText)
            guard let data = jsonString.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(.failure(NSError(domain: "LabelSupplementsAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse AI response"])))
                return
            }
            completion(.success(dict))
        case .failure(let error):
            completion(.failure(error))
        }
    }

    private func parseLabelGradeResponse(_ response: String) -> LabelGradeResult {
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedResponse.isEmpty {
            return LabelGradeResult(
                grade: "?",
                flaggedIngredients: [],
                summary: "Empty response from analysis service",
                detailedExplanation: "The analysis service returned an empty response.",
                confidence: 0.0,
                concerns: [],
                sources: [],
                errorCode: "LABEL-002",
                errorDetails: "Response was empty or contained only whitespace.",
                errorCategory: "parsing"
            )
        }

        let jsonString = extractJSONFromResponse(response)
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return LabelGradeResult(
                grade: "?",
                flaggedIngredients: [],
                summary: "Failed to parse analysis response",
                detailedExplanation: "The analysis service returned data that could not be parsed.",
                confidence: 0.0,
                concerns: [],
                sources: [],
                errorCode: "LABEL-002",
                errorDetails: "Unable to decode JSON from response.",
                errorCategory: "parsing"
            )
        }

        let sanitizedJson = sanitizeLabelGradeNutritionValues(jsonObject)
        var result = LabelGradeResult(from: sanitizedJson)
        if result.grade.isEmpty || (result.summary.isEmpty && result.detailedExplanation.isEmpty) {
            result = LabelGradeResult(
                grade: "?",
                flaggedIngredients: result.flaggedIngredients,
                summary: result.summary.isEmpty ? "Incomplete analysis data" : result.summary,
                detailedExplanation: result.detailedExplanation.isEmpty ? "The analysis returned incomplete data." : result.detailedExplanation,
                confidence: result.confidence,
                concerns: result.concerns,
                sources: result.sources,
                productTitle: result.productTitle,
                errorCode: "LABEL-001",
                errorDetails: "Grade or explanation was empty.",
                errorCategory: "parsing"
            )
        }
        return result
    }

    private static let kMaxCaloriesPerServing = 1000
    private static let kMaxProteinPerServing = 100
    private static let kMaxFatPerServing = 100
    private static let kMaxCarbsPerServing = 150
    private static let kMaxSugarsPerServing = 100
    private static let kMaxDietaryFiberPerServing = 15
    private static let kMaxSugarAlcoholsPerServing = 100
    private static let kMaxSodiumPerServing = 3000

    private func sanitizeNutritionInt(_ value: Int?, maxAllowed: Int) -> Int? {
        guard let value else { return nil }
        return value > maxAllowed ? nil : value
    }

    private func sanitizeLabelGradeNutritionValues(_ jsonObject: [String: Any]) -> [String: Any] {
        var copy = jsonObject
        copy["calories"] = sanitizeNutritionInt(intFromJson(copy["calories"]), maxAllowed: Self.kMaxCaloriesPerServing)
        copy["protein"] = sanitizeNutritionInt(intFromJson(copy["protein"]), maxAllowed: Self.kMaxProteinPerServing)
        copy["fat"] = sanitizeNutritionInt(intFromJson(copy["fat"]), maxAllowed: Self.kMaxFatPerServing)
        copy["carbs"] = sanitizeNutritionInt(intFromJson(copy["carbs"]), maxAllowed: Self.kMaxCarbsPerServing)
        copy["sugars"] = sanitizeNutritionInt(intFromJson(copy["sugars"]), maxAllowed: Self.kMaxSugarsPerServing)
        copy["dietaryFiber"] = sanitizeNutritionInt(intFromJson(copy["dietaryFiber"]), maxAllowed: Self.kMaxDietaryFiberPerServing)
        copy["sugarAlcohols"] = sanitizeNutritionInt(intFromJson(copy["sugarAlcohols"]), maxAllowed: Self.kMaxSugarAlcoholsPerServing)
        copy["sodium"] = sanitizeNutritionInt(intFromJson(copy["sodium"]), maxAllowed: Self.kMaxSodiumPerServing)
        return copy
    }

    private func intFromJson(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let stringValue = value as? String, let doubleValue = Double(stringValue) { return Int(doubleValue) }
        return nil
    }

    private func errorLabelResult(for error: Error) -> LabelGradeResult {
        let nsError = error as NSError
        let message = error.localizedDescription.lowercased()
        if nsError.domain.contains("network") || message.contains("network") || message.contains("internet") {
            return LabelGradeResult(
                grade: "?",
                flaggedIngredients: [],
                summary: "Network error",
                detailedExplanation: "Please check your internet connection and try again.",
                confidence: 0.0,
                concerns: [],
                sources: [],
                errorCode: "LABEL-003",
                errorDetails: error.localizedDescription,
                errorCategory: "network"
            )
        }
        if message.contains("rate limit") || message.contains("quota") || message.contains("timeout") {
            return LabelGradeResult(
                grade: "?",
                flaggedIngredients: [],
                summary: "Analysis service unavailable",
                detailedExplanation: "The analysis service took too long to respond.",
                confidence: 0.0,
                concerns: [],
                sources: [],
                errorCode: "LABEL-004",
                errorDetails: error.localizedDescription,
                errorCategory: "api"
            )
        }
        return LabelGradeResult(
            grade: "?",
            flaggedIngredients: [],
            summary: "Analysis service unavailable",
            detailedExplanation: error.localizedDescription,
            confidence: 0.0,
            concerns: [],
            sources: [],
            errorCode: "LABEL-004",
            errorDetails: error.localizedDescription,
            errorCategory: "api"
        )
    }
}
