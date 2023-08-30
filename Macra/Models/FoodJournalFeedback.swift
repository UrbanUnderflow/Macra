//
//  FoodJournalFeedback.swift
//  FoodJournal
//
//  Created by Tremaine Grant on 8/29/23.
//

import Foundation

struct FoodJournalFeedback {
    let id: String
    let calories: String
    let carbs: String
    let protein: String
    let fat: String
    let foodEvaluation: String
    let personalizedFeedback: String
    let unhealthyItems: String
    let score: Int
    let sentiment: String
    let journalEntry:String
    
    init(id: String, calories: String, carbs: String, protein: String, fat: String, foodEvaluation: String, personalizedFeedback: String, unhealthyItems: String, score: Int, sentiment: String, journalEntry: String) {
        self.id = id
        self.calories = calories
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
        self.foodEvaluation = foodEvaluation
        self.personalizedFeedback = personalizedFeedback
        self.unhealthyItems = unhealthyItems
        self.score = score
        self.sentiment = sentiment
        self.journalEntry = journalEntry
    }
    
    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let calories = dictionary["calories"] as? String,
              let carbs = dictionary["carbs"] as? String,
              let protein = dictionary["protein"] as? String,
              let fat = dictionary["fat"] as? String,
              let foodEvaluation = dictionary["foodEvaluation"] as? String,
              let personalizedFeedbackData = dictionary["personalizedFeedback"] as? String,
              let unhealthyItems = dictionary["unhealthyItems"] as? String,
              let score = dictionary["score"] as? Int,
              let sentiment = dictionary["sentiment"] as? String,
              let journalEntry = dictionary["journalEntry"] as? String
        else {
            return nil
        }
        
        do {
            self.id = id
            self.calories = calories
            self.carbs = carbs
            self.protein = protein
            self.fat = fat
            self.foodEvaluation = foodEvaluation
            self.personalizedFeedback = personalizedFeedbackData
            self.unhealthyItems = unhealthyItems
            self.score = score
            self.sentiment = sentiment
            self.journalEntry = journalEntry
        } catch {
            print("Error initializing JournalFeedback: \(error)")
            return nil
        }
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "calories": calories,
            "carbs": carbs,
            "protein": protein,
            "fat": fat,
            "foodEvaluation": foodEvaluation,
            "personalizedFeedback": personalizedFeedback,
            "unhealthyItems": unhealthyItems,
            "score": score,
            "sentiment": sentiment,
            "journalEntry": journalEntry,
        ]
    }
}

