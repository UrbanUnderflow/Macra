import Foundation
import OpenAISwift

class GPTService {
    static let sharedInstance = GPTService()
    static let testing = true

    private let authToken: String = "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"
    
    private let openAI: OpenAISwift
    
    private let model: OpenAIModelType = .gpt4(.gpt4)
    
    private init() {
        openAI = OpenAISwift(config: .makeDefaultOpenAI(apiKey: authToken))
    }

    func analyzeFood(_ foodEntry: String, completion: @escaping (Result<FoodJournalFeedback, Error>) -> Void) {
            let fetchedPrompt = "Imagine you are a certified nutritionist and personal trainer. Analyze a given food journal entry, estimating the overall caloric intake and macronutrient breakdown. Identify any potentially unhealthy or harmful food items and offer healthier alternatives. Consider the user's stated goal and provide personalized feedback based on that goal. Lastly, if there are any unhealthy or harmful ingredients, suggest healthier alternatives.  To provide more consistent results, the macronutrient analysis will use standard macronutrient values for common food categories. Since precise portion sizes are not specified, the macronutrient values will be given as a range within 20 grams to give the user a better understanding of the ballpark figures.   Structure your response in the following format:  - Total Calories: [calorie range] - Carbohydrates: [carb range] grams - Protein: [protein range] grams - Fat: [fat range] grams - Food Evaluation: [Comment on the healthiness of each food item, noting any potential issues] - Personalized Feedback: [Provide insights and recommendations based on the user's goal] - Unhealthy/Harmful Ingredients: [Identify any unhealthy or potentially harmful ingredients, if any, and suggest healthier alternatives] - Sentiment Score: [Provide a sentiment score (0-100)] - Sentiment: [Provide an overall sentiment analysis (positive, neutral, or negative)]  With this prompt, you can expect a response that includes the requested structure for analyzing the food journal entry, evaluating the healthiness of the food items, providing personalized feedback based on the user's goal, identifying and suggesting alternatives for any unhealthy or harmful ingredients, and the macronutrient analysis with narrower ranges for the values.   With this in mind, analyze the following journal entry: \"\(foodEntry)\""
                let prompt = fetchedPrompt.replacingOccurrences(of: "foodEntry", with: foodEntry)
                let temperature: Double = 0.2
                let maxTokens = 1500

                self.openAI.sendCompletion(with: prompt, model: self.model, maxTokens: maxTokens, temperature: temperature) { result in
                    switch result {
                        case .success(let response):
                        if let bestCompletion = response.choices?.first {
                            let analysis = self.parseDietAnalysisResponse(bestCompletion.text)
                            
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
                            
                            completion(.success(feedback))
                        } else {
                            completion(.failure(NSError(domain: "No completions found", code: -1, userInfo: nil)))
                        }
                    case .failure(let error):
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
}

