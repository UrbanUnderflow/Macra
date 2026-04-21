import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseStorage
import UIKit

enum MacraMealPlanServiceError: Error, LocalizedError {
    case notAuthenticated
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You need to be signed in to generate a meal plan."
        case .invalidResponse: return "Couldn't read the meal plan response."
        case .server(let msg): return msg
        }
    }
}

struct MacraMealPlanService {
    static let shared = MacraMealPlanService()

    private struct Request: Encodable {
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let goal: String?
        let dietaryPreference: String?
        let mealsPerDay: Int
        let forceRegenerate: Bool
        let extraContext: String?
        let imageUrls: [String]?
    }

    private struct Response: Decodable {
        let plan: MacraSuggestedMealPlan
        let cached: Bool?
        let generatedAt: Double?
    }

    func generate(
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        goal: String?,
        dietaryPreference: String?,
        mealsPerDay: Int = 4,
        forceRegenerate: Bool = false,
        extraContext: String? = nil,
        imageUrls: [String]? = nil
    ) async throws -> MacraSuggestedMealPlan {
        guard let user = Auth.auth().currentUser else {
            throw MacraMealPlanServiceError.notAuthenticated
        }
        let token = try await user.getIDToken()

        let base = ConfigManager.shared.getWebsiteBaseURL()
        guard let url = URL(string: "\(base)/.netlify/functions/generate-macra-meal-plan") else {
            throw MacraMealPlanServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let payload = Request(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            goal: goal,
            dietaryPreference: dietaryPreference,
            mealsPerDay: mealsPerDay,
            forceRegenerate: forceRegenerate,
            extraContext: extraContext,
            imageUrls: imageUrls
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        guard let http = httpResponse as? HTTPURLResponse else {
            throw MacraMealPlanServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw MacraMealPlanServiceError.server("Meal plan service returned \(http.statusCode): \(bodyString.prefix(200))")
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.plan
    }
}

/// Uploads user-supplied context images for Nora (meal plan regenerate) to Firebase Storage
/// and returns download URLs. Caps to 5 images — each compressed to JPEG at 0.75 quality.
struct MacraPlanContextImageUploader {
    static let shared = MacraPlanContextImageUploader()
    private let maxImages = 5

    func upload(images: [UIImage]) async throws -> [String] {
        guard let userId = Auth.auth().currentUser?.uid, !userId.isEmpty else {
            throw MacraMealPlanServiceError.notAuthenticated
        }
        let clipped = Array(images.prefix(maxImages))
        var urls: [String] = []
        let root = Storage.storage().reference()
            .child("macraPlanContext")
            .child(userId)

        for image in clipped {
            guard let data = image.jpegData(compressionQuality: 0.75) else { continue }
            let fileId = UUID().uuidString
            let ref = root.child("\(fileId).jpg")
            _ = try await ref.putDataAsync(data, metadata: nil)
            let url = try await ref.downloadURL()
            urls.append(url.absoluteString)
        }
        return urls
    }
}

/// Represents a previously generated Nora plan archived in Firestore.
/// Loaded lazily for the "Use a pre-existing plan" surface.
struct MacraPlanHistoryItem: Identifiable, Hashable {
    let id: String
    let plan: MacraSuggestedMealPlan
    let generatedAt: Date
    let extraContext: String?

    init?(id: String, data: [String: Any]) {
        guard let planDict = data["plan"] as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: planDict),
              let plan = try? JSONDecoder().decode(MacraSuggestedMealPlan.self, from: jsonData) else {
            return nil
        }
        self.id = id
        self.plan = plan
        if let millis = data["generatedAt"] as? Double {
            self.generatedAt = Date(timeIntervalSince1970: millis / 1000)
        } else {
            self.generatedAt = Date()
        }
        self.extraContext = data["extraContext"] as? String
    }
}

@MainActor
final class MacraOnboardingCoordinator: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case meetNora
        case sex
        case age
        case height
        case currentWeight
        case goalWeight
        case pace
        case activityLevel
        case dietaryPreference
        case biggestStruggle
        case generatingPlan
        case prediction
        case planReady
        case features
        case notificationPreferences
        case commitTrial
    }

    @Published var currentStep: Step = .welcome
    @Published var answers = MacraOnboardingAnswers()
    @Published var isFinishing: Bool = false
    @Published var selectedPackageId: String?
    @Published var isPurchasing: Bool = false
    @Published var purchaseError: String?
    @Published var planMacros: MacroRecommendation?
    @Published var isLoadingPlanMacros: Bool = false
    @Published var suggestedMealPlan: MacraSuggestedMealPlan?
    @Published var isLoadingMealPlan: Bool = false
    @Published var mealPlanError: String?

    let appCoordinator: AppCoordinator
    let startingStep: Step

    init(appCoordinator: AppCoordinator, startingStep: Step = .welcome) {
        self.appCoordinator = appCoordinator
        self.startingStep = startingStep
        self.currentStep = startingStep
    }

    var progress: Double {
        let total = Double(Step.allCases.count)
        return Double(currentStep.rawValue + 1) / total
    }

    var canGoBack: Bool {
        if currentStep == startingStep { return false }
        switch currentStep {
        case .welcome, .generatingPlan:
            return false
        default:
            return currentStep.rawValue > 0
        }
    }

    var canGoForward: Bool {
        switch currentStep {
        case .welcome: return true
        case .meetNora: return true
        case .sex: return answers.sex != nil
        case .age: return answers.birthdate != nil
        case .height: return (answers.heightCm ?? 0) > 50
        case .currentWeight: return (answers.currentWeightKg ?? 0) > 20
        case .goalWeight: return (answers.goalWeightKg ?? 0) > 20
        case .pace: return answers.pace != nil
        case .activityLevel: return answers.activityLevel != nil
        case .dietaryPreference: return answers.dietaryPreference != nil
        case .biggestStruggle: return answers.biggestStruggle != nil
        case .generatingPlan: return true
        case .prediction: return true
        case .planReady: return suggestedMealPlan != nil || mealPlanError != nil
        case .features: return true
        case .notificationPreferences: return true
        case .commitTrial: return !isPurchasing
        }
    }

    var selectedPlan: SubscriptionPlanOption? {
        let offering = PurchaseService.sharedInstance.offering
        if let id = selectedPackageId,
           let match = offering.planOptions.first(where: { $0.id == id }) {
            return match
        }
        return offering.planOptions.first
    }

    var selectedPackage: PackageViewModel? {
        return selectedPlan?.packageViewModel
    }

    func selectPlan(_ plan: SubscriptionPlanOption) {
        selectedPackageId = plan.id
    }

    func ensureOfferingsLoaded(force: Bool = false) {
        let offering = PurchaseService.sharedInstance.offering
        guard !offering.isLoadingPackages else { return }
        guard force || offering.planOptions.isEmpty else { return }
        Task {
            await offering.start()
        }
    }

    func loadPlanMacros() {
        if let prediction = MacraOnboardingPrediction.compute(from: answers) {
            let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid ?? ""
            planMacros = prediction.toMacroRecommendation(userId: userId)
            return
        }

        guard let userId = UserService.sharedInstance.user?.id, !userId.isEmpty else { return }
        guard planMacros == nil, !isLoadingPlanMacros else { return }

        isLoadingPlanMacros = true
        MacroRecommendationService.sharedInstance.getCurrentMacroRecommendation(for: userId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoadingPlanMacros = false
                if case .success(let recommendation) = result {
                    self?.planMacros = recommendation
                }
            }
        }
    }

    func loadSuggestedMealPlan(forceRegenerate: Bool = false) {
        guard let macros = planMacros else { return }
        guard !isLoadingMealPlan else { return }
        if suggestedMealPlan != nil && !forceRegenerate { return }

        isLoadingMealPlan = true
        mealPlanError = nil

        let goal = goalSummary()
        let dietary = answers.dietaryPreference?.rawValue

        Task { [weak self] in
            do {
                let plan = try await MacraMealPlanService.shared.generate(
                    calories: macros.calories,
                    protein: macros.protein,
                    carbs: macros.carbs,
                    fat: macros.fat,
                    goal: goal,
                    dietaryPreference: dietary,
                    mealsPerDay: 4,
                    forceRegenerate: forceRegenerate
                )
                await MainActor.run {
                    self?.suggestedMealPlan = plan
                    self?.isLoadingMealPlan = false
                }
            } catch {
                await MainActor.run {
                    self?.mealPlanError = error.localizedDescription
                    self?.isLoadingMealPlan = false
                }
            }
        }
    }

    private func goalSummary() -> String? {
        guard let current = answers.currentWeightKg,
              let goal = answers.goalWeightKg else { return nil }
        let delta = goal - current
        if abs(delta) < 1 { return "maintain weight" }
        let direction = delta < 0 ? "lose" : "gain"
        let lbs = Int(abs(delta) * 2.20462)
        return "\(direction) \(lbs) lbs"
    }

    func advance() {
        let next = currentStep.rawValue + 1
        guard let nextStep = Step(rawValue: next) else {
            dismissPaywall()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = nextStep
        }
    }

    func back() {
        let prev = currentStep.rawValue - 1
        guard let prevStep = Step(rawValue: prev) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = prevStep
        }
    }

    func completeQuestionnaire() {
        guard !isFinishing else { return }
        isFinishing = true

        UserService.sharedInstance.saveMacraProfile(answers: answers) { _ in
            UserService.sharedInstance.markMacraOnboardingComplete { [weak self] _ in
                self?.saveMacroTargetsFromPrediction {
                    DispatchQueue.main.async {
                        self?.isFinishing = false
                        self?.advance()
                    }
                }
            }
        }
    }

    /// Called from the notification preferences step once the user confirms.
    /// Persists prefs to Firestore, installs the on-device schedules, and
    /// kicks off the Macra welcome email (which is idempotent server-side).
    func persistNotificationPreferencesAndNotifyWelcome() {
        let preferences = answers.notificationPreferences
        UserService.sharedInstance.saveMacraNotificationPreferences(preferences)
        NotificationService.sharedInstance.syncScheduledNotifications(with: preferences)
        UserService.sharedInstance.sendMacraWelcomeEmail()
    }

    private func saveMacroTargetsFromPrediction(completion: @escaping () -> Void) {
        guard let prediction = MacraOnboardingPrediction.compute(from: answers),
              let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid,
              !userId.isEmpty else {
            completion()
            return
        }

        let recommendation = prediction.toMacroRecommendation(userId: userId)
        MacroRecommendationService.sharedInstance.saveMacroRecommendation(recommendation) { _ in
            completion()
        }
    }

    func dismissPaywall() {
        let cachedUserHasAccess =
            UserService.sharedInstance.user?.subscriptionType.grantsMacraAccess == true ||
            UserService.sharedInstance.isBetaUser
        if PurchaseService.sharedInstance.isSubscribed || cachedUserHasAccess {
            appCoordinator.showHomeScreen()
            return
        }

        PurchaseService.sharedInstance.checkSubscriptionStatus(forceRefresh: true) { [weak self] result in
            guard case .success(true) = result else { return }

            DispatchQueue.main.async {
                self?.appCoordinator.showHomeScreen()
            }
        }
    }

    func purchaseAndContinue() {
        guard !isPurchasing else { return }
        let offering = PurchaseService.sharedInstance.offering
        guard !offering.isLoadingPackages else {
            purchaseError = "Plans are still loading. Please try again in a moment."
            return
        }
        guard offering.packageLoadError == nil else {
            purchaseError = offering.packageLoadError
            return
        }
        guard let plan = selectedPlan else {
            purchaseError = "Plans are still loading. Please try again in a moment."
            return
        }

        isPurchasing = true
        purchaseError = nil

        PurchaseService.sharedInstance.offering.purchase(plan) { [weak self] result in
            DispatchQueue.main.async {
                self?.isPurchasing = false
                switch result {
                case .success:
                    self?.verifySubscriptionAndContinue()
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.domain == "Purchase Canceled" {
                        self?.purchaseError = nil
                    } else if PurchaseService.sharedInstance.isAlreadySubscribedError(error) {
                        self?.syncExistingSubscriptionAndContinue()
                    } else {
                        self?.purchaseError = error.localizedDescription
                    }
                }
            }
        }
    }

    func restorePurchasesAndContinue() {
        guard !isPurchasing else { return }

        isPurchasing = true
        purchaseError = nil

        PurchaseService.sharedInstance.restoreSubscriptionStatus { [weak self] result in
            DispatchQueue.main.async {
                self?.isPurchasing = false
                self?.handleSubscriptionVerificationResult(
                    result,
                    inactiveMessage: "No active subscription found to restore."
                )
            }
        }
    }

    private func verifySubscriptionAndContinue() {
        isPurchasing = true
        PurchaseService.sharedInstance.checkSubscriptionStatus(forceRefresh: true) { [weak self] result in
            DispatchQueue.main.async {
                self?.isPurchasing = false
                self?.handleSubscriptionVerificationResult(
                    result,
                    inactiveMessage: "Your purchase went through, but subscription access is still syncing. Tap Restore Purchases to refresh it."
                )
            }
        }
    }

    private func syncExistingSubscriptionAndContinue() {
        isPurchasing = true
        purchaseError = "Checking your existing subscription..."

        PurchaseService.sharedInstance.syncSubscriptionStatus { [weak self] result in
            DispatchQueue.main.async {
                self?.isPurchasing = false
                self?.handleSubscriptionVerificationResult(
                    result,
                    inactiveMessage: "You're subscribed in StoreKit, but access did not sync yet. Tap Restore Purchases to refresh it."
                )
            }
        }
    }

    private func handleSubscriptionVerificationResult(_ result: Result<Bool, Error>, inactiveMessage: String) {
        switch result {
        case .success(true):
            purchaseError = nil
            appCoordinator.showHomeScreen()
        case .success(false):
            purchaseError = inactiveMessage
        case .failure(let error):
            purchaseError = error.localizedDescription
        }
    }
}

struct MacraOnboardingFlowView: View {
    @StateObject private var coordinator: MacraOnboardingCoordinator

    init(appCoordinator: AppCoordinator, startingStep: MacraOnboardingCoordinator.Step = .welcome) {
        _coordinator = StateObject(wrappedValue: MacraOnboardingCoordinator(appCoordinator: appCoordinator, startingStep: startingStep))
    }

    var body: some View {
        Group {
            switch coordinator.currentStep {
            case .welcome:
                WelcomeStepView(coordinator: coordinator)
            case .meetNora:
                MeetNoraStepView(coordinator: coordinator)
            case .sex:
                SexStepView(coordinator: coordinator)
            case .age:
                AgeStepView(coordinator: coordinator)
            case .height:
                HeightStepView(coordinator: coordinator)
            case .currentWeight:
                WeightStepView(coordinator: coordinator, kind: .current)
            case .goalWeight:
                WeightStepView(coordinator: coordinator, kind: .goal)
            case .pace:
                PaceStepView(coordinator: coordinator)
            case .activityLevel:
                ActivityLevelStepView(coordinator: coordinator)
            case .dietaryPreference:
                DietaryPreferenceStepView(coordinator: coordinator)
            case .biggestStruggle:
                BiggestStruggleStepView(coordinator: coordinator)
            case .generatingPlan:
                GeneratingPlanStepView(coordinator: coordinator)
            case .prediction:
                PredictionStepView(coordinator: coordinator)
            case .planReady:
                PlanReadyStepView(coordinator: coordinator)
            case .features:
                FeaturesStepView(coordinator: coordinator)
            case .notificationPreferences:
                NotificationPreferencesStepView(coordinator: coordinator)
            case .commitTrial:
                CommitTrialStepView(coordinator: coordinator)
            }
        }
    }
}
