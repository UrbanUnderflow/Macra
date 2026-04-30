import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Persists the per-date Ask Nora thread. One Firestore doc per message so
/// threads rebuild chronologically from the `timestamp` field, and so we can
/// query a single day cheaply via the denormalized `dayKey`.
///
/// Path: `users/{uid}/noraChat/{messageId}`
final class MacraNoraChatService {
    static let sharedInstance = MacraNoraChatService()

    private let db: Firestore

    private init() {
        self.db = Firestore.firestore()
    }

    /// Persists a single message. The caller should save both the user and
    /// assistant messages as they're produced so a mid-turn network failure
    /// still leaves the user's question recoverable.
    func saveMessage(
        _ message: MacraNoraMessage,
        userId: String? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion?(.failure(NutritionCoreError.missingUserId))
            return
        }

        print("[Macra][Nora][FIRESTORE-SAVE] uid=\(resolvedUserId) msgId=\(message.id) dayKey=\(message.dayKey) role=\(message.role.rawValue) ts=\(message.timestamp)")
        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.noraChatCollection)
            .document(message.id)
            .setData(message.toDictionary()) { error in
                if let error {
                    print("[Macra][NoraChatService.save] ❌ \(message.id) → \(error.localizedDescription)")
                    completion?(.failure(error))
                } else {
                    print("[Macra][Nora][FIRESTORE-SAVE-OK] msgId=\(message.id) dayKey=\(message.dayKey)")
                    completion?(.success(()))
                }
            }
    }

    /// Loads every message for the given day, sorted chronologically.
    func loadMessages(
        for date: Date,
        userId: String? = nil,
        completion: @escaping (Result<[MacraNoraMessage], Error>) -> Void
    ) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let dayKey = date.macraFoodJournalDayKey
        print("[Macra][Nora][FIRESTORE-LOAD-START] uid=\(resolvedUserId) requestedDate=\(date) requestedDayKey=\(dayKey)")
        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.noraChatCollection)
            .whereField("dayKey", isEqualTo: dayKey)
            .getDocuments { snapshot, error in
                if let error {
                    print("[Macra][NoraChatService.load] ❌ dayKey:\(dayKey) → \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                let rawDocs = snapshot?.documents ?? []
                print("[Macra][Nora][FIRESTORE-LOAD-RAW] requestedDayKey=\(dayKey) docCount=\(rawDocs.count)")
                for doc in rawDocs {
                    let data = doc.data()
                    let storedDayKey = data["dayKey"] as? String ?? "<missing>"
                    let storedRole = data["role"] as? String ?? "<missing>"
                    let storedTs: String = {
                        if let ts = data["timestamp"] as? Double {
                            return "\(Date(timeIntervalSince1970: ts))"
                        }
                        if let ts = data["timestamp"] as? Timestamp {
                            return "\(ts.dateValue())"
                        }
                        return "<missing>"
                    }()
                    let preview = (data["content"] as? String).map { String($0.prefix(40)) } ?? "<missing>"
                    print("[Macra][Nora][FIRESTORE-LOAD-DOC] id=\(doc.documentID) storedDayKey=\(storedDayKey) role=\(storedRole) ts=\(storedTs) preview=\(preview)")
                }
                let messages = (rawDocs.compactMap {
                    MacraNoraMessage(id: $0.documentID, dictionary: $0.data())
                }).sorted { $0.timestamp < $1.timestamp }
                print("[Macra][Nora][FIRESTORE-LOAD-OK] requestedDayKey=\(dayKey) parsedCount=\(messages.count)")
                completion(.success(messages))
            }
    }

    /// Removes a message (e.g. the user wants to clear a turn).
    func deleteMessage(
        id: String,
        userId: String? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion?(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.noraChatCollection)
            .document(id)
            .delete { error in
                if let error {
                    completion?(.failure(error))
                } else {
                    completion?(.success(()))
                }
            }
    }
}
