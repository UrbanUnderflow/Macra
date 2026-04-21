import Foundation
import FirebaseAuth
import FirebaseFirestore

final class SupplementService {
    static let sharedInstance = SupplementService()

    private let db: Firestore

    private init() {
        self.db = Firestore.firestore()
    }

    func saveSupplement(_ supplement: LoggedSupplement, completion: @escaping (Result<Void, Error>) -> Void) {
        saveSupplementToLibrary(supplement, completion: completion)
    }

    func saveSupplementToLibrary(_ supplement: LoggedSupplement, userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.savedSupplementsCollection)
            .document(supplement.id)
            .setData(supplement.toDictionary()) { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
    }

    func getSavedSupplements(userId: String? = nil, completion: @escaping (Result<[LoggedSupplement], Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.savedSupplementsCollection)
            .order(by: "createdAt", descending: false)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let supplements = snapshot?.documents.map { LoggedSupplement(id: $0.documentID, dictionary: $0.data()) } ?? []
                completion(.success(supplements.reversed()))
            }
    }

    func deleteSavedSupplement(withId supplementId: String, userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.savedSupplementsCollection)
            .document(supplementId)
            .delete { error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
    }

    func addLoggedSupplement(_ supplement: LoggedSupplement, date: Date = Date(), userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        var storedSupplement = supplement
        storedSupplement.createdAt = date
        storedSupplement.updatedAt = Date()

        let documentID = "\(date.dayMonthYearFormat)\(supplement.id)"
        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.supplementLogsCollection)
            .document(documentID)
            .setData(storedSupplement.toDictionary()) { error in
                if let error {
                    completion(.failure(error))
                    return
                }
                NotificationCenter.default.post(name: NutritionCoreNotification.dataDidChange, object: nil)
                completion(.success(()))
            }
    }

    func getLoggedSupplements(byDate date: Date, userId: String? = nil, completion: @escaping (Result<[LoggedSupplement], Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let calendar = Calendar.current
        guard let startOfDay = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date),
              let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) else {
            completion(.failure(NutritionCoreError.invalidPayload("Could not calculate date range for supplement lookup.")))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.supplementLogsCollection)
            .whereField("createdAt", isGreaterThanOrEqualTo: startOfDay.timeIntervalSince1970)
            .whereField("createdAt", isLessThanOrEqualTo: endOfDay.timeIntervalSince1970)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let supplements = snapshot?.documents
                    .map { LoggedSupplement(id: $0.documentID, dictionary: $0.data()) }
                    .sorted { $0.createdAt < $1.createdAt } ?? []
                completion(.success(supplements))
            }
    }

    func deleteLoggedSupplement(withId supplementId: String, userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.supplementLogsCollection)
            .document(supplementId)
            .delete { error in
                if let error {
                    completion(.failure(error))
                } else {
                    NotificationCenter.default.post(name: NutritionCoreNotification.dataDidChange, object: nil)
                    completion(.success(()))
                }
            }
    }
}

