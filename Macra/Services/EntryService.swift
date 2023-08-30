//
//  EntryService.swift
//  FoodJournal
//
//  Created by Tremaine Grant on 8/29/23.
//

import Foundation
import Firebase

class EntryService: ObservableObject {
    static let sharedInstance = EntryService()
    private var db: Firestore!
    
    @Published var entries: [Entry] = []
    
    private init() {
        db = Firestore.firestore()
    }
    
    func fetchEntries() {
        db.collection("entries").getDocuments { (querySnapshot, err) in
            if let err = err {
                print("Error getting logs: \(err)")
            } else {
                self.entries = querySnapshot?.documents.compactMap { document in
                    return Entry(dictionary: document.data())
                } ?? []
            }
        }
    }

    func logEntry(entry: FoodJournalFeedback, completion: @escaping (FoodJournalFeedback?, Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(nil, NSError(domain: "EntryService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let reference = db.collection("users").document(userId).collection("entry")
        
        reference.addDocument(data: entry.toDictionary()) { error in
            if let error = error {
                print("Error writing log to Firestore: \(error)")
                completion(nil, error)
            } else {
                completion(entry, nil)
            }
        }
    }
    
    func updateEntry(entry: FoodJournalFeedback, completion: @escaping (FoodJournalFeedback?, Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(nil, NSError(domain: "EntryService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let reference = db.collection("users").document(userId).collection("entry").document(entry.id)
        
        reference.updateData(entry.toDictionary()) { error in
            if let error = error {
                print("Error updating entry in Firestore: \(error)")
                completion(nil, error)
            } else {
                completion(entry, nil)
            }
        }
    }
}
