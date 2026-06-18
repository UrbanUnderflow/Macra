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
    enum Step: Int, CaseIterable, Hashable {
        case welcome
        case primaryFocus
        case meetNora
        case coachAssignedPlan
        case fwpMacrosHandoff
        case sex
        case age
        case height
        case currentWeight
        case goalWeight
        case pace
        case activityLevel
        case sportSelection
        case dietaryPreference
        case biggestStruggle
        case generatingPlan
        case prediction
        case planReady
        case features
        case notificationPreferences
        case commitTrial
        case activationStart
    }

    enum FWPHandoffState: Equatable {
        case checking
        case unavailable
        case available(MacroRecommendations)
        case accepted
        case reassessing
    }

    @Published var currentStep: Step = .welcome
    /// Set when an under-16 user is detected at the age step. Drives the
    /// terminal age-gate block — Macra is a weight-management product, so
    /// under-16s are blocked entirely (16–17 are forced to maintenance-only).
    @Published var ageGateBlocked: Bool = false
    @Published var answers = MacraOnboardingAnswers()
    @Published var isFinishing: Bool = false
    @Published var selectedPackageId: String?
    @Published var isPurchasing: Bool = false
    @Published var purchaseError: String?
    @Published var onboardingExperienceVariant: MacraOnboardingExperienceVariant
    @Published var planMacros: MacroRecommendation?
    @Published var isLoadingPlanMacros: Bool = false
    @Published var suggestedMealPlan: MacraSuggestedMealPlan?
    @Published var isLoadingMealPlan: Bool = false
    @Published var mealPlanError: String?
    @Published var fwpHandoffState: FWPHandoffState = .checking
    @Published var existingSubscriptionAccessOverride: Bool?
    @Published var purchaseCancellationFeedbackRequestID: UUID?
    /// True when the user accepted FWP macros — skip biometric steps + use FWP macros verbatim.
    private(set) var usingFWPMacros: Bool = false
    private var currentPurchasePaywallMetadata: [String: Any] = [:]
    private var activePurchaseLogID: String?
    private var trackedPaywallViewSources: Set<String> = []

    var currentPurchaseLogIDForFeedback: String? {
        activePurchaseLogID
    }

    /// Coach-assigned meal plan (Pulse 1-on-1) detected for this user.
    /// `.checking` while we resolve, `.unavailable` when the user has
    /// no active 1-on-1 with a meal-plan attachment, `.available`
    /// when we've found one. Drives the optional `.coachAssignedPlan`
    /// step.
    enum CoachPlanState: Equatable {
        case checking
        case unavailable
        case available(CoachMealPlan)
        case adopted
    }
    @Published var coachPlanState: CoachPlanState = .checking
    /// Latched when the user (or auto-adopt) accepts the coach plan —
    /// `advance()` then skips biometrics + macro analysis the same
    /// way `usingFWPMacros` does.
    private(set) var usingCoachPlan: Bool = false
    private var visibleStepVisitCounts: [Step: Int] = [:]
    private var lastTrackedVisibleStep: Step?
    private var pendingOnboardingCompletionAction: String?
    private var didTrackOnboardingStarted = false
    private var didTrackOnboardingProfileCompleted = false
    private var didTrackOnboardingCompleted = false
    private var didTrackExistingSubscriptionAccessContinue = false
    private var didTrackTrialActivationScreenViewed = false
    private var didTrackTrialActivationPrimaryPressed = false
    private var trackedOnboardingStepViews: Set<Step> = []
    private var trackedOnboardingStepCompletions: Set<Step> = []

    let appCoordinator: AppCoordinator
    let startingStep: Step
    let isDemoMode: Bool
    let usesLivePurchasesInDemo: Bool
    let paywallDefaultPlanSelectionOverride: MacraPaywallDefaultPlanSelection?
    let paywallLayoutVariantOverride: MacraPaywallLayoutVariant?
    let onboardingExperienceVariantOverride: MacraOnboardingExperienceVariant?
    private let onDemoDismiss: (() -> Void)?

    init(
        appCoordinator: AppCoordinator,
        startingStep: Step = .welcome,
        isDemoMode: Bool = false,
        usesLivePurchasesInDemo: Bool = false,
        onDemoDismiss: (() -> Void)? = nil,
        existingSubscriptionAccessOverride: Bool? = nil,
        paywallDefaultPlanSelectionOverride: MacraPaywallDefaultPlanSelection? = nil,
        paywallLayoutVariantOverride: MacraPaywallLayoutVariant? = nil,
        onboardingExperienceVariantOverride: MacraOnboardingExperienceVariant? = nil
    ) {
        let cachedExperimentAssignment = MacraPaywallExperimentService.cachedAssignment()
        self.appCoordinator = appCoordinator
        self.startingStep = startingStep
        self.currentStep = startingStep
        self.isDemoMode = isDemoMode
        self.usesLivePurchasesInDemo = usesLivePurchasesInDemo
        self.paywallDefaultPlanSelectionOverride = paywallDefaultPlanSelectionOverride
        self.paywallLayoutVariantOverride = paywallLayoutVariantOverride
        self.onboardingExperienceVariantOverride = onboardingExperienceVariantOverride
        self.onDemoDismiss = onDemoDismiss
        self.existingSubscriptionAccessOverride = existingSubscriptionAccessOverride
        self.onboardingExperienceVariant = onboardingExperienceVariantOverride ?? cachedExperimentAssignment.onboardingVariant

        if isDemoMode {
            self.answers = Self.demoAnswers
            self.planMacros = Self.demoMacroRecommendation
            self.suggestedMealPlan = Self.demoMealPlan
        }
    }

    private static var demoAnswers: MacraOnboardingAnswers {
        var answers = MacraOnboardingAnswers()
        answers.primaryFocus = .eatConsistently
        answers.sex = .male
        answers.birthdate = Calendar.current.date(byAdding: .year, value: -31, to: Date())
        answers.heightCm = 180
        answers.currentWeightKg = 88
        answers.goalWeightKg = 82
        answers.pace = .moderate
        answers.activityLevel = .moderate
        answers.dietaryPreference = .none
        answers.biggestStruggle = .planning
        return answers
    }

    private static var demoMacroRecommendation: MacroRecommendation {
        MacroRecommendation(
            userId: "screen-demo-user",
            calories: 2380,
            protein: 185,
            carbs: 255,
            fat: 70
        )
    }

    private static var demoMealPlan: MacraSuggestedMealPlan {
        MacraSuggestedMealPlan(
            meals: [
                MacraSuggestedMeal(
                    title: "Protein oats",
                    items: [
                        MacraSuggestedMealItem(name: "Rolled oats", quantity: "60g", calories: 230, protein: 8, carbs: 40, fat: 4, imageURL: nil, imageMatch: nil),
                        MacraSuggestedMealItem(name: "Whey isolate", quantity: "1 scoop", calories: 120, protein: 25, carbs: 2, fat: 1, imageURL: nil, imageMatch: nil),
                        MacraSuggestedMealItem(name: "Blueberries", quantity: "80g", calories: 45, protein: 1, carbs: 11, fat: 0, imageURL: nil, imageMatch: nil)
                    ],
                    notes: "Good first meal if training is later in the day.",
                    imageURL: nil,
                    imageURLs: nil,
                    imageMatches: nil,
                    order: 1,
                    daysActive: nil
                ),
                MacraSuggestedMeal(
                    title: "Chicken burrito bowl",
                    items: [
                        MacraSuggestedMealItem(name: "Chicken", quantity: "6 oz", calories: 280, protein: 52, carbs: 0, fat: 6, imageURL: nil, imageMatch: nil),
                        MacraSuggestedMealItem(name: "Brown rice", quantity: "1 cup", calories: 215, protein: 5, carbs: 45, fat: 2, imageURL: nil, imageMatch: nil),
                        MacraSuggestedMealItem(name: "Black beans", quantity: "1/2 cup", calories: 110, protein: 7, carbs: 20, fat: 0, imageURL: nil, imageMatch: nil),
                        MacraSuggestedMealItem(name: "Salsa + lettuce", quantity: "1 serving", calories: 35, protein: 1, carbs: 8, fat: 0, imageURL: nil, imageMatch: nil)
                    ],
                    notes: "Easy to scan, easy to adjust, and still built around foods you would actually eat.",
                    imageURL: nil,
                    imageURLs: nil,
                    imageMatches: nil,
                    order: 2,
                    daysActive: nil
                ),
                MacraSuggestedMeal(
                    title: "Greek yogurt snack",
                    items: [
                        MacraSuggestedMealItem(name: "Greek yogurt", quantity: "250g", calories: 150, protein: 25, carbs: 10, fat: 0, imageURL: nil, imageMatch: nil),
                        MacraSuggestedMealItem(name: "Granola", quantity: "35g", calories: 160, protein: 4, carbs: 28, fat: 5, imageURL: nil, imageMatch: nil)
                    ],
                    notes: "Keeps protein high without making dinner huge.",
                    imageURL: nil,
                    imageURLs: nil,
                    imageMatches: nil,
                    order: 3,
                    daysActive: nil
                ),
                MacraSuggestedMeal(
                    title: "Lean dinner plate",
                    items: [
                        MacraSuggestedMealItem(name: "Turkey patties", quantity: "7 oz", calories: 330, protein: 48, carbs: 0, fat: 14, imageURL: nil, imageMatch: nil),
                        MacraSuggestedMealItem(name: "Sweet potato", quantity: "250g", calories: 215, protein: 4, carbs: 50, fat: 0, imageURL: nil, imageMatch: nil),
                        MacraSuggestedMealItem(name: "Green beans", quantity: "2 cups", calories: 70, protein: 4, carbs: 14, fat: 0, imageURL: nil, imageMatch: nil)
                    ],
                    notes: "Nora keeps dinner lean because the bowl used more fat earlier.",
                    imageURL: nil,
                    imageURLs: nil,
                    imageMatches: nil,
                    order: 4,
                    daysActive: nil
                )
            ],
            notes: nil
        )
    }

    private static var demoPlanOptions: [SubscriptionPlanOption] {
        [
            .local(LocalSubscriptionPlanViewModel(
                id: "rc_annual_demo",
                displayTitle: "Annual",
                localizedPriceString: "$39.99",
                price: Decimal(39.99),
                periodKind: .year,
                trialDays: 3,
                product: nil
            )),
            .local(LocalSubscriptionPlanViewModel(
                id: "rc_monthly_demo",
                displayTitle: "Monthly",
                localizedPriceString: "$4.99",
                price: Decimal(4.99),
                periodKind: .month,
                trialDays: nil,
                product: nil
            ))
        ]
    }

    var progress: Double {
        let total = Double(Step.allCases.count)
        return Double(currentStep.rawValue + 1) / total
    }

    var canGoBack: Bool {
        if currentStep == startingStep { return false }
        switch currentStep {
        case .welcome, .generatingPlan, .notificationPreferences, .activationStart:
            return false
        default:
            return currentStep.rawValue > 0
        }
    }

    var canGoForward: Bool {
        switch currentStep {
        case .welcome: return true
        case .primaryFocus: return onboardingExperienceVariant != .noraGuided || answers.primaryFocus != nil
        case .meetNora: return true
        case .coachAssignedPlan:
            // Coach-handoff screen drives its own CTA; no global "continue".
            return false
        case .fwpMacrosHandoff:
            // The handoff screen drives its own CTA; no global "continue" button.
            return false
        case .sex: return answers.sex != nil
        case .age: return answers.birthdate != nil
        case .height: return (answers.heightCm ?? 0) > 50
        case .currentWeight: return (answers.currentWeightKg ?? 0) > 20
        case .goalWeight: return (answers.goalWeightKg ?? 0) > 20
        case .pace: return answers.pace != nil
        case .activityLevel: return answers.activityLevel != nil
        case .sportSelection: return answers.sport != nil
        case .dietaryPreference: return answers.dietaryPreference != nil
        case .biggestStruggle: return answers.biggestStruggle != nil
        case .generatingPlan: return true
        case .prediction: return true
        case .planReady: return true
        case .features: return true
        case .commitTrial: return !isPurchasing
        case .notificationPreferences: return true
        case .activationStart: return true
        }
    }

    var selectedPlan: SubscriptionPlanOption? {
        if let id = selectedPackageId,
           let match = availablePlanOptions.first(where: { $0.id == id }) {
            return match
        }
        return availablePlanOptions.first
    }

    var availablePlanOptions: [SubscriptionPlanOption] {
        if isDemoMode && !usesLivePurchasesInDemo { return Self.demoPlanOptions }
        return PurchaseService.sharedInstance.offering.planOptions
    }

    var selectedPackage: PackageViewModel? {
        return selectedPlan?.packageViewModel
    }

    func selectPlan(_ plan: SubscriptionPlanOption) {
        selectedPackageId = plan.id
    }

    func ensureOfferingsLoaded(force: Bool = false) {
        guard !isDemoMode || usesLivePurchasesInDemo else {
            if currentStep == .commitTrial {
                trackPaywallViewedIfNeeded()
            }
            return
        }

        let offering = PurchaseService.sharedInstance.offering
        guard !offering.isLoadingPackages else { return }
        guard force || offering.planOptions.isEmpty else {
            if currentStep == .commitTrial {
                trackPaywallViewedIfNeeded()
            }
            return
        }
        Task {
            await offering.start(source: paywallAnalyticsSource)
            if self.currentStep == .commitTrial {
                self.trackPaywallViewedIfNeeded()
            }
        }
    }

    func trackPaywallViewedIfNeeded(source: String? = nil) {
        guard !isDemoMode else { return }
        guard !hasExistingSubscriptionAccess else { return }

        let resolvedSource = source ?? paywallAnalyticsSource
        guard !trackedPaywallViewSources.contains(resolvedSource) else { return }

        trackedPaywallViewSources.insert(resolvedSource)
        let offering = PurchaseService.sharedInstance.offering
        MacraAnalyticsService.shared.trackPaywallViewed(
            source: resolvedSource,
            selectedPlan: selectedPlan,
            availablePlans: offering.planOptions,
            metadata: paywallFunnelAnalyticsMetadata
        )
    }

    var paywallAnalyticsSource: String {
        startingStep == .commitTrial ? "subscription_required" : "onboarding_paywall"
    }

    var onboardingAnalyticsSource: String {
        startingStep == .commitTrial ? "subscription_required" : "new_user_onboarding"
    }

    var hasExistingSubscriptionAccess: Bool {
        if let existingSubscriptionAccessOverride {
            return existingSubscriptionAccessOverride
        }

        return PurchaseService.sharedInstance.isSubscribed ||
        UserService.sharedInstance.user?.subscriptionType.grantsMacraAccess == true ||
        UserService.sharedInstance.isBetaUser
    }

    func trackCurrentOnboardingStepViewed(trigger: String) {
        guard !isDemoMode else { return }
        trackOnboardingStartedIfNeeded()

        let step = currentStep
        let visitCount = (visibleStepVisitCounts[step] ?? 0) + 1
        visibleStepVisitCounts[step] = visitCount
        lastTrackedVisibleStep = step
        guard trackedOnboardingStepViews.insert(step).inserted else { return }

        MacraAnalyticsService.shared.trackOnboardingStepViewed(
            stepId: step.analyticsId,
            stepName: step.analyticsName,
            stepIndex: step.rawValue,
            stepCount: Step.allCases.count,
            source: onboardingAnalyticsSource,
            startingStepId: startingStep.analyticsId,
            visitCount: visitCount,
            trigger: trigger,
            metadata: onboardingAnalyticsMetadata
        )
    }

    private func trackCurrentOnboardingStepCompleted(action: String, destination: Step?) {
        guard shouldTrackCurrentVisibleStep else { return }
        guard trackedOnboardingStepCompletions.insert(currentStep).inserted else { return }

        let resolvedAction = pendingOnboardingCompletionAction ?? action
        pendingOnboardingCompletionAction = nil

        MacraAnalyticsService.shared.trackOnboardingStepCompleted(
            stepId: currentStep.analyticsId,
            stepName: currentStep.analyticsName,
            stepIndex: currentStep.rawValue,
            stepCount: Step.allCases.count,
            source: onboardingAnalyticsSource,
            startingStepId: startingStep.analyticsId,
            completionAction: resolvedAction,
            destinationStepId: destination?.analyticsId,
            metadata: onboardingAnalyticsMetadata
        )
    }

    private func trackCurrentOnboardingStepBack(destination: Step?) {
        guard shouldTrackCurrentVisibleStep else { return }

        MacraAnalyticsService.shared.trackOnboardingStepBack(
            stepId: currentStep.analyticsId,
            stepName: currentStep.analyticsName,
            stepIndex: currentStep.rawValue,
            stepCount: Step.allCases.count,
            source: onboardingAnalyticsSource,
            startingStepId: startingStep.analyticsId,
            destinationStepId: destination?.analyticsId,
            metadata: onboardingAnalyticsMetadata
        )
    }

    private var shouldTrackCurrentVisibleStep: Bool {
        !isDemoMode && lastTrackedVisibleStep == currentStep
    }

    private func trackOnboardingStartedIfNeeded() {
        guard !didTrackOnboardingStarted else { return }
        didTrackOnboardingStarted = true

        MacraAnalyticsService.shared.trackOnboardingStarted(
            source: onboardingAnalyticsSource,
            startingStepId: startingStep.analyticsId,
            stepCount: Step.allCases.count,
            metadata: onboardingAnalyticsMetadata
        )
    }

    private func trackOnboardingProfileCompletedIfNeeded(action: String) {
        guard !isDemoMode, !didTrackOnboardingProfileCompleted else { return }
        didTrackOnboardingProfileCompleted = true

        MacraAnalyticsService.shared.trackOnboardingProfileCompleted(
            source: onboardingAnalyticsSource,
            startingStepId: startingStep.analyticsId,
            stepCount: Step.allCases.count,
            completionAction: action,
            metadata: onboardingAnalyticsMetadata
        )
    }

    private func trackOnboardingCompletedIfNeeded(action: String) {
        guard !isDemoMode, startingStep != .commitTrial, !didTrackOnboardingCompleted else { return }
        didTrackOnboardingCompleted = true

        MacraAnalyticsService.shared.trackOnboardingCompleted(
            source: onboardingAnalyticsSource,
            startingStepId: startingStep.analyticsId,
            stepCount: Step.allCases.count,
            completionAction: action,
            metadata: onboardingAnalyticsMetadata
        )
    }

    private var onboardingAnalyticsMetadata: [String: Any] {
        [
            "progress": progress,
            "can_go_forward": canGoForward,
            "using_fwp_macros": usingFWPMacros,
            "using_coach_plan": usingCoachPlan,
            "onboarding_experience_variant": onboardingExperienceVariant.rawValue,
            "has_plan_macros": planMacros != nil,
            "has_suggested_meal_plan": suggestedMealPlan != nil
        ]
    }

    var paywallFunnelAnalyticsMetadata: [String: Any] {
        var metadata = onboardingAnalyticsMetadata
        let age = onboardingAgeYears
        metadata["paywall_context"] = startingStep == .commitTrial ? "subscription_required" : "new_user_onboarding"
        metadata["age_years"] = age ?? -1
        metadata["age_segment"] = onboardingAgeSegment
        metadata["is_minor"] = (age ?? 18) < 18
        metadata["has_birthdate"] = answers.birthdate != nil
        metadata["sex"] = answers.sex?.rawValue ?? "unknown"
        metadata["goal_direction"] = answers.goalDirection?.rawValue ?? "unknown"
        metadata["pace"] = answers.pace?.rawValue ?? "unknown"
        metadata["activity_level"] = answers.activityLevel?.rawValue ?? "unknown"
        metadata["dietary_preference"] = answers.dietaryPreference?.rawValue ?? "unknown"
        metadata["biggest_struggle"] = answers.biggestStruggle?.rawValue ?? "unknown"
        metadata["has_personalized_plan_preview"] = planMacros != nil
        metadata["has_suggested_meal_plan"] = suggestedMealPlan != nil
        if let selectedPlan {
            metadata["selected_plan_period_at_decision"] = periodAnalyticsName(selectedPlan.periodKind)
            metadata["selected_plan_id_at_decision"] = selectedPlan.id
        } else {
            metadata["selected_plan_period_at_decision"] = "none"
            metadata["selected_plan_id_at_decision"] = "none"
        }
        return metadata
    }

    private var activePaywallFunnelAnalyticsMetadata: [String: Any] {
        var metadata = paywallFunnelAnalyticsMetadata
        currentPurchasePaywallMetadata.forEach { metadata[$0.key] = $0.value }
        return metadata
    }

    private var onboardingAgeYears: Int? {
        guard let birthdate = answers.birthdate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year
    }

    private var onboardingAgeSegment: String {
        guard let age = onboardingAgeYears else { return "unknown" }
        if age < 13 { return "under_13" }
        if age < 18 { return "minor_13_17" }
        if age < 25 { return "young_adult_18_24" }
        return "adult_25_plus"
    }

    private func periodAnalyticsName(_ period: SubscriptionPlanPeriodKind) -> String {
        switch period {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        case .unknown: return "unknown"
        }
    }

    private func trackSubscriptionStart(plan: SubscriptionPlanOption) {
        guard !isDemoMode else { return }
        MacraAnalyticsService.shared.trackSubscriptionStart(
            plan: plan,
            source: paywallAnalyticsSource,
            metadata: activePaywallFunnelAnalyticsMetadata
        )
    }

    private func trackSubscriptionPurchaseAttempted(plan: SubscriptionPlanOption) {
        guard !isDemoMode else { return }
        MacraAnalyticsService.shared.trackSubscriptionPurchaseAttempted(
            plan: plan,
            source: paywallAnalyticsSource,
            metadata: activePaywallFunnelAnalyticsMetadata
        )
    }

    func trackTrialActivationScreenViewedIfNeeded() {
        guard !isDemoMode, !didTrackTrialActivationScreenViewed else { return }
        didTrackTrialActivationScreenViewed = true
        var metadata = activePaywallFunnelAnalyticsMetadata
        metadata["has_suggested_first_meal"] = suggestedMealPlan?.meals.first != nil
        metadata["has_activation_macros"] = planMacros != nil
        MacraAnalyticsService.shared.trackTrialActivationScreenViewed(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            metadata: metadata
        )
    }

    func startTrialActivationFirstMeal() {
        guard !isPurchasing else { return }
        if !isDemoMode, !didTrackTrialActivationPrimaryPressed {
            didTrackTrialActivationPrimaryPressed = true
            var metadata = activePaywallFunnelAnalyticsMetadata
            metadata["has_suggested_first_meal"] = suggestedMealPlan?.meals.first != nil
            metadata["has_activation_macros"] = planMacros != nil
            MacraAnalyticsService.shared.trackTrialActivationPrimaryPressed(
                source: paywallAnalyticsSource,
                selectedPlan: selectedPlan,
                actionTitle: "Start with one meal",
                metadata: metadata
            )
        }
        pendingOnboardingCompletionAction = "activation_primary_pressed"
        advance()
    }

    private func activePurchaseLogMetadata(channel: String, extra: [String: Any] = [:]) -> [String: Any] {
        var metadata = activePaywallFunnelAnalyticsMetadata
        metadata["purchase_channel"] = channel
        metadata["selected_plan_id"] = selectedPlan?.id ?? "none"
        metadata["selected_plan_period_at_decision"] = selectedPlan.map { periodAnalyticsName($0.periodKind) } ?? "none"
        extra.forEach { metadata[$0.key] = $0.value }
        return metadata
    }

    private func scheduleTrialEndingReminderIfRequested(plan: SubscriptionPlanOption?) {
        guard !isDemoMode,
              let leadDays = intPurchaseMetadataValue(for: "trial_reminder_lead_days"),
              leadDays > 0 else { return }

        let trialDays = intPurchaseMetadataValue(for: "trial_disclosure_days") ?? plan?.trialDays
        guard let trialDays, trialDays > 0 else { return }

        NotificationService.sharedInstance.scheduleTrialEndingReminder(
            trialDays: trialDays,
            leadDays: leadDays
        )
    }

    private func intPurchaseMetadataValue(for key: String) -> Int? {
        let value = currentPurchasePaywallMetadata[key]
        if let intValue = value as? Int {
            return intValue
        }
        if let numberValue = value as? NSNumber {
            return numberValue.intValue
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }

    private func logPurchaseSuccess(plan: SubscriptionPlanOption, channel: String) {
        MacraPurchaseLogService.shared.markSuccess(
            logID: activePurchaseLogID,
            plan: plan,
            source: paywallAnalyticsSource,
            metadata: activePurchaseLogMetadata(channel: channel)
        )
        activePurchaseLogID = nil
    }

    private func logPurchaseCanceled(plan: SubscriptionPlanOption, error: Error, failureReason: String) {
        MacraPurchaseLogService.shared.markCanceled(
            logID: activePurchaseLogID,
            plan: plan,
            source: paywallAnalyticsSource,
            error: error,
            failureReason: failureReason,
            metadata: activePurchaseLogMetadata(channel: "storekit")
        )
    }

    private func logPurchaseFailed(plan: SubscriptionPlanOption, error: Error, failureReason: String) {
        MacraPurchaseLogService.shared.markFailed(
            logID: activePurchaseLogID,
            plan: plan,
            source: paywallAnalyticsSource,
            error: error,
            failureReason: failureReason,
            metadata: activePurchaseLogMetadata(channel: "storekit")
        )
        activePurchaseLogID = nil
    }

    private func trackPaywallCTABlocked(reason: String) {
        guard !isDemoMode else { return }
        let offering = PurchaseService.sharedInstance.offering
        MacraAnalyticsService.shared.trackPaywallCTABlocked(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            reason: reason,
            ctaTitle: paywallCTATitle,
            availablePlanCount: offering.planOptions.count,
            isLoadingPackages: offering.isLoadingPackages,
            packageLoadError: offering.packageLoadError,
            metadata: activePaywallFunnelAnalyticsMetadata
        )
    }

    private var paywallCTATitle: String {
        guard let plan = selectedPlan else { return "Continue" }
        if let trialDays = plan.trialDays, trialDays > 0 {
            return trialDays == 1 ? "Try 1 day free" : "Try \(trialDays) days free"
        }
        switch plan.periodKind {
        case .year: return "Unlock my yearly plan"
        case .month: return "Unlock my monthly plan"
        default: return "Unlock my plan"
        }
    }

    private func trackSubscriptionPurchaseCancelled(plan: SubscriptionPlanOption, error: Error? = nil) {
        guard !isDemoMode else { return }
        MacraAnalyticsService.shared.trackSubscriptionPurchaseCancelled(
            plan: plan,
            source: paywallAnalyticsSource,
            error: error,
            metadata: activePaywallFunnelAnalyticsMetadata
        )
    }

    private func trackSubscriptionPurchaseFailed(plan: SubscriptionPlanOption, error: Error, reason: String? = nil) {
        guard !isDemoMode else { return }
        MacraAnalyticsService.shared.trackSubscriptionPurchaseFailed(
            plan: plan,
            source: paywallAnalyticsSource,
            error: error,
            reason: reason,
            metadata: activePaywallFunnelAnalyticsMetadata
        )
    }

    private func trackSubscriptionPurchaseAlreadyActive(plan: SubscriptionPlanOption, error: Error) {
        trackSubscriptionPurchaseFailed(plan: plan, error: error, reason: "already_subscribed")
    }

    private func trackRestoreResult(_ result: Result<Bool, Error>) {
        guard !isDemoMode else { return }
        switch result {
        case .success(true):
            MacraAnalyticsService.shared.trackSubscriptionRestoreSucceeded(source: paywallAnalyticsSource)
        case .success(false):
            MacraAnalyticsService.shared.trackSubscriptionRestoreFailed(
                source: paywallAnalyticsSource,
                reason: "no_active_subscription"
            )
        case .failure(let error):
            MacraAnalyticsService.shared.trackSubscriptionRestoreFailed(
                source: paywallAnalyticsSource,
                reason: "restore_error",
                error: error
            )
        }
    }

    private func trackSubscriptionVerificationResult(
        _ result: Result<Bool, Error>,
        plan: SubscriptionPlanOption?,
        context: String,
        inactiveReason: String
    ) {
        guard !isDemoMode else { return }
        switch result {
        case .success(true):
            MacraAnalyticsService.shared.trackSubscriptionAccessVerified(
                plan: plan,
                source: paywallAnalyticsSource,
                context: context,
                metadata: paywallFunnelAnalyticsMetadata
            )
        case .success(false):
            MacraAnalyticsService.shared.trackSubscriptionAccessVerificationFailed(
                plan: plan,
                source: paywallAnalyticsSource,
                context: context,
                reason: inactiveReason,
                metadata: paywallFunnelAnalyticsMetadata
            )
        case .failure(let error):
            MacraAnalyticsService.shared.trackSubscriptionAccessVerificationFailed(
                plan: plan,
                source: paywallAnalyticsSource,
                context: context,
                reason: "verification_error",
                error: error,
                metadata: paywallFunnelAnalyticsMetadata
            )
        }
    }

    // MARK: - FWP Handoff

    /// Called when the user lands on the handoff step. Reads the shared User doc
    /// from Firestore and either auto-advances past this step (no FWP macros) or
    /// surfaces the choice card.
    func loadFWPHandoff() {
        guard !isDemoMode else {
            fwpHandoffState = .unavailable
            advance()
            return
        }

        fwpHandoffState = .checking
        FWPHandoffService.fetchProfile { [weak self] profile in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // Always pre-populate answers we know — saves typing either way.
                self.seedAnswers(from: profile)

                if let macros = profile.personalMacros {
                    self.fwpHandoffState = .available(macros)
                } else {
                    self.fwpHandoffState = .unavailable
                    // Skip the handoff step entirely when there's nothing to offer.
                    self.advance()
                }
            }
        }
    }

    /// User tapped "Use my FWP macros" — pre-populate biometrics, set planMacros
    /// directly, and skip the biometric steps on next `advance()`.
    func acceptFWPMacros(_ macros: MacroRecommendations) {
        usingFWPMacros = true
        fwpHandoffState = .accepted
        let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid ?? ""
        planMacros = MacroRecommendation(
            userId: userId,
            calories: macros.calories,
            protein: macros.protein,
            carbs: macros.carbs,
            fat: macros.fat
        )
        pendingOnboardingCompletionAction = "accept_fwp_macros"
        advance()
    }

    /// User tapped "Reassess" — keep the pre-populated answers as starting values
    /// and proceed through the biometric steps normally.
    func reassessAfterHandoff() {
        usingFWPMacros = false
        fwpHandoffState = .reassessing
        pendingOnboardingCompletionAction = "reassess_after_fwp_handoff"
        advance()
    }

    // MARK: - Coach Plan (Pulse 1-on-1) Handoff

    /// Detect whether the current user has a coach-assigned meal plan
    /// from a Pulse 1-on-1 trainer. Called when the user lands on the
    /// `.coachAssignedPlan` step. Auto-advances when nothing's there.
    func loadCoachPlanHandoff() {
        guard !isDemoMode else {
            coachPlanState = .unavailable
            advance()
            return
        }

        coachPlanState = .checking
        CoachMealPlanService.shared.fetchLatestCoachPlan { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let plan):
                    if let plan = plan {
                        self.coachPlanState = .available(plan)
                    } else {
                        self.coachPlanState = .unavailable
                        self.advance()
                    }
                case .failure:
                    // Quiet failure — never block onboarding when the
                    // cross-product read hiccups.
                    self.coachPlanState = .unavailable
                    self.advance()
                }
            }
        }
    }

    /// User confirmed they want to use the coach plan. Adopts the
    /// plan's macros as Macra's active target (saves to
    /// `macroProfiles/{userId}/macroRecommendations` + mirrors to
    /// `users/{uid}.macros.personal`), persists the
    /// `coachMealPlanReference` so we don't re-adopt next launch,
    /// then skips the FWP handoff + biometric steps and lands the
    /// user on the post-plan-creation flow.
    func acceptCoachPlan(_ plan: CoachMealPlan) {
        usingCoachPlan = true
        coachPlanState = .adopted
        // Pre-populate biometric/preference answers we already know
        // from FWP so any future re-assess has a head-start. Coach
        // plans don't carry biometrics directly — falling back to
        // the FWP profile pre-fill keeps the answer dict consistent.
        FWPHandoffService.fetchProfile { [weak self] profile in
            DispatchQueue.main.async { self?.seedAnswers(from: profile) }
        }

        let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid ?? ""
        planMacros = MacroRecommendation(
            userId: userId,
            calories: plan.totals.calories > 0 ? plan.totals.calories : plan.dailyCalorieTarget,
            protein: plan.totals.protein,
            carbs: plan.totals.carbs,
            fat: plan.totals.fat
        )

        adoptCoachPlan(plan) { _ in }
        pendingOnboardingCompletionAction = "accept_coach_plan"
        advance()
    }

    /// User tapped "Build my own plan instead" — proceed through the
    /// normal biometrics + analyze flow, leaving the coach plan
    /// untouched on the Pulse side.
    func declineCoachPlan() {
        usingCoachPlan = false
        coachPlanState = .unavailable
        pendingOnboardingCompletionAction = "decline_coach_plan"
        advance()
    }

    /// Persist the adopted coach-plan macros to Macra's storage and
    /// the cross-app User mirror, then save the reference so future
    /// launches know we've already adopted this version. Internal —
    /// callable from both onboarding (`acceptCoachPlan`) and the
    /// silent auto-adopt path.
    func adoptCoachPlan(_ plan: CoachMealPlan, completion: @escaping (Error?) -> Void) {
        guard let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid,
              !userId.isEmpty else {
            completion(nil)
            return
        }

        let calories = plan.totals.calories > 0 ? plan.totals.calories : plan.dailyCalorieTarget
        let recommendation = MacroRecommendation(
            userId: userId,
            calories: calories,
            protein: plan.totals.protein,
            carbs: plan.totals.carbs,
            fat: plan.totals.fat
        )

        MacroRecommendationService.sharedInstance.saveMacroRecommendation(recommendation) { _ in
            let mirrored = MacroRecommendations(
                calories: recommendation.calories,
                protein: recommendation.protein,
                carbs: recommendation.carbs,
                fat: recommendation.fat
            )
            FWPHandoffService.mirrorToFWPPersonal(mirrored) { _ in
                let reference = CoachMealPlanReference(
                    trainingId: plan.trainingId,
                    hostId: plan.hostId,
                    hostUsername: plan.hostUsername,
                    attachedAt: plan.attachedAt
                )
                UserService.sharedInstance.saveCoachMealPlanReference(reference, completion: completion)
            }
        }
    }

    /// Copies what we can from the FWP profile into Macra's answers dict.
    private func seedAnswers(from profile: FWPHandoffProfile) {
        if answers.sex == nil, let sex = profile.sex { answers.sex = sex }
        if answers.birthdate == nil, let birthdate = profile.birthdate { answers.birthdate = birthdate }
        if answers.heightCm == nil, let heightCm = profile.heightCm { answers.heightCm = heightCm }
        if answers.currentWeightKg == nil, let weight = profile.currentWeightKg { answers.currentWeightKg = weight }
        if answers.activityLevel == nil, let activity = profile.activityLevel { answers.activityLevel = activity }
    }

    func loadPlanMacros() {
        if isDemoMode {
            planMacros = Self.demoMacroRecommendation
            return
        }

        // When the user accepted FWP macros, planMacros is already set from the
        // shared User doc — don't overwrite it with a prediction computed from
        // partially-populated answers.
        if usingFWPMacros, planMacros != nil { return }

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
        if isDemoMode {
            suggestedMealPlan = Self.demoMealPlan
            isLoadingMealPlan = false
            mealPlanError = nil
            return
        }

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
                    self?.mealPlanError = MacraUserFacingError.mealPlan(error)
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

    /// Age in whole years derived from the onboarding birthdate, if entered.
    var currentAge: Int? {
        guard let birthdate = answers.birthdate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year
    }

    func advance() {
        // Hard age gate: block under-16 the moment we know their age (the
        // `.age` step). 16–17 continue but are forced to maintenance-only in
        // the macro engine (see MacraOnboardingPrediction.compute).
        if currentStep == .age, let age = currentAge, age < 16 {
            ageGateBlocked = true
            trackCurrentOnboardingStepCompleted(action: "age_gate_blocked", destination: nil)
            return
        }

        // 16–17 are maintenance-only: pre-set goal weight = current so the plan
        // is maintenance, then skip the goal-weight + pace steps (see
        // shouldSkip) so the UI matches what they'll actually receive.
        if currentStep == .currentWeight, let age = currentAge, age < 18,
           let current = answers.currentWeightKg {
            answers.goalWeightKg = current
        }

        let next = currentStep.rawValue + 1
        guard let nextStep = Step(rawValue: next) else {
            trackCurrentOnboardingStepCompleted(action: "flow_finished", destination: nil)
            completeOnboardingAndEnterApp(action: "flow_finished")
            return
        }

        if shouldSkip(step: nextStep),
           let destinationStep = Step(rawValue: nextStep.rawValue + 1) {
            trackCurrentOnboardingStepCompleted(action: "advance", destination: destinationStep)
            currentStep = nextStep
            advance()
            return
        }

        if nextStep == .sportSelection,
           answers.activityLevel != .athlete,
           let destinationStep = Step(rawValue: nextStep.rawValue + 1) {
            trackCurrentOnboardingStepCompleted(action: "advance", destination: destinationStep)
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = destinationStep
            }
            return
        }

        trackCurrentOnboardingStepCompleted(action: "advance", destination: nextStep)

        // Welcome now carries the Nora/value setup in production, so skip the
        // old standalone intro card there. Demo mode keeps it visible so the
        // Screen Demo can review every onboarding surface.
        if !isDemoMode, nextStep == .meetNora {
            currentStep = nextStep
            advance()
            return
        }

        if isDemoMode, [.coachAssignedPlan, .fwpMacrosHandoff].contains(nextStep) {
            currentStep = nextStep
            advance()
            return
        }

        // When the user accepted the coach plan, skip everything
        // between FWP handoff and `.commitTrial` — the macros are
        // already set from the trainer's plan and we don't want the
        // member doing biometrics or sitting through generate /
        // prediction / planReady screens for a plan they've already
        // accepted.
        if usingCoachPlan,
           [.fwpMacrosHandoff, .sex, .age, .height, .currentWeight, .goalWeight,
            .pace, .activityLevel, .sportSelection, .dietaryPreference,
            .biggestStruggle, .generatingPlan, .prediction, .planReady, .features].contains(nextStep) {
            currentStep = nextStep
            advance()
            return
        }

        // The feature list now lives inside the purchase screen in production
        // so the post-reveal flow can move straight from value to conversion.
        if !isDemoMode, nextStep == .features {
            currentStep = nextStep
            advance()
            return
        }

        // When the user accepted FWP macros we skip the FWP-mirrored
        // biometric steps (sex/age/height/currentWeight/activityLevel)
        // since those are already populated from the shared User doc.
        if usingFWPMacros,
           [.sex, .age, .height, .currentWeight, .activityLevel].contains(nextStep) {
            currentStep = nextStep
            advance()
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = nextStep
        }
    }

    func back() {
        let prev = currentStep.rawValue - 1
        guard let prevStep = Step(rawValue: prev) else { return }

        if shouldSkip(step: prevStep),
           let destinationStep = Step(rawValue: prevStep.rawValue - 1) {
            trackCurrentOnboardingStepBack(destination: destinationStep)
            currentStep = prevStep
            back()
            return
        }

        if prevStep == .sportSelection,
           answers.activityLevel != .athlete,
           let destinationStep = Step(rawValue: prevStep.rawValue - 1) {
            trackCurrentOnboardingStepBack(destination: destinationStep)
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep = destinationStep
            }
            return
        }

        trackCurrentOnboardingStepBack(destination: prevStep)

        if !isDemoMode, prevStep == .meetNora {
            currentStep = prevStep
            back()
            return
        }

        if isDemoMode, [.coachAssignedPlan, .fwpMacrosHandoff].contains(prevStep) {
            currentStep = prevStep
            back()
            return
        }

        if usingCoachPlan,
           [.fwpMacrosHandoff, .sex, .age, .height, .currentWeight, .goalWeight,
            .pace, .activityLevel, .sportSelection, .dietaryPreference,
            .biggestStruggle, .generatingPlan, .prediction, .planReady, .features].contains(prevStep) {
            currentStep = prevStep
            back()
            return
        }

        if !isDemoMode, prevStep == .features {
            currentStep = prevStep
            back()
            return
        }

        if usingFWPMacros,
           [.sex, .age, .height, .currentWeight, .activityLevel].contains(prevStep) {
            currentStep = prevStep
            back()
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = prevStep
        }
    }

    private func shouldSkip(step: Step) -> Bool {
        switch step {
        case .primaryFocus:
            return onboardingExperienceVariant != .noraGuided
        case .goalWeight, .pace:
            // 16–17 are maintenance-only — no goal-weight target or pace.
            if let age = currentAge, age < 18 { return true }
            return false
        default:
            return false
        }
    }

    func refreshExperimentAssignmentIfNeeded() async {
        guard !isDemoMode else { return }
        guard onboardingExperienceVariantOverride == nil else { return }
        let assignment = await MacraPaywallExperimentService.fetchAndActivateAssignment()
        guard onboardingExperienceVariant != assignment.onboardingVariant else { return }
        onboardingExperienceVariant = assignment.onboardingVariant
    }

    func noraPrompt(for step: Step) -> String? {
        guard onboardingExperienceVariant == .noraGuided else { return nil }
        switch step {
        case .primaryFocus:
            if let focus = answers.primaryFocus {
                return "Good. I'll shape the plan around: \(focus.title.lowercased())."
            }
            return "First, tell me what you want food to help with most."
        case .sex:
            if answers.sex != nil { return "Got it. I only use this for the calorie estimate." }
            return "This keeps the starting target from being generic."
        case .age:
            if answers.birthdate != nil { return "Good. Age helps tighten the baseline." }
            return "Your age helps me estimate daily energy needs."
        case .height:
            if answers.heightCm != nil { return "Perfect. Height gives the estimate more shape." }
            return "Height keeps your targets anchored to your body."
        case .currentWeight:
            if answers.currentWeightKg != nil { return "That is the baseline, not a judgment." }
            return "Tell me where we are starting today."
        case .goalWeight:
            if answers.goalWeightKg != nil { return "Now I can map the path from here to there." }
            return "Choose the weight you want the plan to move toward."
        case .pace:
            if answers.pace != nil { return "I'll use that pace to keep the plan livable." }
            return "Pick the pace you can repeat on normal days."
        case .activityLevel:
            if answers.activityLevel != nil { return "I'll match the target to your actual week." }
            return "Your normal activity changes how much food fits."
        case .sportSelection:
            if let sportName = answers.sportName, !sportName.isEmpty {
                return "Great. I'll tune the plan around \(sportName.lowercased())."
            }
            return "If sport drives your week, I'll use it to tune fueling."
        case .dietaryPreference:
            if answers.dietaryPreference != nil { return "I'll keep meal ideas inside those boundaries." }
            return "Tell me any food boundaries you want respected."
        case .biggestStruggle:
            if answers.biggestStruggle != nil { return "That tells me where to coach hardest." }
            return "This is the part I'll help protect when real life gets messy."
        default:
            return nil
        }
    }

    func completeQuestionnaire() {
        guard !isFinishing else { return }

        if isDemoMode {
            isFinishing = true
            planMacros = Self.demoMacroRecommendation
            suggestedMealPlan = Self.demoMealPlan
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.isFinishing = false
                self.pendingOnboardingCompletionAction = "questionnaire_completed"
                self.advance()
            }
            return
        }

        isFinishing = true

        UserService.sharedInstance.saveMacraProfile(answers: answers) { _ in
            UserService.sharedInstance.markMacraOnboardingComplete { [weak self] _ in
                self?.saveMacroTargetsFromPrediction {
                    DispatchQueue.main.async {
                        self?.isFinishing = false
                        self?.pendingOnboardingCompletionAction = "questionnaire_completed"
                        self?.trackOnboardingProfileCompletedIfNeeded(action: "questionnaire_completed")
                        self?.advance()
                    }
                }
            }
        }
    }

    /// Called from the notification preferences step once the user confirms.
    /// This saves the commitment before purchase; schedules and welcome email
    /// activate only after subscription access is verified.
    func persistNotificationPreferences() {
        guard !isDemoMode else { return }

        let preferences = answers.notificationPreferences
        UserService.sharedInstance.saveMacraNotificationPreferences(preferences)
    }

    private func activateNotificationPreferencesAndNotifyWelcome() {
        guard !isDemoMode else { return }

        let preferences = answers.notificationPreferences
        NotificationService.sharedInstance.syncScheduledNotifications(with: preferences)
        UserService.sharedInstance.sendMacraWelcomeEmail()
    }

    func finishNotificationPreferencesAndAdvance() {
        pendingOnboardingCompletionAction = answers.notificationPreferences.hasAnyEnabled
            ? "notification_preferences_enabled"
            : "notification_preferences_skipped"
        advance()
    }

    private func saveMacroTargetsFromPrediction(completion: @escaping () -> Void) {
        guard let userId = UserService.sharedInstance.user?.id ?? Auth.auth().currentUser?.uid,
              !userId.isEmpty else {
            completion()
            return
        }

        // Resolve the recommendation to save: coach plan > FWP macros >
        // computed prediction. Coach plans were already persisted by
        // `acceptCoachPlan` -> `adoptCoachPlan`, but we re-save here
        // so the timestamp on the recommendation reflects when the
        // questionnaire actually completed.
        let recommendation: MacroRecommendation
        if (usingCoachPlan || usingFWPMacros), let existing = planMacros {
            recommendation = MacroRecommendation(
                userId: userId,
                calories: existing.calories,
                protein: existing.protein,
                carbs: existing.carbs,
                fat: existing.fat
            )
        } else if let prediction = MacraOnboardingPrediction.compute(from: answers) {
            recommendation = prediction.toMacroRecommendation(userId: userId)
        } else {
            completion()
            return
        }

        MacroRecommendationService.sharedInstance.saveMacroRecommendation(recommendation) { _ in
            // Mirror back to FWP (`user.macros["personal"]`) so the shared User doc
            // reflects whatever Macra's onboarding settled on — keeps all 3 apps in sync.
            let mirrored = MacroRecommendations(
                calories: recommendation.calories,
                protein: recommendation.protein,
                carbs: recommendation.carbs,
                fat: recommendation.fat
            )
            FWPHandoffService.mirrorToFWPPersonal(mirrored) { _ in
                completion()
            }
        }
    }

    func purchaseAndContinue(paywallMetadata: [String: Any] = [:]) {
        currentPurchasePaywallMetadata = paywallMetadata
        let offering = PurchaseService.sharedInstance.offering
        let decision = MacraPurchaseFlowResolver.decision(for: MacraPurchaseFlowInput(
            isPurchasing: isPurchasing,
            isDemoMode: isDemoMode,
            usesLivePurchasesInDemo: usesLivePurchasesInDemo,
            hasExistingSubscriptionAccess: hasExistingSubscriptionAccess,
            isLoadingPackages: offering.isLoadingPackages,
            packageLoadError: offering.packageLoadError,
            selectedPlan: selectedPlan
        ))

        switch decision {
        case .ignoreAlreadyPurchasing:
            return
        case .continueDemoAccess:
            purchaseError = nil
            continueAfterVerifiedAccess()
            return
        case .continueExistingAccess:
            continueWithExistingSubscriptionAccess()
            return
        case .blocked(let reason, let message):
            purchaseError = message
            trackPaywallCTABlocked(reason: reason.rawValue)
            return
        case .purchase(let plan):
            isPurchasing = true
            purchaseError = nil
            activePurchaseLogID = MacraPurchaseLogService.shared.recordAttempt(
                plan: plan,
                source: paywallAnalyticsSource,
                metadata: activePurchaseLogMetadata(channel: "storekit")
            )
            trackSubscriptionPurchaseAttempted(plan: plan)

            offering.purchase(plan) { [weak self] result in
                DispatchQueue.main.async {
                    self?.isPurchasing = false
                    switch result {
                    case .success:
                        self?.logPurchaseSuccess(plan: plan, channel: "storekit")
                        self?.trackSubscriptionStart(plan: plan)
                        self?.scheduleTrialEndingReminderIfRequested(plan: plan)
                        self?.verifySubscriptionAndContinue(plan: plan)
                    case .failure(let error):
                        if PurchaseService.sharedInstance.isPurchaseCanceledError(error) {
                            self?.logPurchaseCanceled(plan: plan, error: error, failureReason: "storekit_cancelled")
                            self?.trackSubscriptionPurchaseCancelled(plan: plan, error: error)
                            self?.purchaseError = nil
                            self?.purchaseCancellationFeedbackRequestID = UUID()
                            if let self {
                                NotificationCenter.default.post(
                                    name: .macraPaywallPurchaseCancelled,
                                    object: self,
                                    userInfo: ["purchaseLogID": self.activePurchaseLogID ?? ""]
                                )
                            }
                        } else if PurchaseService.sharedInstance.isAlreadySubscribedError(error) {
                            self?.logPurchaseFailed(plan: plan, error: error, failureReason: "already_subscribed")
                            self?.trackSubscriptionPurchaseAlreadyActive(plan: plan, error: error)
                            self?.syncExistingSubscriptionAndContinue()
                        } else {
                            self?.logPurchaseFailed(plan: plan, error: error, failureReason: "storekit_purchase_failed")
                            self?.trackSubscriptionPurchaseFailed(plan: plan, error: error)
                            self?.purchaseError = MacraUserFacingError.purchase(error)
                        }
                    }
                }
            }
        }
    }

    func continueWithExistingSubscriptionAccess() {
        guard !isPurchasing else { return }

        if isDemoMode {
            continueAfterVerifiedAccess()
            return
        }

        guard hasExistingSubscriptionAccess else {
            purchaseAndContinue()
            return
        }

        purchaseError = nil
        if !didTrackExistingSubscriptionAccessContinue {
            didTrackExistingSubscriptionAccessContinue = true
            MacraAnalyticsService.shared.trackExistingSubscriptionAccessContinued(source: paywallAnalyticsSource)
            MacraAnalyticsService.shared.trackSubscriptionAccessVerified(
                plan: nil,
                source: paywallAnalyticsSource,
                context: "existing_subscription_access",
                metadata: paywallFunnelAnalyticsMetadata
            )
        }
        continueAfterVerifiedAccess()
    }

    func restorePurchasesAndContinue() {
        guard !isPurchasing else { return }

        if isDemoMode && !usesLivePurchasesInDemo {
            purchaseError = nil
            continueAfterVerifiedAccess()
            return
        }

        isPurchasing = true
        purchaseError = nil
        if !isDemoMode {
            MacraAnalyticsService.shared.trackSubscriptionRestoreAttempted(source: paywallAnalyticsSource)
        }

        PurchaseService.sharedInstance.restoreSubscriptionStatus { [weak self] result in
            DispatchQueue.main.async {
                self?.isPurchasing = false
                self?.trackRestoreResult(result)
                self?.handleSubscriptionVerificationResult(
                    result,
                    inactiveMessage: "No active subscription found to restore."
                )
            }
        }
    }

    func completeWebSubscriptionAndContinue() {
        guard !isPurchasing else { return }

        isPurchasing = true
        purchaseError = "Finishing unlock..."

        UserService.sharedInstance.getUser { [weak self] refreshedUser, userError in
            PurchaseService.sharedInstance.checkSubscriptionStatus(forceRefresh: true) { result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isPurchasing = false

                    let refreshedHasAccess =
                        refreshedUser?.subscriptionType.grantsMacraAccess == true ||
                        UserService.sharedInstance.user?.subscriptionType.grantsMacraAccess == true ||
                        UserService.sharedInstance.isBetaUser
                    let purchaseServiceHasAccess: Bool
                    if case .success(true) = result {
                        purchaseServiceHasAccess = true
                    } else {
                        purchaseServiceHasAccess = false
                    }

                    if refreshedHasAccess || purchaseServiceHasAccess {
                        self.purchaseError = nil
                        self.scheduleTrialEndingReminderIfRequested(plan: self.selectedPlan)
                        MacraAnalyticsService.shared.trackSubscriptionAccessVerified(
                            plan: self.selectedPlan,
                            source: self.paywallAnalyticsSource,
                            context: "web_checkout_return",
                            metadata: self.paywallFunnelAnalyticsMetadata
                        )
                        self.continueAfterVerifiedAccess()
                        return
                    }

                    if let userError {
                        MacraAnalyticsService.shared.trackSubscriptionAccessVerificationFailed(
                            plan: self.selectedPlan,
                            source: self.paywallAnalyticsSource,
                            context: "web_checkout_return",
                            reason: "user_refresh_error",
                            error: userError,
                            metadata: self.paywallFunnelAnalyticsMetadata
                        )
                        self.purchaseError = MacraUserFacingError.purchase(userError)
                        return
                    }

                    switch result {
                    case .success(false):
                        MacraAnalyticsService.shared.trackSubscriptionAccessVerificationFailed(
                            plan: self.selectedPlan,
                            source: self.paywallAnalyticsSource,
                            context: "web_checkout_return",
                            reason: "web_checkout_access_not_active",
                            metadata: self.paywallFunnelAnalyticsMetadata
                        )
                        self.purchaseError = "Your web subscription was created, but access is still syncing. Close and reopen Macra or tap Restore Purchases in a moment."
                    case .failure(let error):
                        MacraAnalyticsService.shared.trackSubscriptionAccessVerificationFailed(
                            plan: self.selectedPlan,
                            source: self.paywallAnalyticsSource,
                            context: "web_checkout_return",
                            reason: "web_checkout_verification_error",
                            error: error,
                            metadata: self.paywallFunnelAnalyticsMetadata
                        )
                        self.purchaseError = MacraUserFacingError.purchase(error)
                    case .success(true):
                        break
                    }
                }
            }
        }
    }

    private func verifySubscriptionAndContinue(plan: SubscriptionPlanOption) {
        isPurchasing = true
        PurchaseService.sharedInstance.checkSubscriptionStatus(forceRefresh: true) { [weak self] result in
            DispatchQueue.main.async {
                self?.isPurchasing = false
                self?.trackSubscriptionVerificationResult(
                    result,
                    plan: plan,
                    context: "post_purchase",
                    inactiveReason: "purchase_access_not_active"
                )
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
                self?.trackSubscriptionVerificationResult(
                    result,
                    plan: self?.selectedPlan,
                    context: "already_subscribed_sync",
                    inactiveReason: "already_subscribed_access_not_active"
                )
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
            continueAfterVerifiedAccess()
        case .success(false):
            purchaseError = inactiveMessage
        case .failure(let error):
            purchaseError = MacraUserFacingError.purchase(error)
        }
    }

    private func continueAfterVerifiedAccess() {
        purchaseError = nil

        if isDemoMode {
            onDemoDismiss?()
            return
        }

        guard currentStep == .commitTrial, startingStep != .commitTrial else {
            trackCurrentOnboardingStepCompleted(action: "access_verified", destination: nil)
            trackOnboardingCompletedIfNeeded(action: "access_verified")
            appCoordinator.showHomeScreen()
            return
        }

        pendingOnboardingCompletionAction = "access_verified"
        advance()
    }

    private func completeOnboardingAndEnterApp(action: String) {
        trackOnboardingCompletedIfNeeded(action: action)
        activateNotificationPreferencesAndNotifyWelcome()
        appCoordinator.showHomeScreen()
    }
}

private extension MacraOnboardingCoordinator.Step {
    var analyticsId: String {
        switch self {
        case .welcome: return "welcome"
        case .primaryFocus: return "primary_focus"
        case .meetNora: return "meet_nora"
        case .coachAssignedPlan: return "coach_assigned_plan"
        case .fwpMacrosHandoff: return "fwp_macros_handoff"
        case .sex: return "sex"
        case .age: return "age"
        case .height: return "height"
        case .currentWeight: return "current_weight"
        case .goalWeight: return "goal_weight"
        case .pace: return "pace"
        case .activityLevel: return "activity_level"
        case .sportSelection: return "sport_selection"
        case .dietaryPreference: return "dietary_preference"
        case .biggestStruggle: return "biggest_struggle"
        case .generatingPlan: return "generating_plan"
        case .prediction: return "prediction"
        case .planReady: return "plan_ready"
        case .features: return "features"
        case .commitTrial: return "commit_trial"
        case .activationStart: return "activation_start"
        case .notificationPreferences: return "notification_preferences"
        }
    }

    var analyticsName: String {
        switch self {
        case .welcome: return "Welcome"
        case .primaryFocus: return "Primary focus"
        case .meetNora: return "Meet Nora"
        case .coachAssignedPlan: return "Coach assigned plan"
        case .fwpMacrosHandoff: return "FWP macros handoff"
        case .sex: return "Sex"
        case .age: return "Age"
        case .height: return "Height"
        case .currentWeight: return "Current weight"
        case .goalWeight: return "Goal weight"
        case .pace: return "Pace"
        case .activityLevel: return "Activity level"
        case .sportSelection: return "Sport selection"
        case .dietaryPreference: return "Dietary preference"
        case .biggestStruggle: return "Biggest struggle"
        case .generatingPlan: return "Generating plan"
        case .prediction: return "Prediction"
        case .planReady: return "Plan ready"
        case .features: return "Features"
        case .commitTrial: return "Commit trial"
        case .activationStart: return "Activation start"
        case .notificationPreferences: return "Notification preferences"
        }
    }

    var noraNarration: String {
        switch self {
        case .welcome:
            return "Welcome to Macra. I am Nora. I will help turn your goal into numbers, meals, and decisions you can actually follow."
        case .primaryFocus:
            return "Before the numbers, tell me what you want food to help with most. I will use that to shape the plan around your real life."
        case .meetNora:
            return "I am here to make food feel less random. Answer a few questions, and I will shape the plan around your body and your life."
        case .coachAssignedPlan:
            return "I found a coach assigned plan for you. If this is the plan you want to use, I can bring it into Macra and keep your nutrition aligned."
        case .fwpMacrosHandoff:
            return "I found macro targets from your Fit With Pulse profile. You can use those here, or we can reassess them together."
        case .sex:
            return "First, choose the biological sex you want me to use for your calorie and macro estimate."
        case .age:
            return "Next, add your age. This helps me estimate your baseline needs more accurately."
        case .height:
            return "Now add your height. I use it with your weight and activity to build a better starting target."
        case .currentWeight:
            return "Tell me where you are starting today. This is just the baseline, not a judgment."
        case .goalWeight:
            return "Now choose the weight you want to move toward. I will use this to shape the pace of your plan."
        case .pace:
            return "Pick the pace that feels sustainable. Faster is not always better if it makes the plan harder to live with."
        case .activityLevel:
            return "Choose the activity level that best matches your normal week. If you regularly play a sport, choose athlete and I will ask which one."
        case .sportSelection:
            return "Choose the sport you play most often. I will use it to tune fueling, training days, and game day recommendations."
        case .dietaryPreference:
            return "Tell me any dietary preference you want respected. I will tailor meal suggestions around it."
        case .biggestStruggle:
            return "Choose the thing that usually breaks the plan for you. This tells me where to coach hardest."
        case .generatingPlan:
            return "I am turning your answers into a calorie target, macro targets, and a simple starting plan."
        case .prediction:
            return "Here is the projected path. These numbers are a starting point, and I will adapt as your real logs come in."
        case .planReady:
            return "I start with simple meals that fit your numbers. The more you log, the more I learn what you like, what you dislike, and how to make the plan more personal."
        case .features:
            return "These are the tools I will use with you: photo logging, macro targets, labels, meal planning, and daily coaching."
        case .notificationPreferences:
            return "Before you unlock Macra, choose when you want me to pull you back on track. This is your first commitment to the plan."
        case .commitTrial:
            return "Your plan is ready. Unlock Macra to start using your targets, meal plan, scanner, and Nora coaching."
        case .activationStart:
            return "Your plan is active. Start with one meal, and I will use that first signal to tune the rest of today."
        }
    }
}

struct MacraOnboardingFlowView: View {
    @StateObject private var coordinator: MacraOnboardingCoordinator
    @ObservedObject private var noraVoice = MacraNoraVoiceService.shared
    private let existingSubscriptionAccessOverride: Bool?
    private let paywallDefaultPlanSelectionOverride: MacraPaywallDefaultPlanSelection?
    private let paywallLayoutVariantOverride: MacraPaywallLayoutVariant?
    private let onboardingExperienceVariantOverride: MacraOnboardingExperienceVariant?

    init(
        appCoordinator: AppCoordinator,
        startingStep: MacraOnboardingCoordinator.Step = .welcome,
        isDemoMode: Bool = false,
        usesLivePurchasesInDemo: Bool = false,
        onDemoDismiss: (() -> Void)? = nil,
        existingSubscriptionAccessOverride: Bool? = nil,
        paywallDefaultPlanSelectionOverride: MacraPaywallDefaultPlanSelection? = nil,
        paywallLayoutVariantOverride: MacraPaywallLayoutVariant? = nil,
        onboardingExperienceVariantOverride: MacraOnboardingExperienceVariant? = nil
    ) {
        self.existingSubscriptionAccessOverride = existingSubscriptionAccessOverride
        self.paywallDefaultPlanSelectionOverride = paywallDefaultPlanSelectionOverride
        self.paywallLayoutVariantOverride = paywallLayoutVariantOverride
        self.onboardingExperienceVariantOverride = onboardingExperienceVariantOverride
        _coordinator = StateObject(wrappedValue: MacraOnboardingCoordinator(
            appCoordinator: appCoordinator,
            startingStep: startingStep,
            isDemoMode: isDemoMode,
            usesLivePurchasesInDemo: usesLivePurchasesInDemo,
            onDemoDismiss: onDemoDismiss,
            existingSubscriptionAccessOverride: existingSubscriptionAccessOverride,
            paywallDefaultPlanSelectionOverride: paywallDefaultPlanSelectionOverride,
            paywallLayoutVariantOverride: paywallLayoutVariantOverride,
            onboardingExperienceVariantOverride: onboardingExperienceVariantOverride
        ))
    }

    var body: some View {
        Group {
            switch coordinator.currentStep {
            case .welcome:
                WelcomeStepView(coordinator: coordinator)
            case .primaryFocus:
                PrimaryFocusStepView(coordinator: coordinator)
            case .meetNora:
                MeetNoraStepView(coordinator: coordinator)
            case .coachAssignedPlan:
                CoachAssignedPlanStepView(coordinator: coordinator)
            case .fwpMacrosHandoff:
                FWPMacrosHandoffStepView(coordinator: coordinator)
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
            case .sportSelection:
                SportSelectionStepView(coordinator: coordinator)
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
            case .activationStart:
                TrialActivationStartStepView(coordinator: coordinator)
            }
        }
        .overlay(alignment: .topTrailing) {
            NoraVoiceToggleButton(
                isEnabled: noraVoice.isEnabled,
                voiceLevel: noraVoice.voiceLevel
            ) {
                toggleNoraVoice()
            }
            .padding(.top, 8)
            .padding(.trailing, 20)
        }
        .overlay {
            if coordinator.ageGateBlocked {
                MacraAgeGateBlockedView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.ageGateBlocked)
        .onAppear {
            coordinator.existingSubscriptionAccessOverride = existingSubscriptionAccessOverride
            coordinator.trackCurrentOnboardingStepViewed(trigger: "flow_appeared")
            MacraNoraVoiceService.shared.preloadOnboardingNarrations()
            preloadLikelyNarrations()
            narrateCurrentStep()
        }
        .onChange(of: existingSubscriptionAccessOverride) { newValue in
            coordinator.existingSubscriptionAccessOverride = newValue
        }
        .task {
            await coordinator.refreshExperimentAssignmentIfNeeded()
        }
        .onChange(of: coordinator.currentStep) { _ in
            coordinator.trackCurrentOnboardingStepViewed(trigger: "step_changed")
            preloadLikelyNarrations()
            narrateCurrentStep()
        }
        .onChange(of: coordinator.answers.primaryFocus) { _ in
            narratePrimaryFocusSelectionIfNeeded()
        }
        .onDisappear {
            MacraNoraVoiceService.shared.stop()
        }
    }

    private func toggleNoraVoice() {
        let shouldEnable = !noraVoice.isEnabled
        MacraNoraVoiceService.shared.setEnabled(shouldEnable)
        guard shouldEnable else { return }
        narrateCurrentStep(force: true)
    }

    private func narrateCurrentStep(force: Bool = false) {
        let step = coordinator.currentStep
        let narration = step.noraNarration

        MacraNoraVoiceService.shared.narrateOnboarding(
            stepId: step.analyticsId,
            fallbackText: narration,
            key: "macra_onboarding_\(step.analyticsId)",
            force: force
        )
    }

    private func preloadLikelyNarrations() {
        var stepIds = [coordinator.currentStep.analyticsId]

        if let nextStep = MacraOnboardingCoordinator.Step(rawValue: coordinator.currentStep.rawValue + 1) {
            stepIds.append(nextStep.analyticsId)
        }

        if coordinator.currentStep == .welcome || coordinator.currentStep == .primaryFocus {
            stepIds.append(contentsOf: MacraPrimaryFocus.allCases.map {
                "primary_focus_selection_\($0.rawValue)"
            })
        }

        MacraNoraVoiceService.shared.preloadOnboardingNarrations(stepIds: stepIds)
    }

    private func narratePrimaryFocusSelectionIfNeeded() {
        guard coordinator.currentStep == .primaryFocus,
              let focus = coordinator.answers.primaryFocus,
              let prompt = coordinator.noraPrompt(for: .primaryFocus) else { return }

        MacraNoraVoiceService.shared.narrateOnboarding(
            stepId: "primary_focus_selection_\(focus.rawValue)",
            fallbackText: prompt,
            key: "macra_onboarding_primary_focus_\(focus.rawValue)",
            force: true
        )
    }
}

/// Terminal block shown when an under-16 user reaches the age step. Macra builds
/// calorie/weight-management plans, so under-16s cannot proceed (COPPA + eating-
/// disorder safety). 16–17 pass through but are forced to maintenance-only macros.
private struct MacraAgeGateBlockedView: View {
    var body: some View {
        ZStack {
            MacraChromaticBackground()
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.primaryGreen)

                Text("Macra is for ages 16 and up")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Thanks for your interest! Macra builds calorie and nutrition plans designed for older users, so we can’t set you up just yet. Please check back when you’re a little older.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    try? Auth.auth().signOut()
                } label: {
                    Text("Sign out")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .padding(.top, 8)
            }
            .padding(28)
        }
    }
}
