//
//  EntryAssessment.swift
//  FoodJournal
//
//  Created by Tremaine Grant on 8/29/23.
//

import Foundation

struct Entry {
    let id: String
    let text: String
    let sentiment: String
    let sentimentScore: Int
    let aiFeedback: String
    let createdAt: Date
    let updatedAt: Date
    
    init(id: String, text: String, sentiment: String, sentimentScore: Int, aiFeedback: String, createdAt: Date, updatedAt: Date ) {
        self.id = id
        self.text = text
        self.sentiment = sentiment
        self.sentimentScore = sentimentScore
        self.aiFeedback = aiFeedback
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    init(dictionary: [String: Any]) {
        self.id = dictionary["id"] as? String ?? ""
        self.text = dictionary["text"] as? String ?? ""
        self.sentiment = dictionary["sentiment"] as? String ?? "neutral"
        self.sentimentScore = dictionary["sentimentScore"] as? Int ?? 0
        self.aiFeedback = dictionary["aiFeedback"] as? String ?? ""
        
        let createdAtStamp = dictionary["createdAt"] as? CGFloat ?? 0.0
        let updatedAtStamp = dictionary["updatedAt"] as? CGFloat ?? 0.0
        
        self.createdAt = Date(timeIntervalSince1970: createdAtStamp)
        self.updatedAt = Date(timeIntervalSince1970: updatedAtStamp)
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "text": text,
            "sentiment": sentiment,
            "sentimentScore": sentimentScore,
            "aiFeedback": aiFeedback,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
    }
}

