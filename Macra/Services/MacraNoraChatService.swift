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

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.noraChatCollection)
            .document(message.id)
            .setData(message.toDictionary()) { error in
                if let error {
                    print("[Macra][NoraChatService.save] ❌ \(message.id) → \(error.localizedDescription)")
                    completion?(.failure(error))
                } else {
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
                let messages = (snapshot?.documents.compactMap {
                    MacraNoraMessage(id: $0.documentID, dictionary: $0.data())
                } ?? []).sorted { $0.timestamp < $1.timestamp }
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
