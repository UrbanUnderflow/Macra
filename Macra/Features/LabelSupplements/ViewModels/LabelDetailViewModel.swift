import Foundation
import SwiftUI

final class LabelDetailViewModel: ObservableObject {
    @Published var scannedLabel: ScannedLabel
    let appCoordinator: AppCoordinator?

    @Published var expandedSection: LabelDetailSection?
    @Published var qaMessages: [LabelQAMessage] = []
    @Published var isAskingQuestion = false
    @Published var currentQuestion = ""
    @Published var qaError: String?
    @Published var deepDiveResult: LabelDeepDiveResult?
    @Published var deepDiveTimestamp: Date?
    @Published var isLoadingDeepDive = false
    @Published var deepDiveError: String?
    @Published var alternatives: [HealthierAlternative]?
    @Published var alternativesTimestamp: Date?
    @Published var isLoadingAlternatives = false
    @Published var alternativesError: String?
    @Published var expandedConcernId: String?
    @Published var backfilledProductTitle: String?
    @Published var userEditedProductTitle: String?
    @Published var isLoadingProductTitle = false
    @Published var isSavingProductTitle = false

    var result: LabelGradeResult { scannedLabel.gradeResult }

    var hasHistory: Bool {
        !qaMessages.isEmpty || deepDiveResult != nil || alternatives != nil
    }

    var displayProductTitle: String? {
        let edited = userEditedProductTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let edited, !edited.isEmpty { return edited }
        let fromScan = scannedLabel.productTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromScan, !fromScan.isEmpty { return fromScan }
        let fromGrade = result.productTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fromGrade, !fromGrade.isEmpty { return fromGrade }
        return backfilledProductTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? backfilledProductTitle : nil
    }

    var isTitleEdited: Bool {
        if let edited = userEditedProductTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !edited.isEmpty {
            return true
        }
        return scannedLabel.productTitleEdited
    }

    var suggestedQuestions: [SuggestedQuestion] {
        var questions: [SuggestedQuestion] = []

        switch result.grade.uppercased() {
        case "C", "D", "F":
            questions.append(SuggestedQuestion(text: "Is this safe to eat occasionally?", icon: "calendar"))
        default:
            break
        }

        let hasSugarConcern = result.flaggedIngredients.contains { $0.lowercased().contains("sugar") || $0.lowercased().contains("sweetener") }
        if hasSugarConcern {
            questions.append(SuggestedQuestion(text: "Is this safe for diabetics?", icon: "heart.text.square"))
        }

        let hasPreservatives = result.flaggedIngredients.contains { $0.lowercased().contains("preservative") || $0.lowercased().contains("bha") || $0.lowercased().contains("bht") }
        if hasPreservatives {
            questions.append(SuggestedQuestion(text: "What are the long-term effects of these preservatives?", icon: "clock"))
        }

        questions.append(SuggestedQuestion(text: "Can I give this to children?", icon: "figure.and.child.holdinghands"))
        questions.append(SuggestedQuestion(text: "Is this good for daily consumption?", icon: "repeat"))
        questions.append(SuggestedQuestion(text: "Does this contain common allergens?", icon: "exclamationmark.triangle"))

        return Array(questions.prefix(6))
    }

    init(scannedLabel: ScannedLabel, appCoordinator: AppCoordinator? = nil) {
        self.scannedLabel = scannedLabel
        self.appCoordinator = appCoordinator
        self.qaMessages = scannedLabel.qaHistory
        self.deepDiveResult = scannedLabel.deepDiveResult
        self.deepDiveTimestamp = scannedLabel.deepDiveTimestamp
        self.alternatives = scannedLabel.alternatives
        self.alternativesTimestamp = scannedLabel.alternativesTimestamp
    }

    func fetchProductTitleIfNeeded() {
        if displayProductTitle != nil, !(displayProductTitle?.isEmpty ?? true) {
            return
        }
        if isTitleEdited || isLoadingProductTitle {
            return
        }

        isLoadingProductTitle = true
        let gradeResult = result

        let infer: (String?) -> Void = { [weak self] imageBase64 in
            guard let self else { return }
            LabelSupplementsAIService.shared.inferProductTitle(gradeResult: gradeResult, imageBase64: imageBase64) { response in
                DispatchQueue.main.async {
                    self.isLoadingProductTitle = false
                    switch response {
                    case .success(let title):
                        if !self.isTitleEdited {
                            self.backfilledProductTitle = title
                            self.persistProductTitle(title, edited: false)
                        }
                    case .failure:
                        break
                    }
                }
            }
        }

        if let imageData = scannedLabel.imageData, !imageData.isEmpty {
            infer(imageData.base64EncodedString())
            return
        }

        if let urlString = scannedLabel.imageURL, !urlString.isEmpty, let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let base64 = data.flatMap { $0.isEmpty ? nil : $0.base64EncodedString() }
                DispatchQueue.main.async {
                    infer(base64)
                }
            }.resume()
            return
        }

        infer(nil)
    }

    func updateProductTitle(_ newTitle: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "LabelDetailViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Product title cannot be empty"])))
            return
        }

        isSavingProductTitle = true
        persistProductTitle(trimmed, edited: true) { [weak self] result in
            DispatchQueue.main.async {
                self?.isSavingProductTitle = false
                if case .success = result {
                    self?.userEditedProductTitle = trimmed
                }
                completion(result)
            }
        }
    }

    func toggleSection(_ section: LabelDetailSection) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if expandedSection == section {
                expandedSection = nil
            } else {
                expandedSection = section
                switch section {
                case .deepDive:
                    if deepDiveResult == nil && !isLoadingDeepDive {
                        fetchDeepDive()
                    }
                case .alternatives:
                    if alternatives == nil && !isLoadingAlternatives {
                        fetchAlternatives()
                    }
                case .askQuestion:
                    break
                }
            }
        }
    }

    func askQuestion(_ question: String) {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isAskingQuestion else { return }

        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        qaMessages.append(LabelQAMessage(role: .user, content: trimmed))
        currentQuestion = ""
        isAskingQuestion = true
        qaError = nil

        LabelSupplementsAIService.shared.askLabelQuestion(
            gradeResult: result,
            question: trimmed,
            conversationHistory: qaMessages
        ) { [weak self] response in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isAskingQuestion = false
                switch response {
                case .success(let answer):
                    self.qaMessages.append(LabelQAMessage(role: .assistant, content: answer))
                    self.persistQAHistory()
                case .failure(let error):
                    self.qaError = "Failed to get answer: \(error.localizedDescription)"
                }
            }
        }
    }

    func askSuggestedQuestion(_ question: SuggestedQuestion) {
        askQuestion(question.text)
    }

    func clearQAHistory() {
        qaMessages.removeAll()
        qaError = nil
        persistQAHistory()
    }

    func fetchDeepDive() {
        guard !isLoadingDeepDive else { return }

        isLoadingDeepDive = true
        deepDiveError = nil

        LabelSupplementsAIService.shared.deepDiveLabelAnalysis(gradeResult: result) { [weak self] response in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingDeepDive = false
                switch response {
                case .success(let deepDive):
                    self.deepDiveResult = deepDive
                    self.deepDiveTimestamp = Date()
                    if let title = deepDive.productTitle, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !self.isTitleEdited {
                        self.backfilledProductTitle = title
                    }
                    self.persistDeepDive()
                case .failure(let error):
                    self.deepDiveError = error.localizedDescription
                }
            }
        }
    }

    func retryDeepDive() {
        deepDiveResult = nil
        deepDiveTimestamp = nil
        fetchDeepDive()
    }

    func fetchAlternatives() {
        guard !isLoadingAlternatives else { return }

        isLoadingAlternatives = true
        alternativesError = nil

        LabelSupplementsAIService.shared.findHealthierAlternatives(gradeResult: result) { [weak self] response in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingAlternatives = false
                switch response {
                case .success(let payload):
                    self.alternatives = payload.0
                    self.alternativesTimestamp = Date()
                    if let title = payload.productTitle, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !self.isTitleEdited {
                        self.backfilledProductTitle = title
                    }
                    self.persistAlternatives(backfillProductTitle: self.isTitleEdited ? nil : payload.productTitle)
                case .failure(let error):
                    self.alternativesError = error.localizedDescription
                }
            }
        }
    }

    func retryAlternatives() {
        alternatives = nil
        alternativesTimestamp = nil
        fetchAlternatives()
    }

    // MARK: - Persistence helpers

    private func persistQAHistory() {
        LabelScanService.shared.updateInteractionHistory(scanId: scannedLabel.id, qaHistory: qaMessages) { _ in }
    }

    private func persistDeepDive() {
        LabelScanService.shared.updateInteractionHistory(
            scanId: scannedLabel.id,
            deepDiveResult: deepDiveResult,
            deepDiveTimestamp: deepDiveTimestamp,
            productTitle: backfilledProductTitle ?? deepDiveResult?.productTitle
        ) { _ in }
    }

    private func persistAlternatives(backfillProductTitle: String?) {
        LabelScanService.shared.updateInteractionHistory(
            scanId: scannedLabel.id,
            alternatives: alternatives,
            alternativesTimestamp: alternativesTimestamp,
            productTitle: backfillProductTitle
        ) { _ in }
    }

    private func persistProductTitle(_ title: String, edited: Bool, completion: ((Result<Void, Error>) -> Void)? = nil) {
        LabelScanService.shared.updateInteractionHistory(
            scanId: scannedLabel.id,
            productTitle: title,
            productTitleEdited: edited
        ) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    self?.scannedLabel.productTitle = title
                    self?.scannedLabel.productTitleEdited = edited
                }
                completion?(result)
            }
        }
    }
}

