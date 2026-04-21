import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct ScannedLabel: Identifiable, Hashable {
    let id: String
    let gradeResult: LabelGradeResult
    let imageData: Data?
    let imageURL: String?
    let createdAt: Date
    let userId: String?
    var productTitle: String?
    var productTitleEdited: Bool
    var qaHistory: [LabelQAMessage]
    var deepDiveResult: LabelDeepDiveResult?
    var deepDiveTimestamp: Date?
    var alternatives: [HealthierAlternative]?
    var alternativesTimestamp: Date?

    init(
        id: String,
        gradeResult: LabelGradeResult,
        imageData: Data? = nil,
        imageURL: String? = nil,
        createdAt: Date = Date(),
        userId: String? = nil,
        productTitle: String? = nil,
        productTitleEdited: Bool = false,
        qaHistory: [LabelQAMessage] = [],
        deepDiveResult: LabelDeepDiveResult? = nil,
        deepDiveTimestamp: Date? = nil,
        alternatives: [HealthierAlternative]? = nil,
        alternativesTimestamp: Date? = nil
    ) {
        self.id = id
        self.gradeResult = gradeResult
        self.imageData = imageData
        self.imageURL = imageURL
        self.createdAt = createdAt
        self.userId = userId
        self.productTitle = productTitle ?? gradeResult.productTitle
        self.productTitleEdited = productTitleEdited
        self.qaHistory = qaHistory
        self.deepDiveResult = deepDiveResult
        self.deepDiveTimestamp = deepDiveTimestamp
        self.alternatives = alternatives
        self.alternativesTimestamp = alternativesTimestamp
    }

#if canImport(UIKit)
    var thumbnailImage: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }
#endif

    var hasInteractionHistory: Bool {
        !qaHistory.isEmpty || deepDiveResult != nil || alternatives != nil
    }
}
