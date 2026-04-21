import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

final class LabelScanService {
    static let shared = LabelScanService()

    private init() {}

    func getScannedLabels(completion: @escaping (Result<[ScannedLabel], Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "LabelScanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])))
            return
        }

        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("labelScans")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let labels: [ScannedLabel] = snapshot?.documents.compactMap { doc in
                    let data = doc.data()
                    let gradeResult: LabelGradeResult
                    if let gradeDict = data["gradeResult"] as? [String: Any] {
                        gradeResult = LabelGradeResult(from: gradeDict)
                    } else {
                        let legacyDict: [String: Any] = [
                            "grade": data["grade"] as? String ?? "F",
                            "summary": data["summary"] as? String ?? "Unable to analyze label",
                            "detailedExplanation": data["detailedExplanation"] as? String ?? data["summary"] as? String ?? "Unable to analyze label",
                            "confidence": data["confidence"] as? Double ?? 0.0,
                            "flaggedIngredients": data["flaggedIngredients"] as? [String] ?? [],
                            "concerns": data["concerns"] as? [[String: Any]] ?? [],
                            "sources": data["sources"] as? [[String: Any]] ?? [],
                            "errorCode": data["errorCode"] as? String as Any,
                            "errorDetails": data["errorDetails"] as? String as Any,
                            "errorCategory": data["errorCategory"] as? String as Any
                        ]
                        gradeResult = LabelGradeResult(from: legacyDict)
                    }

                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let imageURL = data["imageURL"] as? String ?? data["labelImageURL"] as? String
                    let qaHistory = self.parseQAHistory(from: data)
                    let deepDiveResult = self.parseDeepDiveResult(from: data)
                    let deepDiveTimestamp = (data["deepDiveTimestamp"] as? Timestamp)?.dateValue()
                    let alternatives = self.parseAlternatives(from: data)
                    let alternativesTimestamp = (data["alternativesTimestamp"] as? Timestamp)?.dateValue()
                    let productTitle = (data["productTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let productTitleEdited = data["productTitleEdited"] as? Bool ?? false
                    let resolvedProductTitle = (productTitle?.isEmpty == false ? productTitle : nil) ?? gradeResult.productTitle

                    return ScannedLabel(
                        id: doc.documentID,
                        gradeResult: gradeResult,
                        imageData: nil,
                        imageURL: imageURL,
                        createdAt: createdAt,
                        userId: userId,
                        productTitle: resolvedProductTitle,
                        productTitleEdited: productTitleEdited,
                        qaHistory: qaHistory,
                        deepDiveResult: deepDiveResult,
                        deepDiveTimestamp: deepDiveTimestamp,
                        alternatives: alternatives,
                        alternativesTimestamp: alternativesTimestamp
                    )
                } ?? []

                completion(.success(labels))
            }
    }

    func saveScannedLabel(_ scannedLabel: ScannedLabel, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "LabelScanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])))
            return
        }

        uploadImageIfNeeded(for: scannedLabel, userId: userId) { [weak self] result in
            switch result {
            case .success(let imageURL):
                self?.saveLabelDocument(scannedLabel, userId: userId, imageURL: imageURL, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func deleteScannedLabel(_ scannedLabel: ScannedLabel, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "LabelScanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])))
            return
        }

        let docRef = Firestore.firestore().collection("users").document(userId).collection("labelScans").document(scannedLabel.id)
        docRef.delete { error in
            if let error {
                completion(.failure(error))
                return
            }

            if let imageURL = scannedLabel.imageURL, let storageURL = URL(string: imageURL) {
                let storageRef = Storage.storage().reference(forURL: storageURL.absoluteString)
                storageRef.delete { _ in
                    completion(.success(()))
                }
            } else {
                completion(.success(()))
            }
        }
    }

    func updateInteractionHistory(
        scanId: String,
        qaHistory: [LabelQAMessage]? = nil,
        deepDiveResult: LabelDeepDiveResult? = nil,
        deepDiveTimestamp: Date? = nil,
        alternatives: [HealthierAlternative]? = nil,
        alternativesTimestamp: Date? = nil,
        productTitle: String? = nil,
        productTitleEdited: Bool? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "LabelScanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])))
            return
        }

        let docRef = Firestore.firestore().collection("users").document(userId).collection("labelScans").document(scanId)
        var updateData: [String: Any] = [:]

        if let qaHistory {
            updateData["qaHistory"] = qaHistory.map { message in
                [
                    "id": message.id,
                    "role": message.role.rawValue,
                    "content": message.content,
                    "timestamp": Timestamp(date: message.timestamp)
                ]
            }
        }

        if let deepDiveResult {
            updateData["deepDiveResult"] = encodeDeepDiveResult(deepDiveResult)
        }
        if let deepDiveTimestamp {
            updateData["deepDiveTimestamp"] = Timestamp(date: deepDiveTimestamp)
        }
        if let alternatives {
            updateData["alternatives"] = alternatives.map { alt in
                var dict: [String: Any] = [
                    "id": alt.id,
                    "name": alt.name,
                    "reason": alt.reason,
                    "grade": alt.grade,
                    "improvements": alt.improvements,
                    "whereToFind": alt.whereToFind as Any,
                    "category": alt.category as Any
                ]
                if let url = alt.productUrl, !url.isEmpty {
                    dict["productUrl"] = url
                }
                return dict
            }
        }
        if let alternativesTimestamp {
            updateData["alternativesTimestamp"] = Timestamp(date: alternativesTimestamp)
        }
        if let productTitle = productTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !productTitle.isEmpty {
            updateData["productTitle"] = productTitle
        }
        if let productTitleEdited {
            updateData["productTitleEdited"] = productTitleEdited
        }

        guard !updateData.isEmpty else {
            completion(.success(()))
            return
        }

        docRef.updateData(updateData) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func updateMacros(scanId: String, macros: LabelNutritionFacts, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "LabelScanService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing user id"])))
            return
        }

        var updateData: [String: Any] = [:]
        if let calories = macros.calories { updateData["gradeResult.calories"] = calories }
        if let protein = macros.protein { updateData["gradeResult.protein"] = protein }
        if let fat = macros.fat { updateData["gradeResult.fat"] = fat }
        if let carbs = macros.carbs { updateData["gradeResult.carbs"] = carbs }
        if let servingSize = macros.servingSize, !servingSize.isEmpty { updateData["gradeResult.servingSize"] = servingSize }
        if let sugars = macros.sugars { updateData["gradeResult.sugars"] = sugars }
        if let fiber = macros.dietaryFiber { updateData["gradeResult.dietaryFiber"] = fiber }
        if let sugarAlcohols = macros.sugarAlcohols { updateData["gradeResult.sugarAlcohols"] = sugarAlcohols }
        if let sodium = macros.sodium { updateData["gradeResult.sodium"] = sodium }

        guard !updateData.isEmpty else {
            completion(.success(()))
            return
        }

        let docRef = Firestore.firestore().collection("users").document(userId).collection("labelScans").document(scanId)
        docRef.updateData(updateData) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    // MARK: - Private helpers

    private func uploadImageIfNeeded(for scannedLabel: ScannedLabel, userId: String, completion: @escaping (Result<String?, Error>) -> Void) {
        if let existingURL = scannedLabel.imageURL {
            completion(.success(existingURL))
            return
        }

        guard let imageData = scannedLabel.imageData else {
            completion(.success(nil))
            return
        }

        let storageRef = Storage.storage().reference().child("label-scans/\(userId)/\(scannedLabel.id).jpg")
        storageRef.putData(imageData, metadata: nil) { _, error in
            if let error {
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { url, error in
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(url?.absoluteString))
                }
            }
        }
    }

    private func saveLabelDocument(_ scannedLabel: ScannedLabel, userId: String, imageURL: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        let docRef = Firestore.firestore().collection("users").document(userId).collection("labelScans").document(scannedLabel.id)
        let gradeResultDict = encodeGradeResult(scannedLabel.gradeResult)

        var data: [String: Any] = [
            "gradeResult": gradeResultDict,
            "grade": scannedLabel.gradeResult.grade,
            "summary": scannedLabel.gradeResult.summary,
            "detailedExplanation": scannedLabel.gradeResult.detailedExplanation,
            "confidence": scannedLabel.gradeResult.confidence,
            "flaggedIngredients": scannedLabel.gradeResult.flaggedIngredients,
            "concerns": scannedLabel.gradeResult.concerns.map { ["concern": $0.concern, "scientificReason": $0.scientificReason, "severity": $0.severity, "relatedIngredients": $0.relatedIngredients] },
            "sources": scannedLabel.gradeResult.sources.map { ["name": $0.name, "type": $0.type, "title": $0.title, "url": $0.url as Any, "relevance": $0.relevance] },
            "errorCode": scannedLabel.gradeResult.errorCode as Any,
            "errorDetails": scannedLabel.gradeResult.errorDetails as Any,
            "errorCategory": scannedLabel.gradeResult.errorCategory as Any,
            "imageURL": imageURL as Any,
            "createdAt": Timestamp(date: scannedLabel.createdAt),
            "userId": userId
        ]

        if let productTitle = scannedLabel.productTitle, !productTitle.isEmpty {
            data["productTitle"] = productTitle
        }
        data["productTitleEdited"] = scannedLabel.productTitleEdited

        docRef.setData(data) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    private func encodeGradeResult(_ gradeResult: LabelGradeResult) -> [String: Any] {
        do {
            let data = try JSONEncoder().encode(gradeResult)
            return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        } catch {
            return [:]
        }
    }

    private func parseQAHistory(from data: [String: Any]) -> [LabelQAMessage] {
        guard let qaArray = data["qaHistory"] as? [[String: Any]] else {
            return []
        }
        return qaArray.compactMap { dict in
            guard let roleString = dict["role"] as? String,
                  let content = dict["content"] as? String else {
                return nil
            }
            let role = LabelQARole(rawValue: roleString) ?? .user
            let timestamp = (dict["timestamp"] as? Timestamp)?.dateValue() ?? Date()
            let id = dict["id"] as? String ?? UUID().uuidString
            return LabelQAMessage(id: id, role: role, content: content, timestamp: timestamp)
        }
    }

    private func parseDeepDiveResult(from data: [String: Any]) -> LabelDeepDiveResult? {
        guard let deepDiveDict = data["deepDiveResult"] as? [String: Any] else {
            return nil
        }
        return LabelDeepDiveResult(from: deepDiveDict)
    }

    private func parseAlternatives(from data: [String: Any]) -> [HealthierAlternative]? {
        guard let altsArray = data["alternatives"] as? [[String: Any]] else {
            return nil
        }
        let alternatives = altsArray.map { HealthierAlternative(from: $0) }
        return alternatives.isEmpty ? nil : alternatives
    }

    private func encodeDeepDiveResult(_ result: LabelDeepDiveResult) -> [String: Any] {
        var dict: [String: Any] = [
            "longTermEffects": result.longTermEffects.map { [
                "id": $0.id,
                "effect": $0.effect,
                "description": $0.description,
                "severity": $0.severity,
                "timeframe": $0.timeframe,
                "relatedIngredients": $0.relatedIngredients
            ] },
            "nutritionalBreakdown": [
                "macroAnalysis": result.nutritionalBreakdown.macroAnalysis,
                "micronutrientNotes": result.nutritionalBreakdown.micronutrientNotes,
                "calorieContext": result.nutritionalBreakdown.calorieContext,
                "portionGuidance": result.nutritionalBreakdown.portionGuidance
            ],
            "researchFindings": result.researchFindings.map { [
                "id": $0.id,
                "title": $0.title,
                "summary": $0.summary,
                "source": $0.source,
                "year": $0.year as Any,
                "relevance": $0.relevance
            ] },
            "regulatoryStatus": [
                "fdaStatus": result.regulatoryStatus.fdaStatus,
                "whoGuidance": result.regulatoryStatus.whoGuidance,
                "bannedIn": result.regulatoryStatus.bannedIn,
                "warnings": result.regulatoryStatus.warnings
            ]
        ]
        if let productTitle = result.productTitle, !productTitle.isEmpty {
            dict["productTitle"] = productTitle
        }
        return dict
    }
}

