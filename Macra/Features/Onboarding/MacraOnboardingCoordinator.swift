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
        case commitTrial
        case notificationPreferences
    }

    enum FWPHandoffState: Equatable {
        case checking
        case unavailable
        case available(MacroRecommendations)
        case accepted
        case reassessing
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
    @Published var fwpHandoffState: FWPHandoffState = .checking
    /// True when the user accepted FWP macros — skip biometric steps + use FWP macros verbatim.
    private(set) var usingFWPMacros: Bool = false
    private var trackedPaywallViewSources: Set<String> = []

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

    let appCoordinator: AppCoordinator
    let startingStep: Step
    let isDemoMode: Bool
    private let onDemoDismiss: (() -> Void)?

    init(
        appCoordinator: AppCoordinator,
        startingStep: Step = .welcome,
        isDemoMode: Bool = false,
        onDemoDismiss: (() -> Void)? = nil
    ) {
        self.appCoordinator = appCoordinator
        self.startingStep = startingStep
        self.currentStep = startingStep
        self.isDemoMode = isDemoMode
        self.onDemoDismiss = onDemoDismiss

        if isDemoMode {
            self.answers = Self.demoAnswers
            self.planMacros = Self.demoMacroRecommendation
            self.suggestedMealPlan = Self.demoMealPlan
        }
    }

    private static var demoAnswers: MacraOnboardingAnswers {
        var answers = MacraOnboardingAnswers()
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
                    notes: "This is the ad-friendly reveal meal: easy to scan and easy to adjust.",
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
            notes: "Demo plan only. Shows the full onboarding reveal without calling the meal-plan service."
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
                trialDays: nil,
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
        case .welcome, .generatingPlan, .notificationPreferences:
            return false
        default:
            return currentStep.rawValue > 0
        }
    }

    var canGoForward: Bool {
        switch currentStep {
        case .welcome: return true
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
        if isDemoMode { return Self.demoPlanOptions }
        return PurchaseService.sharedInstance.offering.planOptions
    }

    var selectedPackage: PackageViewModel? {
        return selectedPlan?.packageViewModel
    }

    func selectPlan(_ plan: SubscriptionPlanOption) {
        selectedPackageId = plan.id
    }

    func ensureOfferingsLoaded(force: Bool = false) {
        guard !isDemoMode else {
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
            await offering.start()
            if self.currentStep == .commitTrial {
                self.trackPaywallViewedIfNeeded()
            }
        }
    }

    func trackPaywallViewedIfNeeded(source: String? = nil) {
        guard !isDemoMode else { return }

        let resolvedSource = source ?? paywallAnalyticsSource
        guard !trackedPaywallViewSources.contains(resolvedSource) else { return }

        trackedPaywallViewSources.insert(resolvedSource)
        let offering = PurchaseService.sharedInstance.offering
        MacraAnalyticsService.shared.trackPaywallViewed(
            source: resolvedSource,
            selectedPlan: selectedPlan,
            availablePlans: offering.planOptions
        )
    }

    private var paywallAnalyticsSource: String {
        startingStep == .commitTrial ? "subscription_required" : "onboarding"
    }

    private func trackSubscriptionStart(plan: SubscriptionPlanOption) {
        MacraAnalyticsService.shared.trackSubscriptionStart(plan: plan, source: paywallAnalyticsSource)
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
        advance()
    }

    /// User tapped "Reassess" — keep the pre-populated answers as starting values
    /// and proceed through the biometric steps normally.
    func reassessAfterHandoff() {
        usingFWPMacros = false
        fwpHandoffState = .reassessing
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
        advance()
    }

    /// User tapped "Build my own plan instead" — proceed through the
    /// normal biometrics + analyze flow, leaving the coach plan
    /// untouched on the Pulse side.
    func declineCoachPlan() {
        usingCoachPlan = false
        coachPlanState = .unavailable
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

        if nextStep == .sportSelection, answers.activityLevel != .athlete {
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

        if prevStep == .sportSelection, answers.activityLevel != .athlete {
            currentStep = prevStep
            back()
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = prevStep
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
        guard !isDemoMode else { return }

        let preferences = answers.notificationPreferences
        UserService.sharedInstance.saveMacraNotificationPreferences(preferences)
        NotificationService.sharedInstance.syncScheduledNotifications(with: preferences)
        UserService.sharedInstance.sendMacraWelcomeEmail()
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

    func dismissPaywall() {
        if isDemoMode {
            onDemoDismiss?()
            return
        }

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

        if isDemoMode {
            purchaseError = nil
            continueAfterVerifiedAccess()
            return
        }

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
                    self?.trackSubscriptionStart(plan: plan)
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

        if isDemoMode {
            purchaseError = nil
            continueAfterVerifiedAccess()
            return
        }

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
            continueAfterVerifiedAccess()
        case .success(false):
            purchaseError = inactiveMessage
        case .failure(let error):
            purchaseError = error.localizedDescription
        }
    }

    private func continueAfterVerifiedAccess() {
        purchaseError = nil

        guard currentStep == .commitTrial, startingStep != .commitTrial else {
            appCoordinator.showHomeScreen()
            return
        }

        advance()
    }
}

struct MacraOnboardingFlowView: View {
    @StateObject private var coordinator: MacraOnboardingCoordinator

    init(
        appCoordinator: AppCoordinator,
        startingStep: MacraOnboardingCoordinator.Step = .welcome,
        isDemoMode: Bool = false,
        onDemoDismiss: (() -> Void)? = nil
    ) {
        _coordinator = StateObject(wrappedValue: MacraOnboardingCoordinator(
            appCoordinator: appCoordinator,
            startingStep: startingStep,
            isDemoMode: isDemoMode,
            onDemoDismiss: onDemoDismiss
        ))
    }

    var body: some View {
        Group {
            switch coordinator.currentStep {
            case .welcome:
                WelcomeStepView(coordinator: coordinator)
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
            case .commitTrial:
                CommitTrialStepView(coordinator: coordinator)
            case .notificationPreferences:
                NotificationPreferencesStepView(coordinator: coordinator)
            }
        }
    }
}
