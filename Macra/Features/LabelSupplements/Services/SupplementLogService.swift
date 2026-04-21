import Foundation
import FirebaseAuth
import FirebaseFirestore

final class SupplementLogService {
    static let shared = SupplementLogService()

    private let db = Firestore.firestore()

    private init() {}

    func getSavedSupplements(completion: @escaping (Result<[LoggedSupplement], Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "SupplementLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }

        db.collection("users").document(userId).collection("savedSupplements").order(by: "createdAt", descending: true).getDocuments { snapshot, error in
            if let error {
                completion(.failure(error))
                return
            }

            let supplements = snapshot?.documents.map { LoggedSupplement(id: $0.documentID, dictionary: $0.data()) } ?? []
            completion(.success(supplements))
        }
    }

    func saveSupplement(_ supplement: LoggedSupplement, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "SupplementLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }

        db.collection("users").document(userId).collection("savedSupplements").document(supplement.id).setData(supplement.toDictionary()) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func deleteSavedSupplement(withId supplementId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "SupplementLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }

        db.collection("users").document(userId).collection("savedSupplements").document(supplementId).delete { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func addLoggedSupplement(_ supplement: LoggedSupplement, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "SupplementLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }

        let documentId = Date().dayMonthYearFormat + supplement.id
        let supRef = db.collection("users").document(userId).collection("supplementLogs").document(documentId)
        supRef.setData(supplement.toDictionary()) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func getLoggedSupplements(byDate date: Date, completion: @escaping (Result<[LoggedSupplement], Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "SupplementLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }

        let calendar = Calendar.current
        guard let startOfDay = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date),
              let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) else {
            completion(.failure(NSError(domain: "SupplementLogService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not calculate date range"])))
            return
        }

        db.collection("users").document(userId).collection("supplementLogs")
            .whereField("createdAt", isGreaterThanOrEqualTo: startOfDay.timeIntervalSince1970)
            .whereField("createdAt", isLessThanOrEqualTo: endOfDay.timeIntervalSince1970)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let supplements = snapshot?.documents.map { LoggedSupplement(id: $0.documentID, dictionary: $0.data()) } ?? []
                completion(.success(supplements))
            }
    }

    func deleteLoggedSupplement(withId supplementId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "SupplementLogService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])))
            return
        }

        db.collection("users").document(userId).collection("supplementLogs").document(supplementId).delete { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}

