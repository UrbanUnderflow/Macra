import Foundation
import UIKit

final class MacraFoodJournalInsightService {
    static let shared = MacraFoodJournalInsightService()

    enum InsightError: LocalizedError {
        case emptyInput
        case parseFailure(String)

        var errorDescription: String? {
            switch self {
            case .emptyInput: return "No meals logged — add a meal first."
            case .parseFailure(let raw): return "Couldn't parse insight: \(raw.prefix(180))"
            }
        }
    }

    private init() {}

    func generateInsight(
        meals: [MacraFoodJournalMeal],
        supplements: [LoggedSupplement],
        macroTarget: MacraFoodJournalMacroTarget?,
        date: Date,
        completion: @escaping (Result<MacraFoodJournalDailyInsight, Error>) -> Void
    ) {
        guard !meals.isEmpty || supplements.contains(where: { $0.hasMacroContribution }) else {
            completion(.failure(InsightError.emptyInput))
            return
        }

        let mealLines = meals.map { meal -> String in
            let time = meal.createdAt.formatted(date: .omitted, time: .shortened)
            let fiber = meal.fiber.map { " fiber:\($0)g" } ?? ""
            let alcohols = meal.sugarAlcohols.map { " sugarAlcohols:\($0)g" } ?? ""
            return "- [\(time)] \(meal.name): \(meal.calories)kcal P\(meal.protein)g C\(meal.carbs)g F\(meal.fat)g\(fiber)\(alcohols)"
        }.joined(separator: "\n")

        let supplementLines = supplements.filter(\.hasMacroContribution).map { supp -> String in
            "- \(supp.name): \(supp.calories)kcal P\(supp.protein)g C\(supp.carbs)g F\(supp.fat)g"
        }.joined(separator: "\n")

        let totalCalories = meals.reduce(0) { $0 + $1.calories } + supplements.reduce(0) { $0 + $1.calories }
        let totalProtein = meals.reduce(0) { $0 + $1.protein } + supplements.reduce(0) { $0 + $1.protein }
        let totalCarbs = meals.reduce(0) { $0 + $1.carbs } + supplements.reduce(0) { $0 + $1.carbs }
        let totalFat = meals.reduce(0) { $0 + $1.fat } + supplements.reduce(0) { $0 + $1.fat }

        let targetBlock: String
        if let macroTarget {
            targetBlock = "Target: \(macroTarget.calories)kcal P\(macroTarget.protein)g C\(macroTarget.carbs)g F\(macroTarget.fat)g"
        } else {
            targetBlock = "No macro target set."
        }

        let systemPrompt = """
        You are Nora, Macra's nutrition coach. You give the user one short, specific insight about the day's eating based on the meals and supplements they logged. Focus on the single most useful observation — protein adequacy, macro balance, meal timing, fiber density, net-carb impact, or an obvious gap — and give one concrete, kind suggestion the user can act on.

        Return ONLY valid JSON matching this schema exactly — no markdown, no prose:

        {
          "title": "short headline (under 42 chars)",
          "response": "1–3 sentence insight. Lead with the observation; finish with the suggestion.",
          "icon": "SF Symbol name (e.g. 'bolt.fill', 'leaf.fill', 'flame.fill', 'fork.knife', 'chart.line.uptrend.xyaxis', 'drop.fill')"
        }

        Rules:
        - Be specific to the data, not generic. Reference a number or a meal name.
        - Never say "meal 1/2/3"; refer to meals by the name they logged.
        - Don't moralize; no "good"/"bad" framing. Neutral and useful.
        - Keep response under 280 chars.
        """

        let dayLabel = date.formatted(date: .long, time: .omitted)
        let userText = """
        Date: \(dayLabel)
        \(targetBlock)
        Totals: \(totalCalories)kcal P\(totalProtein)g C\(totalCarbs)g F\(totalFat)g

        Meals logged:
        \(mealLines.isEmpty ? "(none)" : mealLines)

        Supplements with macros:
        \(supplementLines.isEmpty ? "(none)" : supplementLines)
        """

        MacraOpenAIBridge.postChat(
            messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ],
            model: "gpt-4o-mini",
            maxTokens: 400,
            temperature: 0.4,
            responseFormat: ["type": "json_object"],
            organization: "macraDailyInsight"
        ) { result in
            switch result {
            case .success(let raw):
                do {
                    let insight = try Self.parseInsight(raw, date: date)
                    completion(.success(insight))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func parseInsight(_ raw: String, date: Date) throws -> MacraFoodJournalDailyInsight {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InsightError.parseFailure(trimmed)
        }
        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Today's insight"
        let response = (json["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let icon = (json["icon"] as? String) ?? "sparkles"
        guard !response.isEmpty else {
            throw InsightError.parseFailure(trimmed)
        }
        return MacraFoodJournalDailyInsight(
            id: UUID().uuidString,
            title: title,
            response: response,
            query: "",
            icon: icon,
            timestamp: date
        )
    }
}
