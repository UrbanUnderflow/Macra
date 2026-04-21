import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

final class LabelScanService {
    static let sharedInstance = LabelScanService()
    /// Legacy alias for call sites that still use `.shared` (the old
    /// Features-module duplicate exposed this name).
    static let shared = sharedInstance

    private let db: Firestore

    private init() {
        self.db = Firestore.firestore()
    }

    func getScannedLabels(userId: String? = nil, completion: @escaping (Result<[ScannedLabel], Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.labelScansCollection)
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error {
                    completion(.failure(error))
                    return
                }

                let scans = snapshot?.documents.compactMap { document -> ScannedLabel? in
                    let data = document.data()
                    let gradeResultData = data["gradeResult"] as? [String: Any] ?? [
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

                    let gradeResult = LabelGradeResult(from: gradeResultData)
                    let createdAt = nutritionDate(from: data["createdAt"] ?? data["scannedAt"])
                    let qaHistory = self.parseQAHistory(from: data)
                    let deepDiveResult = self.parseDeepDiveResult(from: data)
                    let deepDiveTimestamp = nutritionOptionalDate(from: data["deepDiveTimestamp"])
                    let alternatives = self.parseAlternatives(from: data)
                    let alternativesTimestamp = nutritionOptionalDate(from: data["alternativesTimestamp"])
                    let productTitle = (data["productTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let productTitleEdited = data["productTitleEdited"] as? Bool ?? false
                    let imageURL = data["imageURL"] as? String ?? data["labelImageURL"] as? String
                    let userId = data["userId"] as? String

                    return ScannedLabel(
                        id: document.documentID,
                        gradeResult: gradeResult,
                        imageData: nil,
                        imageURL: imageURL,
                        createdAt: createdAt,
                        userId: userId,
                        productTitle: (productTitle?.isEmpty == false ? productTitle : nil) ?? gradeResult.productTitle,
                        productTitleEdited: productTitleEdited,
                        qaHistory: qaHistory,
                        deepDiveResult: deepDiveResult,
                        deepDiveTimestamp: deepDiveTimestamp,
                        alternatives: alternatives,
                        alternativesTimestamp: alternativesTimestamp
                    )
                } ?? []

                completion(.success(scans))
            }
    }

    func saveScannedLabel(_ scannedLabel: ScannedLabel, userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        uploadImageIfNeeded(for: scannedLabel, userId: resolvedUserId) { [weak self] result in
            switch result {
            case .success(let imageURL):
                self?.saveLabelDocument(scannedLabel, userId: resolvedUserId, imageURL: imageURL, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func deleteScannedLabel(_ scannedLabel: ScannedLabel, userId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let docRef = db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.labelScansCollection)
            .document(scannedLabel.id)

        docRef.delete { error in
            if let error {
                completion(.failure(error))
                return
            }

            if let imageURL = scannedLabel.imageURL {
                let storageRef = Storage.storage().reference(forURL: imageURL)
                storageRef.delete { storageError in
                    if let storageError {
                        NutritionCoreLogger.log(.warning, message: "Failed to delete scanned label image", error: storageError)
                    }
                    completion(.success(()))
                }
            } else {
                completion(.success(()))
            }
        }
    }

    func updateInteractionHistory(
        scanId: String,
        userId: String? = nil,
        qaHistory: [LabelQAMessage]? = nil,
        deepDiveResult: LabelDeepDiveResult? = nil,
        deepDiveTimestamp: Date? = nil,
        alternatives: [HealthierAlternative]? = nil,
        alternativesTimestamp: Date? = nil,
        productTitle: String? = nil,
        productTitleEdited: Bool? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        let docRef = db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.labelScansCollection)
            .document(scanId)

        var updateData: [String: Any] = [:]

        if let qaHistory {
            updateData["qaHistory"] = qaHistory.map {
                [
                    "id": $0.id,
                    "role": $0.role.rawValue,
                    "content": $0.content,
                    "timestamp": Timestamp(date: $0.timestamp)
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
            updateData["alternatives"] = alternatives.map {
                var dict: [String: Any] = [
                    "id": $0.id,
                    "name": $0.name,
                    "reason": $0.reason,
                    "grade": $0.grade,
                    "improvements": $0.improvements,
                    "whereToFind": $0.whereToFind as Any,
                    "category": $0.category as Any
                ]
                if let url = $0.productUrl, !url.isEmpty {
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

    func updateMacros(scanId: String, userId: String? = nil, macros: LabelNutritionFacts, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let resolvedUserId = NutritionCoreConfiguration.resolvedUserId(userId) else {
            completion(.failure(NutritionCoreError.missingUserId))
            return
        }

        var updateData: [String: Any] = [:]
        if let calories = macros.calories { updateData["gradeResult.calories"] = calories }
        if let protein = macros.protein { updateData["gradeResult.protein"] = protein }
        if let fat = macros.fat { updateData["gradeResult.fat"] = fat }
        if let carbs = macros.carbs { updateData["gradeResult.carbs"] = carbs }
        if let servingSize = macros.servingSize, !servingSize.isEmpty { updateData["gradeResult.servingSize"] = servingSize }
        if let sugars = macros.sugars { updateData["gradeResult.sugars"] = sugars }
        if let dietaryFiber = macros.dietaryFiber { updateData["gradeResult.dietaryFiber"] = dietaryFiber }
        if let sugarAlcohols = macros.sugarAlcohols { updateData["gradeResult.sugarAlcohols"] = sugarAlcohols }
        if let sodium = macros.sodium { updateData["gradeResult.sodium"] = sodium }

        guard !updateData.isEmpty else {
            completion(.success(()))
            return
        }

        let docRef = db.collection(NutritionCoreConfiguration.usersCollection)
            .document(resolvedUserId)
            .collection(NutritionCoreConfiguration.labelScansCollection)
            .document(scanId)

        docRef.updateData(updateData) { error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    private func uploadImageIfNeeded(for scannedLabel: ScannedLabel, userId: String, completion: @escaping (Result<String?, Error>) -> Void) {
        if let existingURL = scannedLabel.imageURL {
            completion(.success(existingURL))
            return
        }

        guard let imageData = scannedLabel.imageData else {
            completion(.success(nil))
            return
        }

        let storageRef = Storage.storage().reference()
            .child(NutritionCoreConfiguration.labelScanStorageFolder)
            .child(userId)
            .child("\(scannedLabel.id).jpg")

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
        let docRef = db.collection(NutritionCoreConfiguration.usersCollection)
            .document(userId)
            .collection(NutritionCoreConfiguration.labelScansCollection)
            .document(scannedLabel.id)

        var data: [String: Any] = [
            "gradeResult": encodeGradeResult(scannedLabel.gradeResult),
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
            "userId": userId,
            "productTitleEdited": scannedLabel.productTitleEdited
        ]

        if let productTitle = scannedLabel.productTitle, !productTitle.isEmpty {
            data["productTitle"] = productTitle
        }

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
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        } catch {
            NutritionCoreLogger.log(.error, message: "Failed to encode grade result", error: error)
            return [:]
        }
    }

    private func parseQAHistory(from data: [String: Any]) -> [LabelQAMessage] {
        guard let qaArray = data["qaHistory"] as? [[String: Any]] else { return [] }
        return qaArray.compactMap { dict in
            guard let roleString = dict["role"] as? String,
                  let content = dict["content"] as? String else { return nil }
            let role = LabelQARole(rawValue: roleString) ?? .user
            let timestamp = nutritionOptionalDate(from: dict["timestamp"]) ?? Date()
            let id = dict["id"] as? String ?? UUID().uuidString
            return LabelQAMessage(id: id, role: role, content: content, timestamp: timestamp)
        }
    }

    private func parseDeepDiveResult(from data: [String: Any]) -> LabelDeepDiveResult? {
        guard let deepDiveDict = data["deepDiveResult"] as? [String: Any] else { return nil }
        return LabelDeepDiveResult(from: deepDiveDict)
    }

    private func parseAlternatives(from data: [String: Any]) -> [HealthierAlternative]? {
        guard let alternativesArray = data["alternatives"] as? [[String: Any]] else { return nil }
        let alternatives = alternativesArray.map { HealthierAlternative(from: $0) }
        return alternatives.isEmpty ? nil : alternatives
    }

    private func encodeDeepDiveResult(_ result: LabelDeepDiveResult) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["longTermEffects"] = result.longTermEffects.map {
            [
                "id": $0.id,
                "effect": $0.effect,
                "description": $0.description,
                "severity": $0.severity,
                "timeframe": $0.timeframe,
                "relatedIngredients": $0.relatedIngredients
            ]
        }
        dict["nutritionalBreakdown"] = [
            "macroAnalysis": result.nutritionalBreakdown.macroAnalysis,
            "micronutrientNotes": result.nutritionalBreakdown.micronutrientNotes,
            "calorieContext": result.nutritionalBreakdown.calorieContext,
            "portionGuidance": result.nutritionalBreakdown.portionGuidance
        ]
        dict["researchFindings"] = result.researchFindings.map {
            [
                "id": $0.id,
                "title": $0.title,
                "summary": $0.summary,
                "source": $0.source,
                "year": $0.year as Any,
                "relevance": $0.relevance
            ]
        }
        dict["regulatoryStatus"] = [
            "fdaStatus": result.regulatoryStatus.fdaStatus,
            "whoGuidance": result.regulatoryStatus.whoGuidance,
            "bannedIn": result.regulatoryStatus.bannedIn,
            "warnings": result.regulatoryStatus.warnings
        ]
        if let productTitle = result.productTitle, !productTitle.isEmpty {
            dict["productTitle"] = productTitle
        }
        return dict
    }
}
