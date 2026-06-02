import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import SafariServices
import SwiftUI
import UIKit

extension Notification.Name {
    static let macraPaywallPurchaseCancelled = Notification.Name("MacraPaywallPurchaseCancelled")
}

class PayWallViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator

    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }
}

private struct WebCheckoutSheet: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SafariCheckoutView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

enum MacraPaywallDefaultPlanSelection: String {
    case annual
    case monthly

    var prefersMonthlyFirst: Bool {
        self == .monthly
    }

    var analyticsVariantName: String {
        switch self {
        case .annual: return "annual_default_v1"
        case .monthly: return "monthly_default_v1"
        }
    }

    var defaultReason: String {
        switch self {
        case .annual: return "remote_config_annual_default"
        case .monthly: return "remote_config_monthly_default"
        }
    }

    static func normalized(_ rawValue: String?) -> Self {
        guard let value = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !value.isEmpty else {
            return .annual
        }
        return Self(rawValue: value) ?? .annual
    }
}

enum MacraPaywallLayoutVariant: String {
    case control = "trial_confidence_control"
    case trialConfidence = "trial_confidence_legacy"
    case trialPrepCompact = "trial_confidence"
    case hardPaywallValue = "hard_paywall_value"

    var analyticsVariantName: String {
        switch self {
        case .control: return rawValue
        case .trialConfidence: return rawValue
        case .trialPrepCompact: return rawValue
        case .hardPaywallValue: return rawValue
        }
    }

    static func normalized(_ rawValue: String?) -> Self {
        guard let value = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_"),
              !value.isEmpty else {
            return .trialPrepCompact
        }

        switch value {
        case "trial_confidence", "trialconfidence", "variant_b", "compact", "compact_paywall", "trial_confidence_compact", "multi_screen_compact":
            return .trialPrepCompact
        case "hard_paywall_value", "hard_paywall", "paid_value", "paid_plan_value", "variant_c", "value_hard_paywall":
            return .hardPaywallValue
        case "trial_confidence_legacy", "confidence", "trial_confidence_v1":
            return .trialConfidence
        case "trial_confidence_control", "control", "baseline", "control_v1":
            return .control
        default:
            return Self(rawValue: value) ?? .trialPrepCompact
        }
    }
}

struct MacraPaywallExperimentAssignment {
    let defaultPlanSelection: MacraPaywallDefaultPlanSelection
    let layoutVariant: MacraPaywallLayoutVariant
    let onboardingVariant: MacraOnboardingExperienceVariant
    let experimentId: String
    let variantId: String
    let variantName: String
    let assignmentSource: String
    let parameters: [String: String]
}

enum MacraPaywallExperimentService {
    static let defaultPlanParameterKey = "macra_paywall_default_plan"
    static let layoutVariantParameterKey = "macra_paywall_layout_variant"
    static let onboardingVariantParameterKey = MacraOnboardingExperienceVariant.parameterKey
    static let collectionName = "macra-experiments"
    static let documentId = "macra_paywall_onboarding"

    private static let installIdDefaultsKey = "macra_experiment_install_id"
    private static let lastAssignmentDefaultsKey = "macra_experiment_last_paywall_onboarding_assignment"

    static func cachedDefaultPlanSelection() -> MacraPaywallDefaultPlanSelection {
        cachedAssignment().defaultPlanSelection
    }

    static func cachedLayoutVariant() -> MacraPaywallLayoutVariant {
        cachedAssignment().layoutVariant
    }

    static func cachedAssignment() -> MacraPaywallExperimentAssignment {
        guard let cached = readCachedAssignment(forKey: lastAssignmentDefaultsKey) else {
            return defaultAssignment(source: "local_default")
        }
        return assignment(
            experimentId: cached.experimentId,
            variantId: cached.variantId,
            variantName: cached.variantName,
            parameters: cached.parameters,
            source: "local_cache"
        )
    }

    static func fetchAndActivateDefaultPlanSelection() async -> MacraPaywallDefaultPlanSelection {
        await fetchAndActivateAssignment().defaultPlanSelection
    }

    static func fetchAndActivateAssignment() async -> MacraPaywallExperimentAssignment {
        guard FirebaseApp.app() != nil else {
            return cachedAssignment()
        }

        do {
            let snapshot = try await fetchExperimentSnapshot()
            guard let config = ExperimentConfig(id: documentId, data: snapshot.data() ?? [:]),
                  config.isEnabled,
                  !config.enabledVariants.isEmpty else {
                return cachedAssignment()
            }

            let variant = stickyVariant(for: config)
            let assignment = assignment(
                experimentId: config.id,
                variantId: variant.id,
                variantName: variant.name,
                parameters: variant.parameters,
                source: "firestore_experiment"
            )
            cacheAssignment(assignment, salt: config.salt)
            MacraAnalyticsService.shared.trackMacraExperimentAssignment(
                experimentId: assignment.experimentId,
                variantId: assignment.variantId,
                variantName: assignment.variantName,
                defaultPlan: assignment.defaultPlanSelection.rawValue,
                layoutVariant: assignment.layoutVariant.rawValue,
                onboardingVariant: assignment.onboardingVariant.rawValue,
                source: assignment.assignmentSource,
                metadata: [
                    "experiment_collection": collectionName,
                    "experiment_document_id": documentId,
                    "experiment_salt": config.salt
                ]
            )
            return assignment
        } catch {
            print("[Macra][Experiment] Firestore assignment fetch failed: \(error.localizedDescription)")
            return cachedAssignment()
        }
    }

    static func prefetch() {
        Task {
            _ = await fetchAndActivateAssignment()
        }
    }

    private static func fetchExperimentSnapshot() async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            Firestore.firestore()
                .collection(collectionName)
                .document(documentId)
                .getDocument { snapshot, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let snapshot {
                        continuation.resume(returning: snapshot)
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "MacraExperimentService",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Experiment document did not return a snapshot."]
                        ))
                    }
                }
        }
    }

    private static func defaultAssignment(source: String) -> MacraPaywallExperimentAssignment {
        assignment(
            experimentId: documentId,
            variantId: "variant_a",
            variantName: "Trial prep compact",
            parameters: [
                defaultPlanParameterKey: MacraPaywallDefaultPlanSelection.annual.rawValue,
                layoutVariantParameterKey: MacraPaywallLayoutVariant.trialPrepCompact.rawValue,
                onboardingVariantParameterKey: MacraOnboardingExperienceVariant.standard.rawValue
            ],
            source: source
        )
    }

    private static func assignment(
        experimentId: String,
        variantId: String,
        variantName: String,
        parameters: [String: String],
        source: String
    ) -> MacraPaywallExperimentAssignment {
        MacraPaywallExperimentAssignment(
            defaultPlanSelection: MacraPaywallDefaultPlanSelection.normalized(parameters[defaultPlanParameterKey]),
            layoutVariant: MacraPaywallLayoutVariant.normalized(parameters[layoutVariantParameterKey]),
            onboardingVariant: MacraOnboardingExperienceVariant.normalized(parameters[onboardingVariantParameterKey]),
            experimentId: experimentId,
            variantId: variantId,
            variantName: variantName,
            assignmentSource: source,
            parameters: parameters
        )
    }

    private static func stickyVariant(for config: ExperimentConfig) -> ExperimentVariantConfig {
        let cacheKey = assignmentCacheKey(experimentId: config.id, salt: config.salt)
        if let cached = readCachedAssignment(forKey: cacheKey),
           let cachedVariant = config.enabledVariants.first(where: { $0.id == cached.variantId }) {
            return cachedVariant
        }

        let totalWeight = config.enabledVariants.reduce(0.0) { $0 + max(0, $1.weight) }
        guard totalWeight > 0 else { return config.enabledVariants[0] }

        let bucket = deterministicBucket(
            key: "\(config.id):\(config.salt):\(stableSubjectId())"
        )
        let target = bucket * totalWeight
        var cumulative = 0.0
        for variant in config.enabledVariants {
            cumulative += max(0, variant.weight)
            if target <= cumulative {
                return variant
            }
        }
        return config.enabledVariants.last ?? config.enabledVariants[0]
    }

    private static func deterministicBucket(key: String) -> Double {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Double(hash % 1_000_000) / 1_000_000.0
    }

    private static func stableSubjectId() -> String {
        if let uid = Auth.auth().currentUser?.uid, !uid.isEmpty {
            return "user:\(uid)"
        }
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: installIdDefaultsKey), !existing.isEmpty {
            return "install:\(existing)"
        }
        let installId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        defaults.set(installId, forKey: installIdDefaultsKey)
        return "install:\(installId)"
    }

    private static func assignmentCacheKey(experimentId: String, salt: String) -> String {
        "macra_experiment_assignment_\(experimentId)_\(salt)"
    }

    private static func cacheAssignment(_ assignment: MacraPaywallExperimentAssignment, salt: String) {
        let cached = CachedExperimentAssignment(
            experimentId: assignment.experimentId,
            variantId: assignment.variantId,
            variantName: assignment.variantName,
            parameters: assignment.parameters,
            salt: salt,
            assignedAt: Date().timeIntervalSince1970
        )
        writeCachedAssignment(cached, forKey: assignmentCacheKey(experimentId: assignment.experimentId, salt: salt))
        writeCachedAssignment(cached, forKey: lastAssignmentDefaultsKey)
    }

    private static func readCachedAssignment(forKey key: String) -> CachedExperimentAssignment? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CachedExperimentAssignment.self, from: data)
    }

    private static func writeCachedAssignment(_ assignment: CachedExperimentAssignment, forKey key: String) {
        guard let data = try? JSONEncoder().encode(assignment) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct ExperimentConfig {
    let id: String
    let isEnabled: Bool
    let salt: String
    let variants: [ExperimentVariantConfig]

    var enabledVariants: [ExperimentVariantConfig] {
        variants.filter { $0.isEnabled && $0.weight > 0 }
    }

    init?(id: String, data: [String: Any]) {
        self.id = (data["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? id
        self.isEnabled = data["isEnabled"] as? Bool ?? data["enabled"] as? Bool ?? false
        self.salt = (data["assignmentSalt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (data["salt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? MacraPaywallExperimentService.documentId

        let rawVariants = data["variants"] as? [[String: Any]] ?? []
        self.variants = rawVariants.compactMap(ExperimentVariantConfig.init(data:))
    }
}

private struct ExperimentVariantConfig {
    let id: String
    let name: String
    let weight: Double
    let isEnabled: Bool
    let parameters: [String: String]

    init?(data: [String: Any]) {
        guard let id = (data["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        self.id = id
        self.name = (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? (data["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? id
        self.weight = Self.doubleValue(from: data["weight"]) ?? Self.doubleValue(from: data["rolloutWeight"]) ?? 0
        self.isEnabled = data["isEnabled"] as? Bool ?? data["enabled"] as? Bool ?? true

        let rawParameters = data["parameters"] as? [String: Any] ?? [:]
        self.parameters = rawParameters.reduce(into: [String: String]()) { result, entry in
            if let value = entry.value as? String {
                result[entry.key] = value
            } else if let value = entry.value as? CustomStringConvertible {
                result[entry.key] = value.description
            }
        }
    }

    private static func doubleValue(from value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

private struct CachedExperimentAssignment: Codable {
    let experimentId: String
    let variantId: String
    let variantName: String
    let parameters: [String: String]
    let salt: String
    let assignedAt: Double
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum PaywallCancelFeedbackReason: String, CaseIterable, Identifiable {
    case priceTooHigh = "price_too_high"
    case notReady = "not_ready"
    case needMoreProof = "need_more_proof"
    case appleSheetConfusing = "apple_sheet_confusing"
    case wrongPlan = "wrong_plan"
    case somethingDidNotWork = "something_did_not_work"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .priceTooHigh: return "Price felt too high"
        case .notReady: return "I'm not ready yet"
        case .needMoreProof: return "I need more proof first"
        case .appleSheetConfusing: return "Apple's sheet was confusing"
        case .wrongPlan: return "I wanted a different plan"
        case .somethingDidNotWork: return "Something did not work"
        }
    }
}

private enum CompactPaywallStep: String {
    case trialWorks = "trial_works"
    case firstSevenDays = "first_seven_days"
    case trialReminder = "trial_reminder"
    case plans = "plans"

    var next: CompactPaywallStep? {
        switch self {
        case .trialWorks:
            return .firstSevenDays
        case .firstSevenDays:
            return .trialReminder
        case .trialReminder:
            return .plans
        case .plans: return nil
        }
    }

    var previous: CompactPaywallStep? {
        switch self {
        case .trialWorks: return nil
        case .firstSevenDays:
            return .trialWorks
        case .trialReminder:
            return .firstSevenDays
        case .plans:
            return .trialReminder
        }
    }
}

struct PayWallView: View {
    @ObservedObject private var offeringViewModel = PurchaseService.sharedInstance.offering
    @ObservedObject var viewModel: PayWallViewModel
    private static let webCheckoutAnnualPriceID = "price_1PDq3LRobSf56MUOng0UxhCC"
    @State private var paywallDefaultPlanSelection: MacraPaywallDefaultPlanSelection
    @State private var paywallLayoutVariant: MacraPaywallLayoutVariant
    @State private var paywallExperimentAssignment: MacraPaywallExperimentAssignment
    @State private var didTrackPaywallView = false
    @State private var didTrackExistingAccessView = false
    @State private var didTrackPaywallValuePreviewView = false
    @State private var didTrackPricingDisclosureView = false
    @State private var didTrackTrialConfidenceView = false
    @State private var didTrackWebCheckoutFallbackPresented = false
    @State private var didTrackPaywallDismissed = false
    @State private var paywallAppearedAt: Date?
    @State private var standaloneSelectedPlanID: String?
    @State private var standalonePurchaseError: String?
    @State private var isStandalonePurchasing = false
    @State private var webCheckoutSheet: WebCheckoutSheet?
    @State private var isWebCheckoutCompleting = false
    @State private var isPreparingWebCheckout = false
    @State private var isVerifyingSubscriptionAccess = false
    @State private var showSubscriptionSuccess = false
    @State private var didTrackSubscriptionSuccessActivationView = false
    @State private var didTrackSubscriptionSuccessActivationPrimary = false
    @State private var showAppleConfirmationBridge = false
    @State private var showCancelFeedbackDialog = false
    @State private var cancelFeedbackTrigger = "unknown"
    @State private var didAskCancelFeedback = false
    @State private var didSubmitCancelFeedback = false
    @State private var activePurchaseLogID: String?
    @State private var cancelFeedbackPresentationTask: Task<Void, Never>?
    @State private var compactPaywallStep: CompactPaywallStep = .trialWorks
    @State private var selectedTrialReminderLeadDays = 2
    private let isDemoMode: Bool
    private let usesLivePurchasesInDemo: Bool
    private let onboardingCoordinator: MacraOnboardingCoordinator?
    private let onDismiss: (() -> Void)?
    private let existingSubscriptionAccessOverride: Bool?
    private let defaultPlanSelectionOverride: MacraPaywallDefaultPlanSelection?
    private let layoutVariantOverride: MacraPaywallLayoutVariant?
    private let presentsCancelFeedbackOnAppear: Bool
    private let persistsCancelFeedbackInDemo: Bool

    init(
        viewModel: PayWallViewModel,
        isDemoMode: Bool = false,
        usesLivePurchasesInDemo: Bool = false,
        onboardingCoordinator: MacraOnboardingCoordinator? = nil,
        onDismiss: (() -> Void)? = nil,
        existingSubscriptionAccessOverride: Bool? = nil,
        defaultPlanSelectionOverride: MacraPaywallDefaultPlanSelection? = nil,
        layoutVariantOverride: MacraPaywallLayoutVariant? = nil,
        presentsCancelFeedbackOnAppear: Bool = false,
        persistsCancelFeedbackInDemo: Bool = false
    ) {
        let cachedAssignment = MacraPaywallExperimentService.cachedAssignment()
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._paywallDefaultPlanSelection = State(initialValue: defaultPlanSelectionOverride ?? cachedAssignment.defaultPlanSelection)
        self._paywallLayoutVariant = State(initialValue: layoutVariantOverride ?? cachedAssignment.layoutVariant)
        self._paywallExperimentAssignment = State(initialValue: cachedAssignment)
        self.isDemoMode = isDemoMode
        self.usesLivePurchasesInDemo = usesLivePurchasesInDemo
        self.onboardingCoordinator = onboardingCoordinator
        self.onDismiss = onDismiss
        self.existingSubscriptionAccessOverride = existingSubscriptionAccessOverride
        self.defaultPlanSelectionOverride = defaultPlanSelectionOverride
        self.layoutVariantOverride = layoutVariantOverride
        self.presentsCancelFeedbackOnAppear = presentsCancelFeedbackOnAppear
        self.persistsCancelFeedbackInDemo = persistsCancelFeedbackInDemo
    }

    private var shouldUseDemoPlans: Bool {
        isDemoMode && !usesLivePurchasesInDemo
    }

    private var shouldTrackPaywallAnalytics: Bool {
        !isDemoMode
    }

    private var shouldPersistCancelFeedback: Bool {
        !isDemoMode || persistsCancelFeedbackInDemo
    }

    private var isRenewalFlow: Bool {
        onboardingCoordinator?.startingStep == .commitTrial
    }

    private var availablePlans: [SubscriptionPlanOption] {
        if let coordinator = onboardingCoordinator {
            return coordinator.availablePlanOptions
        }
        return shouldUseDemoPlans ? Self.demoPlanOptions : offeringViewModel.planOptions
    }

    private var displayedPlans: [SubscriptionPlanOption] {
        let fallbackPlans = Self.paywallPlans(
            from: availablePlans,
            preferMonthlyFirst: shouldPreferLowFrictionPlanDefault
        )

        if usesHardPaywallValueLayout {
            let hardPaywallPlans = Self.hardPaywallPlans(from: availablePlans)
            return hardPaywallPlans
        }

        return fallbackPlans
    }

    private var hardPaywallDirectPlansAvailable: Bool {
        !Self.hardPaywallPlans(from: availablePlans).isEmpty
    }

    private var selectedPlan: SubscriptionPlanOption? {
        if let coordinator = onboardingCoordinator {
            if let current = coordinator.selectedPlan,
               displayedPlans.contains(where: { $0.id == current.id }) {
                return current
            }
            if usesHardPaywallValueLayout {
                return preferredDefaultVisiblePlan
            }
            return preferredDefaultVisiblePlan ?? coordinator.selectedPlan
        }

        if let id = standaloneSelectedPlanID,
           let match = displayedPlans.first(where: { $0.id == id }) {
            return match
        }
        return preferredDefaultVisiblePlan
    }

    private var shouldPreferLowFrictionPlanDefault: Bool {
        paywallDefaultPlanSelection.prefersMonthlyFirst
    }

    private var preferredDefaultVisiblePlan: SubscriptionPlanOption? {
        if shouldPreferLowFrictionPlanDefault,
           let monthly = displayedPlans.first(where: { $0.periodKind == .month }) {
            return monthly
        }
        return displayedPlans.first
    }

    private var paywallDefaultReason: String {
        if preferredDefaultVisiblePlan?.periodKind == .month ||
            preferredDefaultVisiblePlan?.periodKind == .year {
            return paywallDefaultPlanSelection.defaultReason
        }
        return "first_available_plan"
    }

    private var usesTrialConfidenceLayout: Bool {
        paywallLayoutVariant == .trialConfidence
    }

    private var usesTrialPrepCompactLayout: Bool {
        paywallLayoutVariant == .trialPrepCompact && !hasExistingSubscriptionAccess
    }

    private var usesHardPaywallValueLayout: Bool {
        paywallLayoutVariant == .hardPaywallValue && !hasExistingSubscriptionAccess
    }

    private var isCompactPaywallIntroStep: Bool {
        usesTrialPrepCompactLayout && compactPaywallStep != .plans
    }

    private var paywallFunnelMetadata: [String: Any] {
        var metadata = onboardingCoordinator?.paywallFunnelAnalyticsMetadata ?? [:]
        metadata["paywall_variant"] = paywallDefaultPlanSelection.analyticsVariantName
        metadata["paywall_ab_parameter"] = MacraPaywallExperimentService.defaultPlanParameterKey
        metadata["macra_paywall_default_plan"] = paywallDefaultPlanSelection.rawValue
        metadata["paywall_default_selection"] = paywallDefaultPlanSelection.rawValue
        metadata["paywall_default_reason"] = paywallDefaultReason
        metadata["paywall_layout_variant"] = paywallLayoutVariant.analyticsVariantName
        metadata["paywall_layout_ab_parameter"] = MacraPaywallExperimentService.layoutVariantParameterKey
        metadata["macra_paywall_layout_variant"] = paywallLayoutVariant.rawValue
        metadata["paywall_layout_selection"] = paywallLayoutVariant.rawValue
        metadata["experiment_id"] = paywallExperimentAssignment.experimentId
        metadata["experiment_variant_id"] = paywallExperimentAssignment.variantId
        metadata["experiment_variant_name"] = paywallExperimentAssignment.variantName
        metadata["experiment_assignment_source"] = paywallExperimentAssignment.assignmentSource
        metadata["onboarding_experience_variant"] = paywallExperimentAssignment.onboardingVariant.rawValue
        metadata["paywall_default_plan_id"] = preferredDefaultVisiblePlan?.id ?? "none"
        metadata["paywall_default_plan_period"] = preferredDefaultVisiblePlan.map { periodAnalyticsName($0.periodKind) } ?? "none"
        metadata["displayed_plan_order"] = displayedPlans.map { periodAnalyticsName($0.periodKind) }.joined(separator: ",")
        metadata["selected_plan_period"] = selectedPlan.map { periodAnalyticsName($0.periodKind) } ?? "none"
        metadata["selected_plan_id"] = selectedPlan?.id ?? "none"
        metadata["has_price_expectation_card"] = !shouldUseWebCheckoutFallback
        metadata["has_trial_confidence_card"] = usesTrialConfidenceLayout && !shouldUseWebCheckoutFallback
        metadata["has_trial_prep_screens"] = usesTrialPrepCompactLayout
        metadata["uses_trial_prep_compact_layout"] = usesTrialPrepCompactLayout
        metadata["uses_hard_paywall_value_layout"] = usesHardPaywallValueLayout
        metadata["hard_paywall_direct_plan_available"] = hardPaywallDirectPlansAvailable
        metadata["compact_paywall_step"] = usesTrialPrepCompactLayout ? compactPaywallStep.rawValue : "none"
        metadata["trial_disclosure_days"] = trialDisclosureDays ?? 0
        metadata["trial_reminder_lead_days"] = trialReminderLeadDaysForScheduling ?? 0
        metadata["trial_reminder_choice"] = trialReminderLeadDaysForScheduling.map { "\($0)_day_before" } ?? "none"
        metadata["uses_web_checkout_fallback"] = shouldUseWebCheckoutFallback
        metadata["available_plan_count_at_paywall"] = availablePlans.count
        metadata["visible_plan_count_at_paywall"] = displayedPlans.count
        metadata["is_renewal_flow"] = isRenewalFlow
        metadata["is_screen_demo"] = isDemoMode
        metadata["screen_demo_persists_cancel_feedback"] = persistsCancelFeedbackInDemo
        if let paywallAppearedAt {
            metadata["paywall_elapsed_seconds"] = Int(Date().timeIntervalSince(paywallAppearedAt))
        }
        return metadata
    }

    private var isPurchasing: Bool {
        (onboardingCoordinator?.isPurchasing ?? isStandalonePurchasing) ||
        isWebCheckoutCompleting ||
        isPreparingWebCheckout ||
        isVerifyingSubscriptionAccess
    }

    private var purchaseError: String? {
        onboardingCoordinator?.purchaseError ?? standalonePurchaseError
    }

    private var isLoadingPackages: Bool {
        offeringViewModel.isLoadingPackages
    }

    private var packageLoadError: String? {
        shouldUseDemoPlans ? nil : offeringViewModel.packageLoadError
    }

    private var shouldUseWebCheckoutFallback: Bool {
        !hasExistingSubscriptionAccess &&
        !shouldUseDemoPlans &&
        !isLoadingPackages &&
        displayedPlans.isEmpty
    }

    private var webCheckoutFallbackReason: String {
        if let packageLoadError, !packageLoadError.isEmpty {
            return "plans_load_failed"
        }
        if availablePlans.isEmpty {
            return "plans_unavailable"
        }
        return "no_supported_plans"
    }

    private var primaryCTAAnalyticsDecision: String {
        if isPurchasing {
            return "purchase_already_processing"
        }
        if hasExistingSubscriptionAccess {
            return "existing_access_continue"
        }
        if isCompactPaywallIntroStep {
            return "compact_paywall_step_continue"
        }
        if shouldUseWebCheckoutFallback {
            return "web_checkout_fallback"
        }
        if isLoadingPackages {
            return "plans_loading"
        }
        if selectedPlan == nil {
            return "no_plan_selected"
        }
        return "native_purchase"
    }

    private var paywallAnalyticsSource: String {
        if let onboardingCoordinator {
            return onboardingCoordinator.paywallAnalyticsSource
        }
        return "standalone_paywall"
    }

    private var hasExistingSubscriptionAccess: Bool {
        if let existingSubscriptionAccessOverride {
            return existingSubscriptionAccessOverride
        }

        if let onboardingCoordinator {
            return onboardingCoordinator.hasExistingSubscriptionAccess
        }

        return PurchaseService.sharedInstance.isSubscribed ||
        UserService.sharedInstance.user?.subscriptionType.grantsMacraAccess == true ||
        UserService.sharedInstance.isBetaUser
    }

    private var selectedTrialDays: Int? {
        guard let trialDays = selectedPlan?.trialDays, trialDays > 0 else { return nil }
        return trialDays
    }

    private var trialDisclosureDays: Int? {
        trialDisclosureDays(for: selectedPlan)
    }

    private func trialDisclosureDays(for plan: SubscriptionPlanOption?) -> Int? {
        guard let plan else {
            return usesTrialPrepCompactLayout ? 3 : nil
        }
        guard plan.periodKind == .year else { return nil }
        if let trialDays = plan.trialDays, trialDays > 0 {
            return trialDays
        }
        guard usesTrialPrepCompactLayout else { return nil }
        return 3
    }

    private var trialReminderLeadDaysForScheduling: Int? {
        guard let trialDays = trialDisclosureDays, trialDays > 1 else { return nil }
        return min(selectedTrialReminderLeadDays, trialDays - 1)
    }

    var body: some View {
        ZStack {
            MacraChromaticBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if usesTrialPrepCompactLayout {
                    compactPaywallFlowBody
                } else if usesHardPaywallValueLayout {
                    hardPaywallValueBody
                } else {
                    standardPaywallBody
                }

                bottomCTASection
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await refreshPaywallExperimentSelection()
            await loadPlansAndTrackPaywallView()
        }
        .onAppear {
            if paywallAppearedAt == nil {
                paywallAppearedAt = Date()
            }
            if let coordinator = onboardingCoordinator {
                if !coordinator.isDemoMode {
                    coordinator.loadPlanMacros()
                }
                coordinator.ensureOfferingsLoaded()
            }
            ensureVisiblePlanSelected()
            if presentsCancelFeedbackOnAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    presentCancelFeedbackDialog(trigger: "screen_demo")
                }
            }
        }
        .onChange(of: availablePlans.map(\.id).joined(separator: ",")) { _ in
            ensureVisiblePlanSelected()
            guard shouldTrackPaywallAnalytics else { return }
            trackPaywallViewedIfReady()
            trackWebCheckoutFallbackPresentedIfReady()
        }
        .onChange(of: shouldUseWebCheckoutFallback) { _ in
            trackWebCheckoutFallbackPresentedIfReady()
        }
        .onChange(of: packageLoadError ?? "") { _ in
            trackWebCheckoutFallbackPresentedIfReady()
        }
        .onChange(of: existingSubscriptionAccessOverride) { _ in
            Task { await loadPlansAndTrackPaywallView() }
        }
        .onChange(of: onboardingCoordinator?.purchaseCancellationFeedbackRequestID) { requestID in
            guard requestID != nil else { return }
            presentCancelFeedbackDialogAfterPurchaseCancel(trigger: "storekit_cancelled")
        }
        .sheet(item: $webCheckoutSheet) { sheet in
            SafariCheckoutView(url: sheet.url)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "What stopped you from starting today?",
            isPresented: $showCancelFeedbackDialog,
            titleVisibility: .visible
        ) {
            ForEach(PaywallCancelFeedbackReason.allCases) { reason in
                Button(reason.title) {
                    submitCancelFeedback(reason)
                }
            }

            Button("Not now", role: .cancel) {
                dismissCancelFeedback(reason: "not_now")
            }
        } message: {
            Text("One tap helps us understand what held you back.")
        }
        .onReceive(NotificationCenter.default.publisher(for: MacraDeepLinkService.subscriptionReturnNotification)) { notification in
            handleSubscriptionReturn(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macraPaywallPurchaseCancelled)) { notification in
            guard let coordinator = onboardingCoordinator,
                  let notificationCoordinator = notification.object as? MacraOnboardingCoordinator,
                  notificationCoordinator === coordinator else { return }
            if let purchaseLogID = notification.userInfo?["purchaseLogID"] as? String,
               !purchaseLogID.isEmpty {
                activePurchaseLogID = purchaseLogID
            }
            presentCancelFeedbackDialogAfterPurchaseCancel(trigger: "storekit_cancelled")
        }
        .overlay {
            ZStack {
                if showCancelFeedbackDialog {
                    Color.black.opacity(0.48)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if showSubscriptionSuccess {
                    subscriptionSuccessOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if showAppleConfirmationBridge {
                    Color.black.opacity(0.64)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    appleConfirmationBridgeOverlay
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showSubscriptionSuccess)
        .animation(.easeInOut(duration: 0.18), value: showAppleConfirmationBridge)
        .animation(.easeInOut(duration: 0.18), value: showCancelFeedbackDialog)
        .animation(.easeInOut(duration: 0.2), value: compactPaywallStep)
    }

    private var standardPaywallBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                heroSection

                revealOrPersonalizedSection

                if !hasExistingSubscriptionAccess {
                    firstWeekValueCard
                }

                if hasExistingSubscriptionAccess {
                    existingAccessCard
                } else {
                    outcomeProofCard

                    foodFreedomCard

                    eatingOutCard

                    noraDecisionCard

                    socialLearningCard

                    unlockHighlightsCard

                    if !shouldUseWebCheckoutFallback {
                        if usesTrialConfidenceLayout {
                            trialConfidenceCard
                        } else {
                            purchaseExpectationCard
                        }
                    }

                    if !shouldUseWebCheckoutFallback {
                        tierPickerSection
                    }

                    if !shouldUseWebCheckoutFallback {
                        priceDisclosureCard
                    }
                }

                purchaseErrorText
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
    }

    private var hardPaywallValueBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                hardPaywallPlanFirstHeader

                hardPaywallTopPlanCard

                hardPaywallDeliveredValueCard

                if shouldUseWebCheckoutFallback {
                    compactWebCheckoutFallbackCard
                } else {
                    hardPaywallPriceCommitmentCard
                    priceDisclosureCard
                }

                outcomeProofCard

                noraDecisionCard

                firstWeekValueCard

                unlockHighlightsCard

                purchaseErrorText
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private var compactPaywallFlowBody: some View {
        switch compactPaywallStep {
        case .trialWorks:
            compactTrialWorksScreen
        case .firstSevenDays:
            compactFirstSevenDaysScreen
        case .trialReminder:
            compactTrialReminderScreen
        case .plans:
            compactPlanSelectionScreen
        }
    }

    @ViewBuilder
    private var purchaseErrorText: some View {
        if let purchaseError, !purchaseError.isEmpty {
            Text(purchaseError)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "FF8A80"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        if let coordinator = onboardingCoordinator {
            PaywallTopBar(
                canGoBack: coordinator.canGoBack || (usesTrialPrepCompactLayout && compactPaywallStep.previous != nil),
                onBack: handlePaywallBackPressed
            )
        } else if onDismiss != nil {
            PaywallTopBar(
                canGoBack: false,
                onBack: {},
                onClose: handlePaywallClosePressed
            )
        } else {
            Color.clear.frame(height: 8)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headerEyebrow)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(.primaryGreen)

            Text(headerTitle)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(headerSubtitle)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var showsPersonalizedPlan: Bool {
        guard !isRenewalFlow else { return false }
        return onboardingCoordinator?.planMacros != nil
    }

    private var headerEyebrow: String {
        if hasExistingSubscriptionAccess { return "MACRA ACCESS ACTIVE" }
        if isRenewalFlow { return "SUBSCRIPTION REQUIRED" }
        if usesHardPaywallValueLayout { return "MACRA PLAN READY" }
        return "MACRA PLUS"
    }

    private var headerTitle: String {
        if hasExistingSubscriptionAccess { return "Your Macra plan is ready." }
        if isRenewalFlow { return "Unlock your Macra Plan" }
        if usesHardPaywallValueLayout { return "Unlock your plan and start using it today." }
        return "Build the body you want without giving up the food you love."
    }

    private var headerSubtitle: String {
        if hasExistingSubscriptionAccess {
            return "Your subscription already unlocks Macra. Continue when you're ready to start using this plan."
        }
        if usesHardPaywallValueLayout {
            return "Your targets are built. Subscribe to unlock the scanner, Nora, meal decisions, and the plan Macra made for your goal."
        }
        return "Macra turns your calories, meals out, labels, and Nora's AI insights into a plan you can actually live with."
    }

    // MARK: - Personalized plan (when available) + Reveal teaser (always)

    @ViewBuilder
    private var revealOrPersonalizedSection: some View {
        if showsPersonalizedPlan, let macros = onboardingCoordinator?.planMacros {
            planSummaryCard(macros: macros)
                .onAppear {
                    trackPaywallValuePreviewViewedIfNeeded(previewType: "personalized_plan")
                }
        }
        if !hasExistingSubscriptionAccess {
            PayWallRevealMoment()
                .onAppear {
                    trackPaywallValuePreviewViewedIfNeeded(previewType: showsPersonalizedPlan ? "photo_scan_after_personalized_plan" : "photo_scan_teaser")
                }
        }
    }

    @ViewBuilder
    private func planSummaryCard(macros: MacroRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR PLAN")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.3)
                .foregroundColor(Color.primaryGreen)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(macros.calories)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("kcal daily")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack(spacing: 8) {
                planSummaryChip(label: "P", value: "\(macros.protein)g", color: Color.primaryBlue)
                planSummaryChip(label: "C", value: "\(macros.carbs)g", color: Color.primaryGreen)
                planSummaryChip(label: "F", value: "\(macros.fat)g", color: Color(hex: "FFB454"))
            }

            if let plan = onboardingCoordinator?.suggestedMealPlan, !plan.meals.isEmpty {
                Divider().background(Color.white.opacity(0.08))
                HStack(spacing: 10) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.primaryGreen)
                    Text("\(plan.meals.count) meals planned")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                }
            }

            if let struggle = onboardingCoordinator?.answers.biggestStruggle {
                Divider().background(Color.white.opacity(0.08))
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.primaryGreen)
                        .padding(.top, 2)
                    Text(struggle.paywallProofLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.primaryGreen.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primaryGreen.opacity(0.25), lineWidth: 1)
        )
    }

    private func planSummaryChip(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.1)))
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Hard paywall plan-first page

    private var hardPaywallPlanFirstHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR MACRA PLAN")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(.primaryGreen)

            Text("Your plan is ready.")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(hardPaywallPlanLeadCopy)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hardPaywallPlanLeadCopy: String {
        if let plan = selectedPlan {
            return "You have targets, macros, and meal ideas waiting. Macra Monthly is \(plan.priceLabel) \(renewalCadenceText(for: plan)) and gives you the scanner, Nora, labels, and meal planning to use them today."
        }

        return "You have targets, macros, and meal ideas waiting. Macra Monthly gives you the scanner, Nora, labels, and meal planning to use them today."
    }

    @ViewBuilder
    private var hardPaywallTopPlanCard: some View {
        if shouldUseWebCheckoutFallback {
            EmptyView()
        } else if isLoadingPackages && displayedPlans.isEmpty {
            planStatusCard(message: "Loading the monthly plan...")
        } else if displayedPlans.isEmpty {
            planStatusCard(message: packageLoadError ?? "No monthly plan is available right now.")
        } else if let plan = selectedPlan {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Macra Monthly")
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("Use your plan today")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.62))
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(plan.perPeriodDisplay)
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.78)
                            .lineLimit(1)
                        Text("Apple confirms first")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.primaryGreen)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 10) {
                    hardPaywallPlanDetailRow(
                        icon: "checkmark.seal.fill",
                        title: "Ready for you",
                        value: "Your targets, scanner, meal plan, Nora, labels, and Fit With Pulse"
                    )
                    hardPaywallPlanDetailRow(
                        icon: "creditcard.fill",
                        title: "Monthly price",
                        value: "\(plan.priceLabel) \(renewalCadenceText(for: plan))"
                    )
                    hardPaywallPlanDetailRow(
                        icon: "apple.logo",
                        title: "Apple confirmation",
                        value: "Review the price before you approve"
                    )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.primaryGreen.opacity(0.07)))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primaryGreen.opacity(0.55), lineWidth: 2)
            )
            .onAppear {
                trackPricingDisclosureViewedIfNeeded()
            }
        }
    }

    private func hardPaywallPlanDetailRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color.primaryGreen)
                .frame(width: 26, height: 26)
                .background(Color.primaryGreen.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.58))
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hardPaywallDeliveredValueCard: some View {
        conversionCard(
            eyebrow: "READY TO USE",
            title: hardPaywallDeliveredValueTitle,
            body: hardPaywallDeliveredValueBody,
            accent: Color.primaryGreen
        ) {
            if let macros = onboardingCoordinator?.planMacros {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        planSummaryChip(label: "KCAL", value: "\(macros.calories)", color: Color.primaryGreen)
                        planSummaryChip(label: "P", value: "\(macros.protein)g", color: Color.primaryBlue)
                    }
                    HStack(spacing: 8) {
                        planSummaryChip(label: "C", value: "\(macros.carbs)g", color: Color(hex: "FFB454"))
                        planSummaryChip(label: "F", value: "\(macros.fat)g", color: Color.secondaryPink)
                    }
                }
            }

            if let plan = onboardingCoordinator?.suggestedMealPlan, !plan.meals.isEmpty {
                unlockHighlightRow(
                    icon: "fork.knife",
                    title: "\(plan.meals.count) meals ready to start",
                    body: "Open the plan and pick a first meal that fits your numbers.",
                    accent: Color.primaryBlue
                )
            }

            if let struggle = onboardingCoordinator?.answers.biggestStruggle {
                unlockHighlightRow(
                    icon: "sparkles",
                    title: struggle.paywallProofTitle,
                    body: struggle.paywallProofLine,
                    accent: Color.secondaryPink
                )
            }
        }
        .onAppear {
            trackPaywallValuePreviewViewedIfNeeded(previewType: "hard_paywall_delivered_value")
        }
    }

    private var hardPaywallDeliveredValueTitle: String {
        if onboardingCoordinator?.planMacros != nil {
            return "Your targets and meals are already waiting."
        }
        return "Your first plan is already waiting."
    }

    private var hardPaywallDeliveredValueBody: String {
        if let macros = onboardingCoordinator?.planMacros {
            return "Start with \(macros.calories) calories plus protein, carbs, and fat targets. Then use Macra to scan meals, adjust choices, and ask Nora what fits."
        }
        return "Start with the goal and food direction you chose. Then use Macra to scan meals, adjust choices, and ask Nora what fits."
    }

    // MARK: - Compact trial prep variant

    private var compactTrialWorksScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                compactTrialHeroHeader

                compactTrialTimelineCard

                compactCallout(
                    icon: "iphone",
                    title: "Apple shows the details first",
                    body: "The confirmation sheet shows the selected plan and renewal price before you approve.",
                    accent: Color.primaryGreen
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .onAppear {
            trackTrialConfidenceViewedIfNeeded()
            trackPricingDisclosureViewedIfNeeded()
        }
    }

    private var compactFirstSevenDaysScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                compactStepPill("Step 2 of 4")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your first 7 days with Macra")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("The goal is not perfect tracking. It is knowing the next best food decision.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    compactFirstWeekRow(
                        day: "Day 1",
                        title: "Scan one real meal",
                        body: "Get calories, protein, carbs, and fat without guessing.",
                        accent: Color.primaryGreen
                    )
                    compactFirstWeekRow(
                        day: "Days 2-3",
                        title: "Learn what fits",
                        body: "See which meals support your target and which need a swap.",
                        accent: Color.primaryBlue
                    )
                    compactFirstWeekRow(
                        day: "Days 4-7",
                        title: "Use Nora before decisions",
                        body: "Ask what to order, how to balance dinner, or how to handle cravings.",
                        accent: Color.secondaryPink
                    )
                }

                compactCallout(
                    icon: "sparkles",
                    title: "Keep the plan practical",
                    body: "Macra is built for real meals, restaurants, labels, and days that do not go perfectly.",
                    accent: Color(hex: "FFB454")
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .onAppear {
            trackPaywallValuePreviewViewedIfNeeded(previewType: "first_seven_days_prep")
        }
    }

    private var compactTrialReminderScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                compactStepPill("Step 3 of 4")

                VStack(spacing: 18) {
                    TalkingNoraOrb(size: 86)

                    VStack(spacing: 8) {
                        Text("When should we remind you that your trial ends?")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Pick the nudge that gives you enough time to decide before the yearly plan starts.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                VStack(spacing: 10) {
                    compactTrialReminderOption(
                        leadDays: 2,
                        title: "2 days before",
                        subtitle: "More time to decide before the trial turns into your yearly plan."
                    )

                    compactTrialReminderOption(
                        leadDays: 1,
                        title: "1 day before",
                        subtitle: "A final check-in the day before renewal."
                    )
                }

                compactCallout(
                    icon: "bell.badge.fill",
                    title: "Easy to cancel",
                    body: "The reminder points you back to Apple Subscriptions before the plan renews.",
                    accent: Color.primaryBlue
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .onAppear {
            trackPaywallValuePreviewViewedIfNeeded(previewType: "trial_reminder_choice")
        }
    }

    private var compactPlanSelectionSubtitle: String {
        if trialDisclosureDays != nil {
            return "Start free today. Keep scanning meals, asking Nora, and using your targets after onboarding."
        }
        if selectedPlan?.periodKind == .month {
            return "Monthly starts when you confirm with Apple. Choose annual if you want the 3-day trial."
        }
        return "Choose the plan that fits how you want to use Macra after onboarding."
    }

    private var compactPriceDisclosureTitle: String {
        if trialDisclosureDays != nil {
            return "No payment today."
        }
        if selectedPlan?.periodKind == .month {
            return "Monthly starts after Apple confirmation."
        }
        return "Apple confirms the selected plan before it starts."
    }

    private var compactPlanSelectionScreen: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                compactStepPill("Step 4 of 4")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose your Macra plan.")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(compactPlanSelectionSubtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if shouldUseWebCheckoutFallback {
                    compactWebCheckoutFallbackCard
                } else {
                    tierPickerSection
                    compactPriceDisclosureCard
                }

                compactIncludedSummaryCard

                purchaseErrorText
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 26)
        }
        .onAppear {
            trackPricingDisclosureViewedIfNeeded()
        }
    }

    private func compactStepPill(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundColor(Color.primaryGreen)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primaryGreen.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.primaryGreen.opacity(0.28), lineWidth: 1))
    }

    private var compactTrialHeroHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            compactStepPill("Step 1 of 4")

            VStack(spacing: 14) {
                TalkingNoraOrb(size: 84)
                    .padding(.top, 2)

                VStack(spacing: 8) {
                    Text(trialDisclosureDays == nil ? "How your plan starts" : "How your free trial works")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(trialConfidenceIntro)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if let selectedPlan {
                        compactTrialChip(
                            label: compactTrialPlanChipLabel(for: selectedPlan),
                            value: selectedPlan.priceLabel,
                            accent: Color.primaryGreen
                        )
                    } else if let trialDays = trialDisclosureDays {
                        compactTrialChip(
                            label: "Trial",
                            value: "\(trialLengthText(for: trialDays)) free",
                            accent: Color(hex: "8DB7FF")
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primaryGreen.opacity(0.16),
                                Color.white.opacity(0.055),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.primaryGreen.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private func compactTrialChip(label: String, value: String, accent: Color) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 92)
        .background(Capsule().fill(Color.black.opacity(0.24)))
        .overlay(Capsule().strokeBorder(accent.opacity(0.22), lineWidth: 1))
    }

    private func compactTrialPlanChipLabel(for plan: SubscriptionPlanOption) -> String {
        let cadence: String
        switch plan.periodKind {
        case .year:
            cadence = "Yearly"
        case .month:
            cadence = "Monthly"
        case .week:
            cadence = "Weekly"
        case .day:
            cadence = "Daily"
        case .unknown:
            cadence = "Plan"
        }

        if let trialDays = trialDisclosureDays {
            return "\(cadence) after \(trialLengthAdjectiveText(for: trialDays)) trial"
        }
        return cadence
    }

    private func compactTrialReminderOption(
        leadDays: Int,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = selectedTrialReminderLeadDays == leadDays

        return Button {
            selectedTrialReminderLeadDays = leadDays
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? Color.primaryGreen : Color.white.opacity(0.35))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.primaryGreen.opacity(0.7) : Color.white.opacity(0.09),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var compactTrialTimelineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(trialDisclosureDays == nil ? "Plan timeline" : "Trial timeline")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                if let trialDays = trialDisclosureDays {
                    Text("\(trialLengthText(for: trialDays))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.primaryGreen))
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                trialConfidenceTimelineRow(
                    icon: "checkmark",
                    title: trialConfidenceTodayTitle,
                    body: trialConfidenceTodayLine,
                    accent: Color.primaryGreen,
                    showsConnector: true
                )

                trialConfidenceTimelineRow(
                    icon: "bell.fill",
                    title: "Before renewal",
                    body: "Cancel anytime in Apple Subscriptions if Macra is not the right fit.",
                    accent: Color.primaryBlue,
                    showsConnector: true
                )

                trialConfidenceTimelineRow(
                    icon: "crown.fill",
                    title: trialDisclosureDays.map { "After \(trialLengthText(for: $0))" } ?? "When confirmed",
                    body: trialConfidenceRenewalLine,
                    accent: Color(hex: "FFB454"),
                    showsConnector: false
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primaryGreen.opacity(0.22), lineWidth: 1)
        )
    }

    private func compactFirstWeekRow(day: String, title: String, body: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(day)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .frame(width: 74, alignment: .center)
                .padding(.vertical, 8)
                .background(Capsule().fill(accent))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func compactCallout(icon: String, title: String, body: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 30, height: 30)
                .background(accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.26)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var compactPriceDisclosureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(compactPriceDisclosureTitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(priceDisclosureText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(Color.primaryGreen.opacity(0.18), lineWidth: 1)
        )
    }

    private var compactWebCheckoutFallbackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Secure web checkout")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Plans are not loading through Apple right now, so this button opens Stripe and applies access to this Macra account.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.primaryGreen.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primaryGreen.opacity(0.22), lineWidth: 1)
        )
    }

    private var compactIncludedSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("INCLUDED")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.3)
                .foregroundColor(Color.primaryGreen)

            compactFeatureRow(
                icon: "camera.viewfinder",
                title: "Scan meals",
                body: "Photo and label scans turn food into macro estimates.",
                accent: Color.primaryGreen
            )
            compactFeatureRow(
                icon: "list.bullet.rectangle",
                title: "Menu choices",
                body: "Ask Nora what fits before ordering.",
                accent: Color.primaryBlue
            )
            compactFeatureRow(
                icon: "person.2.fill",
                title: "Eat with friends",
                body: "Share meals and learn from real days.",
                accent: Color.secondaryPink
            )
            compactFeatureRow(
                icon: "dumbbell",
                title: "Fit With Pulse",
                body: "Workouts and clubs are included.",
                accent: Color(hex: "FFB454")
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func compactFeatureRow(icon: String, title: String, body: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Conversion proof

    private var hardPaywallValueAnchorCard: some View {
        conversionCard(
            eyebrow: "UNLOCK THE SYSTEM",
            title: hardPaywallAnchorTitle,
            body: hardPaywallAnchorBody,
            accent: Color.primaryGreen
        ) {
            unlockHighlightRow(
                icon: "target",
                title: "Targets are already built",
                body: "Your calories, protein, carbs, and fat become the lane for every meal decision.",
                accent: Color.primaryGreen
            )
            unlockHighlightRow(
                icon: "camera.viewfinder",
                title: "Scan food into the plan",
                body: "Use photos and labels to turn real meals into clear numbers.",
                accent: Color.primaryBlue
            )
            unlockHighlightRow(
                icon: "sparkles",
                title: "Nora guides the next choice",
                body: "Ask what fits before ordering, snacking, or adjusting dinner.",
                accent: Color.secondaryPink
            )
        }
        .onAppear {
            trackPaywallValuePreviewViewedIfNeeded(previewType: "hard_paywall_value_anchor")
        }
    }

    private var hardPaywallAnchorTitle: String {
        if let struggle = onboardingCoordinator?.answers.biggestStruggle {
            return "\(struggle.coachingFocusTitle). Unlock the plan now."
        }
        return "Your plan is ready. Unlock it now."
    }

    private var hardPaywallAnchorBody: String {
        if let macros = onboardingCoordinator?.planMacros {
            return "Start with \(macros.calories) calories plus protein, carbs, and fat targets. Use scans, labels, and Nora to make those numbers work with real meals."
        }
        return "Use scans, labels, Nora, meal planning, and Fit With Pulse with the plan you just built."
    }

    private var firstWeekValueCard: some View {
        conversionCard(
            eyebrow: "YOUR FIRST 7 DAYS",
            title: firstWeekValueTitle,
            body: firstWeekValueBody,
            accent: Color.primaryGreen
        ) {
            unlockHighlightRow(
                icon: "calendar",
                title: "Start with today's target",
                body: "Your calories and macros are already translated into a daily lane.",
                accent: Color.primaryGreen
            )
            unlockHighlightRow(
                icon: "camera.viewfinder",
                title: "Scan before you guess",
                body: "Use photo and label scans when a meal is unclear, then let the plan adjust.",
                accent: Color.primaryBlue
            )
            unlockHighlightRow(
                icon: "sparkles",
                title: "Ask Nora for the next move",
                body: "When cravings, restaurants, or portions get messy, Nora gives the next decision.",
                accent: Color.secondaryPink
            )
        }
    }

    private var firstWeekValueTitle: String {
        if let struggle = onboardingCoordinator?.answers.biggestStruggle {
            return "\(struggle.coachingFocusTitle), starting today."
        }
        return "Your plan has a first move, not just a price."
    }

    private var firstWeekValueBody: String {
        if let struggle = onboardingCoordinator?.answers.biggestStruggle {
            return struggle.coachingFocusBody
        }
        return "Macra unlocks the scanner, Nora, targets, meal planning, and the Fit With Pulse workouts that keep the plan usable after onboarding."
    }

    private var outcomeProofCard: some View {
        conversionCard(
            eyebrow: "WHAT YOU GET",
            title: "A plan that turns today's food choices into progress.",
            body: personalizedPlanProofLine,
            accent: Color.primaryGreen
        ) {
            unlockHighlightRow(
                icon: "target",
                title: "Targets made personal",
                body: "Your calorie, protein, carb, and fat targets become the guide for every meal.",
                accent: Color.primaryGreen
            )
            unlockHighlightRow(
                icon: "fork.knife",
                title: "A day you can actually follow",
                body: "Macra keeps the plan practical instead of forcing perfect meal-prep behavior.",
                accent: Color.primaryBlue
            )
        }
    }

    private var foodFreedomCard: some View {
        conversionCard(
            eyebrow: "FOOD FREEDOM",
            title: "Eat like someone with a plan, not someone starting over Monday.",
            body: "Macra is built for people who want a leaner, healthier body and still want sushi, tacos, burgers, bowls, coffee runs, and nights out.",
            accent: Color(hex: "FFB454")
        ) {
            unlockHighlightRow(
                icon: "heart.fill",
                title: "Keep the foods you love",
                body: "Learn what fits, what needs a swap, and what just needs the rest of the day adjusted.",
                accent: Color(hex: "FFB454")
            )
            unlockHighlightRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Recover from messy days",
                body: "Nora can rebalance dinner after a big lunch so one meal does not become a lost day.",
                accent: Color.secondaryPink
            )
        }
    }

    private var eatingOutCard: some View {
        conversionCard(
            eyebrow: "EATING OUT MODE",
            title: "Know what to order before hunger makes the decision.",
            body: "Use Macra for menus, fast food, labels, and meal photos so the next choice is obvious.",
            accent: Color.primaryBlue
        ) {
            unlockHighlightRow(
                icon: "list.bullet.rectangle",
                title: "Menu decisions",
                body: "Ask Nora what fits your targets at the restaurant in front of you.",
                accent: Color.primaryBlue
            )
            unlockHighlightRow(
                icon: "takeoutbag.and.cup.and.straw",
                title: "Fast-food recommendations",
                body: "Get high-protein picks, swaps, and portions without guessing in the line.",
                accent: Color(hex: "FFB454")
            )
            unlockHighlightRow(
                icon: "qrcode.viewfinder",
                title: "Label reality checks",
                body: "Scan packaged foods and supplements before they become part of your day.",
                accent: Color.primaryGreen
            )
        }
    }

    private var noraDecisionCard: some View {
        conversionCard(
            eyebrow: "NORA COACHING",
            title: "Turn \"what should I eat?\" into the next clear move.",
            body: "Nora uses your targets, logs, and context to coach the exact decision in front of you.",
            accent: Color.secondaryPink
        ) {
            unlockHighlightRow(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Can I fit pizza tonight?",
                body: "Get the portion, sides, and day adjustment that keep the plan alive.",
                accent: Color.secondaryPink
            )
            unlockHighlightRow(
                icon: "sparkles",
                title: "What should I order?",
                body: "Turn cravings, menus, and macro gaps into a realistic recommendation.",
                accent: Color.primaryGreen
            )
        }
    }

    private var socialLearningCard: some View {
        conversionCard(
            eyebrow: "SOCIAL LEARNING",
            title: "Learn how other people structure eating habits.",
            body: "Buddies lets you share food habits with friends, compare meal structure, and learn from days that look like the body and lifestyle you want.",
            accent: Color.primaryGreen
        ) {
            unlockHighlightRow(
                icon: "person.2.fill",
                title: "Share eating habits",
                body: "Invite friends to see your daily meals and swap accountability when you want it.",
                accent: Color.primaryGreen
            )
            unlockHighlightRow(
                icon: "chart.bar.xaxis",
                title: "Copy better patterns",
                body: "Study how high-protein days, meals out, and snacks are structured in real life.",
                accent: Color.primaryBlue
            )
        }
    }

    private var personalizedPlanProofLine: String {
        if let macros = onboardingCoordinator?.planMacros {
            return "You are unlocking \(macros.calories) calories with \(macros.protein)g protein, \(macros.carbs)g carbs, and \(macros.fat)g fat as your daily operating system."
        }

        return "You are not buying generic advice. You are unlocking the system that turns your goals, meals, and cravings into daily decisions."
    }

    private func conversionCard<Content: View>(
        eyebrow: String,
        title: String,
        body: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.3)
                .foregroundColor(accent)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(body)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(accent.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(accent.opacity(0.16), lineWidth: 1)
        )
    }

    // MARK: - What unlocks

    private var unlockHighlightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EVERYTHING INCLUDED")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.3)
                .foregroundColor(Color.primaryGreen)

            unlockHighlightRow(
                icon: "camera.viewfinder",
                title: "Photo macro scan",
                body: "Scan meals and get calorie and macro estimates in seconds."
            )
            unlockHighlightRow(
                icon: "qrcode.viewfinder",
                title: "Label scanner",
                body: "Understand products, ingredients, and tradeoffs before they land in your cart."
            )
            unlockHighlightRow(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Nora AI insights",
                body: "Get day-specific coaching from your targets, logs, cravings, and schedule."
            )
            unlockHighlightRow(
                icon: "person.2.fill",
                title: "Buddies and share cards",
                body: "Share meals, learn from friends, and make your progress more visible."
            )
            unlockHighlightRow(
                icon: "dumbbell",
                title: "Fit With Pulse Pro included",
                body: "One subscription also unlocks AI workouts, live challenges, and clubs."
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func unlockHighlightRow(
        icon: String,
        title: String,
        body: String,
        accent: Color = Color.primaryGreen
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var existingAccessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primaryGreen)
                    .frame(width: 30, height: 30)
                    .background(Color.primaryGreen.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription recognized")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("No purchase is needed for this account.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.66))
                }
            }

            Text("Macra is unlocked through your existing subscription. Your plan, meal targets, scanner, and Nora are ready.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.primaryGreen.opacity(0.055)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primaryGreen.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Tier picker

    @ViewBuilder
    private var tierPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOOSE YOUR PLAN")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.3)
                .foregroundColor(Color.primaryGreen)

            if isLoadingPackages && availablePlans.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.primaryGreen)
                    Text("Loading plans...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if displayedPlans.isEmpty {
                planStatusCard(
                    message: packageLoadError ?? "No subscription plans are available right now."
                )
            } else {
                ForEach(Array(displayedPlans.enumerated()), id: \.element.id) { index, plan in
                    TierCard(
                        title: plan.displayTitle,
                        perPeriodPrice: plan.perPeriodDisplay,
                        billingNote: paywallBillingNote(for: plan),
                        badge: tierSavingsBadge(for: plan),
                        emphasized: index == 0,
                        isSelected: selectedPlan?.id == plan.id,
                        onTap: { selectPlan(plan, userInitiated: true) }
                    )
                }
            }
        }
    }

    private func paywallBillingNote(for plan: SubscriptionPlanOption) -> String {
        if usesHardPaywallValueLayout {
            if plan.periodKind == .month {
                return "Billed monthly. Cancel anytime"
            }
            return plan.billingNote
        }

        guard usesTrialPrepCompactLayout else {
            return plan.billingNote
        }
        if let trialDays = trialDisclosureDays(for: plan) {
            return "Includes \(trialLengthAdjectiveText(for: trialDays)) trial. \(plan.billingNote)"
        }
        if plan.periodKind == .month {
            return "No free trial. Billed monthly"
        }
        return plan.billingNote
    }

    private func planStatusCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func tierSavingsBadge(for plan: SubscriptionPlanOption) -> String? {
        guard plan.periodKind == .year,
              let comparisonPlan = availablePlans.first(where: { $0.periodKind == .month }) else { return nil }
        let yearlyPrice = NSDecimalNumber(decimal: plan.price).doubleValue
        let comparisonPrice = NSDecimalNumber(decimal: comparisonPlan.price).doubleValue
        let annualizedComparison = comparisonPrice * 12
        guard annualizedComparison > 0, yearlyPrice < annualizedComparison else { return nil }
        let pct = Int(((annualizedComparison - yearlyPrice) / annualizedComparison * 100).rounded())
        return pct > 0 ? "SAVE \(pct)%" : nil
    }

    private func selectPlan(_ plan: SubscriptionPlanOption, userInitiated: Bool) {
        if let coordinator = onboardingCoordinator {
            coordinator.selectPlan(plan)
        } else {
            standaloneSelectedPlanID = plan.id
        }

        if userInitiated, !isDemoMode {
            MacraAnalyticsService.shared.trackSubscriptionPlanSelected(
                plan: plan,
                source: paywallAnalyticsSource,
                metadata: paywallFunnelMetadata
            )
        }
    }

    private func ensureVisiblePlanSelected() {
        guard let defaultVisiblePlan = preferredDefaultVisiblePlan else { return }

        if let coordinator = onboardingCoordinator {
            if let current = coordinator.selectedPlan,
               displayedPlans.contains(where: { $0.id == current.id }) {
                return
            }
            coordinator.selectPlan(defaultVisiblePlan)
            return
        }

        if let id = standaloneSelectedPlanID,
           displayedPlans.contains(where: { $0.id == id }) {
            return
        }
        standaloneSelectedPlanID = defaultVisiblePlan.id
    }

    // MARK: - Price disclosure

    private var trialConfidenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primaryGreen)
                    .frame(width: 32, height: 32)
                    .background(Color.primaryGreen.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("How your free start works")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(trialConfidenceIntro)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                trialConfidenceTimelineRow(
                    icon: "checkmark",
                    title: trialConfidenceTodayTitle,
                    body: trialConfidenceTodayLine,
                    accent: Color.primaryGreen,
                    showsConnector: true
                )

                trialConfidenceTimelineRow(
                    icon: "bell.fill",
                    title: "Before renewal",
                    body: "Cancel anytime in Apple Subscriptions if Macra is not the right fit.",
                    accent: Color.primaryBlue,
                    showsConnector: true
                )

                trialConfidenceTimelineRow(
                    icon: "crown.fill",
                    title: trialDisclosureDays.map { "After \(trialLengthText(for: $0))" } ?? "When confirmed",
                    body: trialConfidenceRenewalLine,
                    accent: Color(hex: "FFB454"),
                    showsConnector: false
                )
            }
            .padding(.top, 2)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "iphone")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 26, height: 26)
                    .background(Color.primaryGreen)
                    .clipShape(Circle())

                Text("Next, Apple shows the confirmation sheet with the exact plan and trial details before anything starts.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.28)))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.primaryGreen.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primaryGreen.opacity(0.22), lineWidth: 1)
        )
        .onAppear {
            trackTrialConfidenceViewedIfNeeded()
            trackPricingDisclosureViewedIfNeeded()
        }
    }

    private var hardPaywallPriceCommitmentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.primaryGreen)
                    .frame(width: 30, height: 30)
                    .background(Color.primaryGreen.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple confirms before anything starts")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(hardPaywallPriceCommitmentText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isDemoMode && !hardPaywallDirectPlansAvailable {
                Text("Demo note: this preview is using the available StoreKit plans, so Apple may still show an eligible introductory offer.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "FFB454"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "FFB454").opacity(0.08)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(hex: "FFB454").opacity(0.18), lineWidth: 1)
                    )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.primaryGreen.opacity(0.055)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primaryGreen.opacity(0.22), lineWidth: 1)
        )
        .onAppear {
            trackPricingDisclosureViewedIfNeeded()
        }
    }

    private var hardPaywallPriceCommitmentText: String {
        guard let plan = selectedPlan else {
            return "Choose Macra Monthly, then review the price with Apple before anything starts."
        }

        if usesHardPaywallValueLayout {
            return "You will see \(plan.priceLabel) \(renewalCadenceText(for: plan)) on the Apple sheet before you approve."
        }

        if let trialDays = trialDisclosureDays {
            return "Apple will show the \(trialLengthText(for: trialDays)) trial and \(plan.priceLabel) renewal before anything starts."
        }

        return "Apple will show \(plan.priceLabel) \(renewalCadenceText(for: plan)) before the subscription starts."
    }

    private var trialConfidenceIntro: String {
        if let trialDays = trialDisclosureDays {
            return "Start your \(trialLengthText(for: trialDays)) trial with no charge today. The selected plan only renews after the trial unless you cancel."
        }
        return "You can review the exact Apple confirmation sheet before the selected plan starts."
    }

    private var trialConfidenceTodayTitle: String {
        trialDisclosureDays == nil ? "Today" : "Free Today"
    }

    private var trialConfidenceTodayLine: String {
        if trialDisclosureDays != nil {
            return "Unlock scanner, Nora, targets, meal planning, and workouts. No payment today."
        }
        return "Review your Macra plan and confirm only if the selected price feels right."
    }

    private var trialConfidenceRenewalLine: String {
        guard let plan = selectedPlan else {
            return "Renews at the selected plan price unless canceled."
        }
        if trialDisclosureDays != nil {
            return "Renews at \(plan.priceLabel) \(renewalCadenceText(for: plan)) unless canceled."
        }
        return "Starts at \(plan.priceLabel) \(renewalCadenceText(for: plan)) after Apple confirmation."
    }

    private func trialConfidenceTimelineRow(
        icon: String,
        title: String,
        body: String,
        accent: Color,
        showsConnector: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 30, height: 30)
                    .background(accent)
                    .clipShape(Circle())

                if showsConnector {
                    Rectangle()
                        .fill(accent.opacity(0.34))
                        .frame(width: 2, height: 34)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
    }

    private var purchaseExpectationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.primaryGreen)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Before Apple asks")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(purchaseExpectationBody)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 8) {
                purchaseExpectationRow(
                    label: "Trial",
                    value: selectedTrialDays.map { "\(trialLengthText(for: $0)) free" } ?? "Not included"
                )
                purchaseExpectationRow(
                    label: "Renews",
                    value: selectedPlan.map { "\($0.priceLabel) \(renewalCadenceText(for: $0))" } ?? "Plan loading"
                )
                purchaseExpectationRow(
                    label: "Cancel",
                    value: "Anytime in Apple Subscriptions"
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primaryGreen.opacity(0.18), lineWidth: 1)
        )
        .onAppear {
            trackPricingDisclosureViewedIfNeeded()
        }
    }

    private var purchaseExpectationBody: String {
        if let trialDays = selectedTrialDays {
            return "The next screen is Apple's subscription sheet. Your \(trialLengthText(for: trialDays)) trial starts free, then renews at the selected plan price unless you cancel."
        }
        return "The next screen is Apple's subscription sheet. It confirms the selected plan price before your subscription starts."
    }

    private func purchaseExpectationRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.trailing)
        }
    }

    private var priceDisclosureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(priceDisclosureText)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if !usesHardPaywallValueLayout, let trialDays = trialDisclosureDays {
                HStack {
                    Text("Trial")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(trialLengthText(for: trialDays)) free")
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.top, 4)
            }

            if let plan = selectedPlan {
                HStack {
                    Text("Plan")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 12))
                    Spacer()
                    Text(plan.priceLabel)
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var priceDisclosureText: String {
        if shouldUseWebCheckoutFallback {
            return "Web checkout uses Stripe. Your subscription auto-renews until canceled and access is applied to this Macra account."
        }

        if usesHardPaywallValueLayout,
           let plan = selectedPlan {
            return "Macra starts after you approve \(plan.priceLabel) \(renewalCadenceText(for: plan)) with Apple. It renews monthly until canceled in Apple Subscriptions."
        }

        if let trialDays = trialDisclosureDays {
            return "Your \(trialLengthText(for: trialDays)) trial is free. After the trial, your selected plan auto-renews until canceled. Cancel anytime in Settings > [your name] > Subscriptions."
        }

        if usesTrialPrepCompactLayout,
           let plan = selectedPlan,
           plan.periodKind == .month {
            return "Monthly does not include a free trial. It starts at \(plan.priceLabel) monthly after Apple confirmation. Choose annual if you want the 3-day trial."
        }

        return "Auto-renews at the price shown until canceled. Cancel anytime in Settings > [your name] > Subscriptions."
    }

    private func renewalCadenceText(for plan: SubscriptionPlanOption) -> String {
        switch plan.periodKind {
        case .year: return "yearly"
        case .month: return "monthly"
        case .week: return "weekly"
        case .day: return "daily"
        case .unknown: return ""
        }
    }

    // MARK: - Bottom CTA + footer

    private var bottomCTASection: some View {
        VStack(spacing: 14) {
            MacraPrimaryButton(
                title: isPurchasing ? "Processing..." : ctaTitle,
                accent: Color.primaryGreen,
                isLoading: isPurchasing,
                disablesWhileLoading: false,
                action: handlePrimaryButtonPressed
            )

            if let ctaSupportingText {
                Text(ctaSupportingText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if hasExistingSubscriptionAccess {
                HStack(spacing: 16) {
                    Button(action: openPrivacy) {
                        Text("Privacy")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    Button(action: openTerms) {
                        Text("Terms")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            } else {
                HStack(spacing: 16) {
                    Button(action: triggerRestore) {
                        Text("Restore Purchases")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    Button(action: openPrivacy) {
                        Text("Privacy")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                    }

                    Button(action: openTerms) {
                        Text("Terms")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var subscriptionSuccessOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundColor(Color.primaryGreen)

                    Text("Your plan is active")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Start with one meal so Nora can tune the rest of today.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                subscriptionActivationCard

                MacraPrimaryButton(
                    title: "Start with one meal",
                    accent: Color.primaryGreen,
                    isLoading: false,
                    action: finishSubscriptionSuccessFlow
                )
                .padding(.top, 6)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.secondaryCharcoal.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.primaryGreen.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .onAppear {
                trackSubscriptionSuccessActivationViewedIfNeeded()
            }
        }
    }

    private var subscriptionActivationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let macros = onboardingCoordinator?.planMacros {
                HStack(spacing: 10) {
                    activationMetric(label: "Calories", value: "\(macros.calories)", accent: Color.primaryGreen)
                    activationMetric(label: "Protein", value: "\(macros.protein)g", accent: Color.primaryBlue)
                }
            }

            if let meal = onboardingCoordinator?.suggestedMealPlan?.meals.first {
                Divider().background(Color.white.opacity(0.08))
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.primaryGreen)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("First meal to log")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(0.9)
                            .foregroundColor(Color.primaryGreen)
                        Text(meal.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("\(meal.totalCalories) calories planned")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
                    }
                    Spacer(minLength: 0)
                }
            } else {
                activationStepRow(icon: "camera.viewfinder", title: "Log your first meal", body: "Use a photo or quick entry. One real meal gives Nora the signal she needs.")
            }

            activationStepRow(icon: "sparkles", title: "Nora checks the fit", body: "After the first log, Macra compares the meal against your target and next meal.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primaryGreen.opacity(0.18), lineWidth: 1)
        )
    }

    private func activationMetric(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.0)
                .foregroundColor(accent)
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.08)))
    }

    private func activationStepRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.primaryGreen)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primaryGreen.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var appleConfirmationBridgeOverlay: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)

                Text(appleConfirmationBridgeTitle)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(appleConfirmationBridgeBody)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                appleConfirmationRow(label: "Today", value: appleConfirmationTodayText)
                appleConfirmationRow(label: appleConfirmationRenewalLabel, value: appleConfirmationRenewalText)
                appleConfirmationRow(label: "Cancel", value: "Apple Subscriptions")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))

            MacraPrimaryButton(
                title: "Continue to Apple",
                accent: Color.primaryGreen,
                isLoading: false,
                action: continueFromAppleConfirmationBridge
            )

            Button("Not now") {
                dismissAppleConfirmationBridge(reason: "not_now")
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.white.opacity(0.72))
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.secondaryCharcoal.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.primaryGreen.opacity(0.28), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    private var appleConfirmationBridgeBody: String {
        if usesHardPaywallValueLayout {
            return "The Apple sheet shows the selected monthly price and the final approval button before anything starts."
        }
        if let trialDays = trialDisclosureDays {
            return "The Apple sheet shows your \(trialLengthText(for: trialDays)) free trial, the renewal price, and the final approval button before anything starts."
        }
        return "The Apple sheet shows the selected price and the final approval button before anything starts."
    }

    private var appleConfirmationBridgeTitle: String {
        if usesHardPaywallValueLayout || trialDisclosureDays == nil {
            return "Apple confirms your plan next"
        }
        return "Apple confirms the trial next"
    }

    private var appleConfirmationTodayText: String {
        guard trialDisclosureDays == nil else { return "$0" }
        return selectedPlan?.priceLabel ?? "Selected price"
    }

    private var appleConfirmationRenewalText: String {
        guard let plan = selectedPlan else { return "Selected plan" }
        if trialDisclosureDays == nil {
            return "\(plan.priceLabel) \(renewalCadenceText(for: plan))"
        }
        return "\(plan.priceLabel) \(renewalCadenceText(for: plan)) unless canceled"
    }

    private var appleConfirmationRenewalLabel: String {
        trialDisclosureDays == nil ? "Renews" : "After trial"
    }

    private func appleConfirmationRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.58))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    private var ctaTitle: String {
        if hasExistingSubscriptionAccess { return "Continue to Macra" }
        if usesTrialPrepCompactLayout {
            switch compactPaywallStep {
            case .trialWorks: return "Continue"
            case .firstSevenDays: return "Set reminder"
            case .trialReminder: return "See plans"
            case .plans: break
            }
        }
        if shouldUseWebCheckoutFallback { return "Unlock Macra" }
        if isRenewalFlow { return "Unlock Macra Pro" }
        if usesTrialConfidenceLayout, selectedTrialDays != nil { return "Continue for free" }
        if usesTrialPrepCompactLayout, trialDisclosureDays != nil { return "Start my free trial" }
        if usesTrialPrepCompactLayout, selectedPlan?.periodKind == .month { return "Start monthly plan" }
        if usesHardPaywallValueLayout, trialDisclosureDays == nil { return "Unlock Macra today" }
        if usesHardPaywallValueLayout { return "Continue with Apple" }
        if let trialDays = selectedTrialDays { return "Try \(trialLengthText(for: trialDays)) free" }
        if selectedPlan == nil, isLoadingPackages { return "Loading plans..." }
        if selectedPlan == nil { return "Unlock Macra" }
        guard let plan = selectedPlan else { return "Continue" }
        switch plan.periodKind {
        case .year: return "Unlock my yearly plan"
        case .month: return "Unlock my monthly plan"
        default: return "Unlock my plan"
        }
    }

    private var ctaSupportingText: String? {
        if isCompactPaywallIntroStep {
            return nil
        }
        if shouldUseWebCheckoutFallback {
            return "Subscribe securely through Stripe, then return to Macra automatically."
        }
        guard !hasExistingSubscriptionAccess, let plan = selectedPlan else { return nil }
        if usesHardPaywallValueLayout {
            return "Apple asks you to confirm first. Cancel anytime in Apple Subscriptions."
        }
        if let trialDays = trialDisclosureDays {
            if usesTrialConfidenceLayout {
                return "No payment today. After \(trialLengthText(for: trialDays)), renews at \(plan.priceLabel) unless canceled."
            }
            if usesTrialPrepCompactLayout {
                return "No payment today. After \(trialLengthText(for: trialDays)), renews at \(plan.priceLabel) unless canceled."
            }
            return "Free for \(trialLengthText(for: trialDays)), then \(plan.priceLabel). Cancel anytime."
        }
        if usesTrialPrepCompactLayout, plan.periodKind == .month {
            return "Monthly starts after Apple confirmation. Annual includes a 3-day trial."
        }

        return "\(plan.priceLabel). Cancel anytime in Apple Subscriptions."
    }

    private func trialLengthText(for days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    private func trialLengthAdjectiveText(for days: Int) -> String {
        days == 1 ? "1-day" : "\(days)-day"
    }

    // MARK: - Actions

    private func handlePrimaryButtonPressed() {
        trackPaywallPrimaryButtonPressedIfNeeded()

        guard !isPurchasing else {
            trackPaywallCTABlockedIfNeeded(reason: "purchase_already_processing")
            return
        }

        if advanceCompactPaywallIfNeeded() {
            return
        }

        if hasExistingSubscriptionAccess {
            triggerExistingAccessContinue()
        } else if shouldUseWebCheckoutFallback {
            triggerWebCheckoutFallback()
        } else {
            presentAppleConfirmationBridge()
        }
    }

    private func advanceCompactPaywallIfNeeded() -> Bool {
        guard usesTrialPrepCompactLayout,
              let nextStep = compactPaywallStep.next else {
            return false
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            compactPaywallStep = nextStep
        }
        return true
    }

    private func triggerWebCheckoutFallback() {
        trackWebCheckoutFallbackPressedIfNeeded()
        standalonePurchaseError = nil
        onboardingCoordinator?.purchaseError = nil
        isPreparingWebCheckout = true
        activePurchaseLogID = MacraPurchaseLogService.shared.recordAttempt(
            plan: selectedPlan,
            source: paywallAnalyticsSource,
            metadata: purchaseLogMetadata(channel: "web_checkout", extra: [
                "fallback_reason": webCheckoutFallbackReason
            ])
        )

        Task {
            do {
                guard let checkoutURL = try await webCheckoutURLForCurrentUser() else {
                    await failWebCheckoutPreparation(
                        message: "We could not open web checkout because this account is not signed in.",
                        reason: "missing_checkout_url"
                    )
                    return
                }

                await MainActor.run {
                    isPreparingWebCheckout = false
                    if shouldTrackPaywallAnalytics {
                        MacraAnalyticsService.shared.trackSubscriptionWebCheckoutStarted(
                            source: paywallAnalyticsSource,
                            reason: webCheckoutFallbackReason,
                            checkoutURL: checkoutURL,
                            metadata: paywallFunnelMetadata
                        )
                    }
                    webCheckoutSheet = WebCheckoutSheet(url: checkoutURL)
                }
            } catch {
                await failWebCheckoutPreparation(
                    message: "We could not start secure web checkout. Please try again.",
                    reason: "firebase_token_unavailable"
                )
            }
        }
    }

    @MainActor
    private func failWebCheckoutPreparation(message: String, reason: String) {
        isPreparingWebCheckout = false
        standalonePurchaseError = message
        onboardingCoordinator?.purchaseError = message
        MacraPurchaseLogService.shared.markFailed(
            logID: activePurchaseLogID,
            plan: selectedPlan,
            source: paywallAnalyticsSource,
            failureReason: reason,
            metadata: purchaseLogMetadata(channel: "web_checkout", extra: [
                "fallback_reason": webCheckoutFallbackReason
            ])
        )
        activePurchaseLogID = nil
        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackSubscriptionWebCheckoutFailed(
                source: paywallAnalyticsSource,
                reason: reason,
                metadata: paywallFunnelMetadata
            )
        }
    }

    private func webCheckoutURLForCurrentUser() async throws -> URL? {
        guard let firebaseUser = Auth.auth().currentUser else { return nil }
        let appUser = UserService.sharedInstance.user
        let userId = firebaseUser.uid
        guard !userId.isEmpty else { return nil }
        let firebaseIdToken = try await firebaseUser.getIDToken()

        let trimmedBase = ConfigManager.shared
            .getWebsiteBaseURL()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Hit the server redirect directly so web auth UI never paints before Stripe checkout.
        guard var components = URLComponents(string: "\(trimmedBase)/.netlify/functions/create-athlete-checkout-session") else { return nil }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "subscribe"),
            URLQueryItem(name: "plan", value: "yearly"),
            URLQueryItem(name: "priceId", value: Self.webCheckoutAnnualPriceID),
            URLQueryItem(name: "source", value: "macra_ios_paywall"),
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "firebaseIdToken", value: firebaseIdToken),
            URLQueryItem(name: "appReturnUrl", value: "macra://subscription/success"),
            URLQueryItem(name: "appCancelUrl", value: "macra://subscription/cancelled")
        ]

        if let email = appUser?.email ?? firebaseUser.email, !email.isEmpty {
            queryItems.append(URLQueryItem(name: "email", value: email))
        }

        components.queryItems = queryItems
        return components.url
    }

    private func handleSubscriptionReturn(_ notification: Notification) {
        guard let userInfo = notification.userInfo as? [String: String] else { return }
        let status = (userInfo["status"] ?? "unknown").lowercased()
        let sessionId = userInfo["session_id"]
        webCheckoutSheet = nil

        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackSubscriptionWebCheckoutReturned(
                source: paywallAnalyticsSource,
                status: status,
                sessionId: sessionId,
                metadata: paywallFunnelMetadata
            )
        }

        switch status {
        case "success", "succeeded", "verified", "complete", "completed":
            scheduleTrialEndingReminderIfRequested()
            MacraPurchaseLogService.shared.markSuccess(
                logID: activePurchaseLogID,
                plan: selectedPlan,
                source: paywallAnalyticsSource,
                metadata: purchaseLogMetadata(channel: "web_checkout", extra: [
                    "checkout_return_status": status,
                    "checkout_session_id": sessionId ?? "",
                    "fallback_reason": webCheckoutFallbackReason
                ])
            )
            activePurchaseLogID = nil
            if let onboardingCoordinator {
                onboardingCoordinator.completeWebSubscriptionAndContinue()
            } else {
                completeStandaloneWebCheckoutReturn()
            }
        case "cancel", "cancelled", "canceled":
            standalonePurchaseError = nil
            onboardingCoordinator?.purchaseError = nil
            MacraPurchaseLogService.shared.markCanceled(
                logID: activePurchaseLogID,
                plan: selectedPlan,
                source: paywallAnalyticsSource,
                failureReason: "web_checkout_cancelled",
                metadata: purchaseLogMetadata(channel: "web_checkout", extra: [
                    "checkout_return_status": status,
                    "checkout_session_id": sessionId ?? "",
                    "fallback_reason": webCheckoutFallbackReason
                ])
            )
            if shouldTrackPaywallAnalytics {
                MacraAnalyticsService.shared.trackSubscriptionWebCheckoutFailed(
                    source: paywallAnalyticsSource,
                    reason: "web_checkout_cancelled",
                    metadata: paywallFunnelMetadata
                )
            }
            presentCancelFeedbackDialogAfterPurchaseCancel(trigger: "web_checkout_cancelled")
        default:
            let message = "Web checkout did not finish. Please try again."
            standalonePurchaseError = message
            onboardingCoordinator?.purchaseError = message
            MacraPurchaseLogService.shared.markFailed(
                logID: activePurchaseLogID,
                plan: selectedPlan,
                source: paywallAnalyticsSource,
                failureReason: "web_checkout_return_\(status)",
                metadata: purchaseLogMetadata(channel: "web_checkout", extra: [
                    "checkout_return_status": status,
                    "checkout_session_id": sessionId ?? "",
                    "fallback_reason": webCheckoutFallbackReason
                ])
            )
            activePurchaseLogID = nil
            if shouldTrackPaywallAnalytics {
                MacraAnalyticsService.shared.trackSubscriptionWebCheckoutFailed(
                    source: paywallAnalyticsSource,
                    reason: "web_checkout_return_\(status)",
                    metadata: paywallFunnelMetadata
                )
            }
        }
    }

    private func completeStandaloneWebCheckoutReturn() {
        verifyStandaloneSubscriptionAccessAndShowSuccess(plan: selectedPlan, context: "web_checkout_return")
    }

    private func verifyStandaloneSubscriptionAccessAndShowSuccess(plan: SubscriptionPlanOption?, context: String) {
        isVerifyingSubscriptionAccess = true
        isWebCheckoutCompleting = true
        standalonePurchaseError = "Finishing unlock..."

        UserService.sharedInstance.getUser { refreshedUser, userError in
            PurchaseService.sharedInstance.checkSubscriptionStatus(forceRefresh: true) { result in
                DispatchQueue.main.async {
                    isVerifyingSubscriptionAccess = false
                    isWebCheckoutCompleting = false

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
                        standalonePurchaseError = nil
                        if activePurchaseLogID != nil {
                            MacraPurchaseLogService.shared.markSuccess(
                                logID: activePurchaseLogID,
                                plan: plan,
                                source: paywallAnalyticsSource,
                                metadata: purchaseLogMetadata(channel: context)
                            )
                            activePurchaseLogID = nil
                        }
                        if shouldTrackPaywallAnalytics {
                            MacraAnalyticsService.shared.trackSubscriptionAccessVerified(
                                plan: plan,
                                source: paywallAnalyticsSource,
                                context: context,
                                metadata: paywallFunnelMetadata
                            )
                        }
                        showSubscriptionSuccessAndEnterDashboard()
                        return
                    }

                    if let userError {
                        if activePurchaseLogID != nil {
                            MacraPurchaseLogService.shared.markFailed(
                                logID: activePurchaseLogID,
                                plan: plan,
                                source: paywallAnalyticsSource,
                                error: userError,
                                failureReason: "user_refresh_error",
                                metadata: purchaseLogMetadata(channel: context)
                            )
                            activePurchaseLogID = nil
                        }
                        if shouldTrackPaywallAnalytics {
                            MacraAnalyticsService.shared.trackSubscriptionAccessVerificationFailed(
                                plan: plan,
                                source: paywallAnalyticsSource,
                                context: context,
                                reason: "user_refresh_error",
                                error: userError,
                                metadata: paywallFunnelMetadata
                            )
                        }
                        standalonePurchaseError = MacraUserFacingError.purchase(userError)
                        return
                    }

                    switch result {
                    case .success(false):
                        if activePurchaseLogID != nil {
                            MacraPurchaseLogService.shared.markFailed(
                                logID: activePurchaseLogID,
                                plan: plan,
                                source: paywallAnalyticsSource,
                                failureReason: "\(context)_access_not_active",
                                metadata: purchaseLogMetadata(channel: context)
                            )
                            activePurchaseLogID = nil
                        }
                        if shouldTrackPaywallAnalytics {
                            MacraAnalyticsService.shared.trackSubscriptionAccessVerificationFailed(
                                plan: plan,
                                source: paywallAnalyticsSource,
                                context: context,
                                reason: "\(context)_access_not_active",
                                metadata: paywallFunnelMetadata
                            )
                        }
                        standalonePurchaseError = "Your subscription was created, but access is still syncing. Close and reopen Macra or tap Restore Purchases in a moment."
                    case .failure(let error):
                        if activePurchaseLogID != nil {
                            MacraPurchaseLogService.shared.markFailed(
                                logID: activePurchaseLogID,
                                plan: plan,
                                source: paywallAnalyticsSource,
                                error: error,
                                failureReason: "\(context)_verification_error",
                                metadata: purchaseLogMetadata(channel: context)
                            )
                            activePurchaseLogID = nil
                        }
                        if shouldTrackPaywallAnalytics {
                            MacraAnalyticsService.shared.trackSubscriptionAccessVerificationFailed(
                                plan: plan,
                                source: paywallAnalyticsSource,
                                context: context,
                                reason: "\(context)_verification_error",
                                error: error,
                                metadata: paywallFunnelMetadata
                            )
                        }
                        standalonePurchaseError = MacraUserFacingError.purchase(error)
                    case .success(true):
                        break
                    }
                }
            }
        }
    }

    private func triggerPurchase() {
        if let coordinator = onboardingCoordinator {
            coordinator.purchaseAndContinue(paywallMetadata: paywallFunnelMetadata)
            return
        }

        let decision = MacraPurchaseFlowResolver.decision(for: MacraPurchaseFlowInput(
            isPurchasing: isPurchasing,
            isDemoMode: isDemoMode,
            usesLivePurchasesInDemo: usesLivePurchasesInDemo,
            hasExistingSubscriptionAccess: hasExistingSubscriptionAccess,
            isLoadingPackages: isLoadingPackages,
            packageLoadError: packageLoadError,
            selectedPlan: selectedPlan
        ))

        switch decision {
        case .ignoreAlreadyPurchasing:
            trackPaywallCTABlockedIfNeeded(reason: "purchase_already_processing")
        case .continueDemoAccess:
            if let plan = selectedPlan {
                purchaseStandalone(plan)
            } else {
                finishStandalonePaywall()
            }
        case .continueExistingAccess:
            triggerExistingAccessContinue()
        case .blocked(let reason, let message):
            standalonePurchaseError = message
            trackPaywallCTABlockedIfNeeded(reason: reason.rawValue)
        case .purchase(let plan):
            purchaseStandalone(plan)
        }
    }

    private func presentAppleConfirmationBridge() {
        guard selectedPlan != nil else {
            triggerPurchase()
            return
        }

        showAppleConfirmationBridge = true
        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackPaywallPurchaseBridgeViewed(
                source: paywallAnalyticsSource,
                selectedPlan: selectedPlan,
                ctaTitle: ctaTitle,
                metadata: paywallFunnelMetadata
            )
        }
    }

    private func continueFromAppleConfirmationBridge() {
        showAppleConfirmationBridge = false
        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackPaywallPurchaseBridgeContinued(
                source: paywallAnalyticsSource,
                selectedPlan: selectedPlan,
                ctaTitle: "Continue to Apple",
                metadata: paywallFunnelMetadata
            )
        }
        triggerPurchase()
    }

    private func dismissAppleConfirmationBridge(reason: String) {
        showAppleConfirmationBridge = false
        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackPaywallPurchaseBridgeDismissed(
                source: paywallAnalyticsSource,
                selectedPlan: selectedPlan,
                ctaTitle: "Continue to Apple",
                reason: reason,
                metadata: paywallFunnelMetadata
            )
        }
    }

    private func triggerExistingAccessContinue() {
        if let coordinator = onboardingCoordinator {
            coordinator.continueWithExistingSubscriptionAccess()
            return
        }
        finishStandalonePaywall()
    }

    private func purchaseStandalone(_ plan: SubscriptionPlanOption) {
        if shouldUseDemoPlans {
            viewModel.appCoordinator.showToast(viewModel: ToastViewModel(
                message: "Demo purchase tapped: \(plan.displayTitle)",
                backgroundColor: .secondaryCharcoal,
                textColor: .secondaryWhite
            ))
            finishStandalonePaywall()
            return
        }

        isStandalonePurchasing = true
        standalonePurchaseError = nil
        activePurchaseLogID = MacraPurchaseLogService.shared.recordAttempt(
            plan: plan,
            source: paywallAnalyticsSource,
            metadata: purchaseLogMetadata(channel: "storekit")
        )
        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackSubscriptionPurchaseAttempted(
                plan: plan,
                source: paywallAnalyticsSource,
                metadata: paywallFunnelMetadata
            )
        }

        offeringViewModel.purchase(plan) { result in
            isStandalonePurchasing = false
            switch result {
            case .success:
                scheduleTrialEndingReminderIfRequested()
                MacraPurchaseLogService.shared.markSuccess(
                    logID: activePurchaseLogID,
                    plan: plan,
                    source: paywallAnalyticsSource,
                    metadata: purchaseLogMetadata(channel: "storekit")
                )
                activePurchaseLogID = nil
                if shouldTrackPaywallAnalytics {
                    MacraAnalyticsService.shared.trackSubscriptionStart(
                        plan: plan,
                        source: paywallAnalyticsSource,
                        metadata: paywallFunnelMetadata
                    )
                }
                verifyStandaloneSubscriptionAccessAndShowSuccess(plan: plan, context: "storekit_purchase")
            case .failure(let error):
                if PurchaseService.sharedInstance.isPurchaseCanceledError(error) {
                    MacraPurchaseLogService.shared.markCanceled(
                        logID: activePurchaseLogID,
                        plan: plan,
                        source: paywallAnalyticsSource,
                        error: error,
                        failureReason: "storekit_cancelled",
                        metadata: purchaseLogMetadata(channel: "storekit")
                    )
                    if shouldTrackPaywallAnalytics {
                        MacraAnalyticsService.shared.trackSubscriptionPurchaseCancelled(
                            plan: plan,
                            source: paywallAnalyticsSource,
                            error: error,
                            metadata: paywallFunnelMetadata
                        )
                    }
                    standalonePurchaseError = nil
                    presentCancelFeedbackDialogAfterPurchaseCancel(trigger: "storekit_cancelled")
                } else {
                    MacraPurchaseLogService.shared.markFailed(
                        logID: activePurchaseLogID,
                        plan: plan,
                        source: paywallAnalyticsSource,
                        error: error,
                        failureReason: "storekit_purchase_failed",
                        metadata: purchaseLogMetadata(channel: "storekit")
                    )
                    activePurchaseLogID = nil
                    if shouldTrackPaywallAnalytics {
                        MacraAnalyticsService.shared.trackSubscriptionPurchaseFailed(
                            plan: plan,
                            source: paywallAnalyticsSource,
                            error: error,
                            metadata: paywallFunnelMetadata
                        )
                    }
                    standalonePurchaseError = MacraUserFacingError.purchase(error)
                    print("There was an error while purchasing \(error)")
                }
            }
        }
    }

    private func scheduleTrialEndingReminderIfRequested() {
        guard !isDemoMode,
              let trialDays = trialDisclosureDays,
              let leadDays = trialReminderLeadDaysForScheduling else { return }

        NotificationService.sharedInstance.scheduleTrialEndingReminder(
            trialDays: trialDays,
            leadDays: leadDays
        )
    }

    private func triggerRestore() {
        if let coordinator = onboardingCoordinator {
            coordinator.restorePurchasesAndContinue()
            return
        }
        restoreStandalone()
    }

    private func restoreStandalone() {
        if shouldUseDemoPlans {
            viewModel.appCoordinator.showToast(viewModel: ToastViewModel(
                message: "Demo restore tapped",
                backgroundColor: .secondaryCharcoal,
                textColor: .secondaryWhite
            ))
            finishStandalonePaywall()
            return
        }

        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackSubscriptionRestoreAttempted(source: paywallAnalyticsSource)
        }

        PurchaseService.sharedInstance.restoreSubscriptionStatus { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let restored):
                    if restored {
                        if shouldTrackPaywallAnalytics {
                            MacraAnalyticsService.shared.trackSubscriptionRestoreSucceeded(source: paywallAnalyticsSource)
                        }
                        verifyStandaloneSubscriptionAccessAndShowSuccess(plan: selectedPlan, context: "restore_purchases")
                    } else {
                        if shouldTrackPaywallAnalytics {
                            MacraAnalyticsService.shared.trackSubscriptionRestoreFailed(
                                source: paywallAnalyticsSource,
                                reason: "no_active_subscription"
                            )
                        }
                        viewModel.appCoordinator.showToast(viewModel: ToastViewModel(
                            message: "No active subscription found for this Apple ID.",
                            backgroundColor: .secondaryCharcoal,
                            textColor: .secondaryWhite
                        ))
                    }
                case .failure(let error):
                    if shouldTrackPaywallAnalytics {
                        MacraAnalyticsService.shared.trackSubscriptionRestoreFailed(
                            source: paywallAnalyticsSource,
                            reason: "restore_error",
                            error: error
                        )
                    }
                    print("There was an error while restoring purchases \(error)")
                    viewModel.appCoordinator.showToast(viewModel: ToastViewModel(
                        message: "We could not restore purchases. Please try again.",
                        backgroundColor: .secondaryCharcoal,
                        textColor: .secondaryWhite
                    ))
                }
            }
        }
    }

    private func openPrivacy() {
        if let coordinator = onboardingCoordinator {
            coordinator.appCoordinator.showPrivacyScreenModal()
        } else if !isDemoMode || usesLivePurchasesInDemo {
            viewModel.appCoordinator.showPrivacyScreenModal()
        }
    }

    private func openTerms() {
        if let coordinator = onboardingCoordinator {
            coordinator.appCoordinator.modalScreen = .terms
        } else if !isDemoMode || usesLivePurchasesInDemo {
            viewModel.appCoordinator.modalScreen = .terms
        }
    }

    private func finishStandalonePaywall() {
        viewModel.appCoordinator.showNutritionTab(.journal)
        if let onDismiss {
            onDismiss()
        } else {
            viewModel.appCoordinator.closeModals()
        }
    }

    private func showSubscriptionSuccessAndEnterDashboard() {
        standalonePurchaseError = nil
        onboardingCoordinator?.purchaseError = nil
        showSubscriptionSuccess = true
    }

    private func finishSubscriptionSuccessFlow() {
        trackSubscriptionSuccessActivationPrimaryIfNeeded(actionTitle: "Start with one meal")
        showSubscriptionSuccess = false
        finishStandalonePaywall()
    }

    // MARK: - Tracking / loading

    @MainActor
    private func refreshPaywallExperimentSelection() async {
        if let defaultPlanSelectionOverride,
           paywallDefaultPlanSelection != defaultPlanSelectionOverride {
            paywallDefaultPlanSelection = defaultPlanSelectionOverride
            ensureVisiblePlanSelected()
        }

        if let layoutVariantOverride,
           paywallLayoutVariant != layoutVariantOverride {
            paywallLayoutVariant = layoutVariantOverride
        }

        guard defaultPlanSelectionOverride == nil || layoutVariantOverride == nil else { return }
        guard !shouldUseDemoPlans else { return }

        let assignment = await MacraPaywallExperimentService.fetchAndActivateAssignment()
        paywallExperimentAssignment = assignment
        if defaultPlanSelectionOverride == nil,
           paywallDefaultPlanSelection != assignment.defaultPlanSelection {
            paywallDefaultPlanSelection = assignment.defaultPlanSelection
            ensureVisiblePlanSelected()
        }

        if layoutVariantOverride == nil,
           paywallLayoutVariant != assignment.layoutVariant {
            paywallLayoutVariant = assignment.layoutVariant
        }
    }

    @MainActor
    private func loadPlansAndTrackPaywallView() async {
        if shouldUseDemoPlans {
            didTrackPaywallView = true
            return
        }

        if hasExistingSubscriptionAccess {
            trackExistingAccessViewIfReady()
            return
        }

        if onboardingCoordinator == nil,
           offeringViewModel.planOptions.isEmpty,
           !offeringViewModel.isLoadingPackages {
            await offeringViewModel.start(source: paywallAnalyticsSource)
        }

        ensureVisiblePlanSelected()
        trackPaywallViewedIfReady()
        trackWebCheckoutFallbackPresentedIfReady()
    }

    @MainActor
    private func trackPaywallViewedIfReady() {
        guard shouldTrackPaywallAnalytics, !didTrackPaywallView else { return }
        guard !hasExistingSubscriptionAccess else {
            trackExistingAccessViewIfReady()
            return
        }
        guard !availablePlans.isEmpty else { return }

        didTrackPaywallView = true
        MacraAnalyticsService.shared.trackPaywallViewed(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            availablePlans: availablePlans,
            metadata: paywallFunnelMetadata
        )
    }

    @MainActor
    private func trackExistingAccessViewIfReady() {
        guard shouldTrackPaywallAnalytics, !didTrackExistingAccessView else { return }
        didTrackExistingAccessView = true
        MacraAnalyticsService.shared.trackExistingSubscriptionAccessViewed(source: paywallAnalyticsSource)
    }

    private func trackPaywallPrimaryButtonPressedIfNeeded() {
        guard shouldTrackPaywallAnalytics else { return }
        MacraAnalyticsService.shared.trackPaywallPrimaryButtonPressed(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            ctaTitle: ctaTitle,
            availablePlanCount: availablePlans.count,
            isLoadingPackages: isLoadingPackages,
            packageLoadError: packageLoadError,
            isPurchasing: isPurchasing,
            hasExistingSubscriptionAccess: hasExistingSubscriptionAccess,
            ctaDecision: primaryCTAAnalyticsDecision,
            usesWebCheckoutFallback: shouldUseWebCheckoutFallback,
            fallbackReason: shouldUseWebCheckoutFallback ? webCheckoutFallbackReason : nil,
            metadata: paywallFunnelMetadata
        )
    }

    private func trackSubscriptionSuccessActivationViewedIfNeeded() {
        guard shouldTrackPaywallAnalytics, !didTrackSubscriptionSuccessActivationView else { return }
        didTrackSubscriptionSuccessActivationView = true
        MacraAnalyticsService.shared.trackTrialActivationScreenViewed(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            metadata: paywallFunnelMetadata
        )
    }

    private func trackSubscriptionSuccessActivationPrimaryIfNeeded(actionTitle: String) {
        guard shouldTrackPaywallAnalytics, !didTrackSubscriptionSuccessActivationPrimary else { return }
        didTrackSubscriptionSuccessActivationPrimary = true
        MacraAnalyticsService.shared.trackTrialActivationPrimaryPressed(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            actionTitle: actionTitle,
            metadata: paywallFunnelMetadata
        )
    }

    private func purchaseLogMetadata(channel: String, extra: [String: Any] = [:]) -> [String: Any] {
        var metadata = paywallFunnelMetadata
        metadata["purchase_channel"] = channel
        metadata["selected_plan_id"] = selectedPlan?.id ?? "none"
        metadata["selected_plan_period"] = selectedPlan.map { periodAnalyticsName($0.periodKind) } ?? "none"
        extra.forEach { metadata[$0.key] = $0.value }
        return metadata
    }

    private func trackPaywallValuePreviewViewedIfNeeded(previewType: String) {
        guard shouldTrackPaywallAnalytics, !didTrackPaywallValuePreviewView else { return }
        guard !hasExistingSubscriptionAccess else { return }

        didTrackPaywallValuePreviewView = true
        MacraAnalyticsService.shared.trackPaywallValuePreviewViewed(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            availablePlans: availablePlans,
            previewType: previewType,
            metadata: paywallFunnelMetadata
        )
    }

    private func trackPricingDisclosureViewedIfNeeded() {
        guard shouldTrackPaywallAnalytics, !didTrackPricingDisclosureView else { return }
        guard !hasExistingSubscriptionAccess else { return }

        didTrackPricingDisclosureView = true
        MacraAnalyticsService.shared.trackPaywallPricingDisclosureViewed(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            availablePlans: availablePlans,
            disclosureText: usesHardPaywallValueLayout
                ? priceDisclosureText
                : ((usesTrialConfidenceLayout || usesTrialPrepCompactLayout) ? trialConfidenceIntro : purchaseExpectationBody),
            metadata: paywallFunnelMetadata
        )
    }

    private func trackTrialConfidenceViewedIfNeeded() {
        guard shouldTrackPaywallAnalytics, !didTrackTrialConfidenceView else { return }
        guard !hasExistingSubscriptionAccess else { return }

        didTrackTrialConfidenceView = true
        MacraAnalyticsService.shared.trackPaywallTrialConfidenceViewed(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            availablePlans: availablePlans,
            metadata: paywallFunnelMetadata
        )
    }

    @MainActor
    private func trackWebCheckoutFallbackPresentedIfReady() {
        guard shouldTrackPaywallAnalytics,
              !didTrackWebCheckoutFallbackPresented,
              shouldUseWebCheckoutFallback else { return }

        didTrackWebCheckoutFallbackPresented = true
        MacraAnalyticsService.shared.trackSubscriptionWebCheckoutFallbackPresented(
            source: paywallAnalyticsSource,
            reason: webCheckoutFallbackReason,
            ctaTitle: ctaTitle,
            availablePlanCount: availablePlans.count,
            isLoadingPackages: isLoadingPackages,
            packageLoadError: packageLoadError,
            metadata: paywallFunnelMetadata
        )
    }

    private func trackWebCheckoutFallbackPressedIfNeeded() {
        guard shouldTrackPaywallAnalytics else { return }
        MacraAnalyticsService.shared.trackSubscriptionWebCheckoutFallbackPressed(
            source: paywallAnalyticsSource,
            reason: webCheckoutFallbackReason,
            ctaTitle: ctaTitle,
            availablePlanCount: availablePlans.count,
            isLoadingPackages: isLoadingPackages,
            packageLoadError: packageLoadError,
            metadata: paywallFunnelMetadata
        )
    }

    private func trackPaywallCTABlockedIfNeeded(reason: String) {
        guard shouldTrackPaywallAnalytics else { return }
        MacraAnalyticsService.shared.trackPaywallCTABlocked(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            reason: reason,
            ctaTitle: ctaTitle,
            availablePlanCount: availablePlans.count,
            isLoadingPackages: isLoadingPackages,
            packageLoadError: packageLoadError,
            metadata: paywallFunnelMetadata
        )
    }

    private func handlePaywallBackPressed() {
        if usesTrialPrepCompactLayout, let previousStep = compactPaywallStep.previous {
            withAnimation(.easeInOut(duration: 0.2)) {
                compactPaywallStep = previousStep
            }
            return
        }

        trackPaywallDismissedIfNeeded(reason: "back_button")
        onboardingCoordinator?.back()
    }

    private func handlePaywallClosePressed() {
        trackPaywallDismissedIfNeeded(reason: "close_button")
        onDismiss?()
    }

    private func trackPaywallDismissedIfNeeded(reason: String) {
        guard shouldTrackPaywallAnalytics, !didTrackPaywallDismissed else { return }
        didTrackPaywallDismissed = true

        var metadata = paywallFunnelMetadata
        metadata["paywall_dismiss_reason"] = reason

        MacraAnalyticsService.shared.trackPaywallDismissed(
            source: paywallAnalyticsSource,
            selectedPlan: selectedPlan,
            metadata: metadata
        )
    }

    private func presentCancelFeedbackDialog(trigger: String) {
        guard !didAskCancelFeedback else { return }
        clearPurchaseLoadingForCancelFeedback()
        cancelFeedbackTrigger = trigger
        didAskCancelFeedback = true
        didSubmitCancelFeedback = false
        showCancelFeedbackDialog = true

        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackPaywallCancelFeedbackPresented(
                source: paywallAnalyticsSource,
                selectedPlan: selectedPlan,
                trigger: trigger,
                metadata: paywallFunnelMetadata
            )
        }
    }

    private func presentCancelFeedbackDialogAfterPurchaseCancel(trigger: String) {
        if let purchaseLogID = onboardingCoordinator?.currentPurchaseLogIDForFeedback,
           !purchaseLogID.isEmpty,
           activePurchaseLogID == nil {
            activePurchaseLogID = purchaseLogID
        }

        clearPurchaseLoadingForCancelFeedback()
        cancelFeedbackPresentationTask?.cancel()
        cancelFeedbackPresentationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            cancelFeedbackPresentationTask = nil
            presentCancelFeedbackDialog(trigger: trigger)
        }
    }

    private func clearPurchaseLoadingForCancelFeedback() {
        isStandalonePurchasing = false
        isPreparingWebCheckout = false
        isWebCheckoutCompleting = false
        isVerifyingSubscriptionAccess = false
        standalonePurchaseError = nil
        onboardingCoordinator?.isPurchasing = false
        onboardingCoordinator?.purchaseError = nil
    }

    private func submitCancelFeedback(_ reason: PaywallCancelFeedbackReason) {
        cancelFeedbackPresentationTask?.cancel()
        cancelFeedbackPresentationTask = nil
        didSubmitCancelFeedback = true
        showCancelFeedbackDialog = false
        let didAttemptPersistence = persistCancelFeedback(reason)
        MacraPurchaseLogService.shared.attachCancelReason(
            logID: activePurchaseLogID,
            reasonCode: reason.rawValue,
            reasonLabel: reason.title,
            trigger: cancelFeedbackTrigger,
            metadata: paywallFunnelMetadata
        )
        activePurchaseLogID = nil

        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackPaywallCancelFeedbackSubmitted(
                source: paywallAnalyticsSource,
                selectedPlan: selectedPlan,
                trigger: cancelFeedbackTrigger,
                reason: reason.rawValue,
                reasonLabel: reason.title,
                metadata: paywallFunnelMetadata
            )
        }

        let toastMessage = shouldPersistCancelFeedback && isDemoMode && !didAttemptPersistence
            ? "Sign in before testing Firestore save."
            : "Thanks. That helps us improve Macra."
        activeAppCoordinator?.showToast(viewModel: ToastViewModel(
            message: toastMessage,
            backgroundColor: .secondaryCharcoal,
            textColor: .secondaryWhite
        ))
    }

    private func persistCancelFeedback(_ reason: PaywallCancelFeedbackReason) -> Bool {
        guard shouldPersistCancelFeedback else {
            print("[Macra][PaywallCancelFeedback] Demo persistence disabled; skipping Firestore save")
            return false
        }

        guard let user = Auth.auth().currentUser, !user.uid.isEmpty else {
            print("[Macra][PaywallCancelFeedback] No signed-in user; skipping Firestore save")
            return false
        }

        let feedbackRef = Firestore.firestore()
            .collection("Macrafeedbackreason")
            .document()

        let selectedPlanPeriod = selectedPlan.map { periodAnalyticsName($0.periodKind) } ?? "none"
        let capturedAt = Timestamp(date: Date())
        let latestSummary: [String: Any] = [
            "id": feedbackRef.documentID,
            "reason": reason.rawValue,
            "reasonLabel": reason.title,
            "trigger": cancelFeedbackTrigger,
            "source": paywallAnalyticsSource,
            "selectedPlanId": selectedPlan?.id ?? "none",
            "selectedPlanPeriod": selectedPlanPeriod,
            "capturedAt": capturedAt,
            "isScreenDemo": isDemoMode,
        ]

        var payload: [String: Any] = latestSummary
        payload["userId"] = user.uid
        payload["email"] = user.email ?? ""
        payload["surface"] = "paywall_cancel_feedback"
        payload["app"] = "macra"
        payload["isScreenDemo"] = isDemoMode
        payload["createdAt"] = FieldValue.serverTimestamp()
        payload["metadata"] = paywallFunnelMetadata

        let userRef = Firestore.firestore()
            .collection("users")
            .document(user.uid)
        let batch = Firestore.firestore().batch()
        batch.setData(payload, forDocument: feedbackRef, merge: true)
        batch.setData([
            "macraLatestPaywallCancelFeedback": latestSummary,
            "macraLatestPaywallCancelFeedbackAt": FieldValue.serverTimestamp(),
            "macraPaywallCancelFeedbackCount": FieldValue.increment(Int64(1)),
        ], forDocument: userRef, merge: true)
        batch.commit { error in
            if let error {
                print("[Macra][PaywallCancelFeedback] Firestore save failed: \(error.localizedDescription)")
            } else {
                print("[Macra][PaywallCancelFeedback] Firestore saved collection=Macrafeedbackreason reason=\(reason.rawValue)")
            }
        }
        return true
    }

    private func dismissCancelFeedback(reason: String) {
        cancelFeedbackPresentationTask?.cancel()
        cancelFeedbackPresentationTask = nil
        showCancelFeedbackDialog = false
        guard didAskCancelFeedback, !didSubmitCancelFeedback else { return }
        activePurchaseLogID = nil

        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackPaywallCancelFeedbackDismissed(
                source: paywallAnalyticsSource,
                selectedPlan: selectedPlan,
                trigger: cancelFeedbackTrigger,
                reason: reason,
                metadata: paywallFunnelMetadata
            )
        }
    }

    private var activeAppCoordinator: AppCoordinator? {
        onboardingCoordinator?.appCoordinator ?? viewModel.appCoordinator
    }

    // MARK: - Plan list helpers

    private func periodAnalyticsName(_ period: SubscriptionPlanPeriodKind) -> String {
        switch period {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        case .unknown: return "unknown"
        }
    }

    private static func paywallPlans(
        from plans: [SubscriptionPlanOption],
        preferMonthlyFirst: Bool
    ) -> [SubscriptionPlanOption] {
        let annual = plans.first(where: { $0.periodKind == .year })
        let monthly = plans.first(where: { $0.periodKind == .month })
        let primaryPlans = preferMonthlyFirst
            ? [monthly, annual].compactMap { $0 }
            : [annual, monthly].compactMap { $0 }

        if !primaryPlans.isEmpty {
            return primaryPlans
        }

        return plans
            .filter { [.year, .month].contains($0.periodKind) }
            .sorted { $0.periodKind.rawValue < $1.periodKind.rawValue }
    }

    private static func hardPaywallPlans(from plans: [SubscriptionPlanOption]) -> [SubscriptionPlanOption] {
        let directPlans = plans
            .filter { $0.periodKind == .month && ($0.trialDays ?? 0) <= 0 }
            .sorted { left, right in
                NSDecimalNumber(decimal: left.price).doubleValue < NSDecimalNumber(decimal: right.price).doubleValue
            }

        return directPlans
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
}

// MARK: - Photo-scan moment with animated scan sweep + macro reveal

private struct PayWallRevealMoment: View {
    @State private var scanStartedAt: Date?
    @State private var revealStartedAt: Date?
    @State private var showNoraLine = false
    @State private var animateBars = false

    private static let scanDuration: TimeInterval = 1.35
    private static let countDuration: TimeInterval = 0.95

    var body: some View {
        MacraGlassCard(accent: .primaryGreen, tint: .primaryGreen, tintOpacity: 0.06) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("PHOTO SCAN")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundColor(.white.opacity(0.62))

                    Spacer()

                    Label("10 sec", systemImage: "bolt.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.primaryGreen)
                }

                HStack(alignment: .top, spacing: 12) {
                    PayWallMealSnapshot(
                        scanStartedAt: scanStartedAt,
                        scanDuration: Self.scanDuration,
                        countDuration: Self.countDuration
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        PayWallMacroLine(label: "Protein", target: 48, fillTarget: 0.82, tint: .primaryGreen, revealStartedAt: revealStartedAt, duration: Self.countDuration, animateBar: animateBars)
                        PayWallMacroLine(label: "Carbs", target: 63, fillTarget: 0.62, tint: .primaryBlue, revealStartedAt: revealStartedAt, duration: Self.countDuration, animateBar: animateBars)
                        PayWallMacroLine(label: "Fat", target: 19, fillTarget: 0.38, tint: .secondaryPink, revealStartedAt: revealStartedAt, duration: Self.countDuration, animateBar: animateBars)
                    }
                    .padding(13)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 28, height: 28)
                        .background(Color.primaryGreen)
                        .clipShape(Circle())

                    Text("Nora: You're short 42g protein. Dinner should be lean protein + low-fat carbs.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(showNoraLine ? 1 : 0)
                .offset(y: showNoraLine ? 0 : 8)
                .animation(.easeOut(duration: 0.45), value: showNoraLine)
            }
        }
        .onAppear { runAnimationSequence() }
    }

    private func runAnimationSequence() {
        guard scanStartedAt == nil else { return }
        scanStartedAt = Date()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanDuration) {
            revealStartedAt = Date()
            withAnimation(.easeOut(duration: Self.countDuration)) {
                animateBars = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanDuration + Self.countDuration + 0.12) {
            showNoraLine = true
        }
    }
}

private struct PayWallMealSnapshot: View {
    let scanStartedAt: Date?
    let scanDuration: TimeInterval
    let countDuration: TimeInterval

    private let frameSize: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Image("chipotleBowl")
                    .resizable()
                    .scaledToFill()
                    .frame(width: frameSize, height: frameSize)

                LinearGradient(
                    colors: [.black.opacity(0.02), .black.opacity(0.52)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(width: frameSize, height: frameSize)

                if let scanStartedAt {
                    scanOverlay(startedAt: scanStartedAt)
                }

                VStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    Text("Chipotle bowl")
                        .font(.caption.weight(.black))
                        .foregroundColor(.white)
                }
            }
            .frame(width: frameSize, height: frameSize)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .accessibilityLabel("Chipotle bowl scan preview")

            countingCalories
                .font(.title3.weight(.black))
                .foregroundColor(.white)
                .monospacedDigit()

            Text("Fits today with one adjustment")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func scanOverlay(startedAt: Date) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let progress = min(1, elapsed / scanDuration)
            let lineY = frameSize * CGFloat(progress)
            let scanning = progress < 1.0

            ZStack(alignment: .top) {
                if scanning {
                    LinearGradient(
                        colors: [
                            Color.primaryGreen.opacity(0),
                            Color.primaryGreen.opacity(0.32),
                            Color.primaryGreen.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: frameSize, height: 42)
                    .offset(y: lineY - 21)
                    .blendMode(.plusLighter)

                    Rectangle()
                        .fill(Color.primaryGreen.opacity(0.95))
                        .frame(width: frameSize, height: 1.4)
                        .offset(y: lineY - 0.7)
                        .shadow(color: Color.primaryGreen.opacity(0.65), radius: 4)
                        .blendMode(.plusLighter)
                }
            }
            .frame(width: frameSize, height: frameSize, alignment: .top)
            .clipped()
        }
    }

    @ViewBuilder
    private var countingCalories: some View {
        if let scanStartedAt {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(scanStartedAt) - scanDuration)
                let progress = max(0, min(1, elapsed / countDuration))
                let eased = 1 - pow(1 - progress, 3)
                let value = Int((730.0 * eased).rounded())
                Text("\(value) kcal")
            }
        } else {
            Text("0 kcal")
        }
    }
}

private struct PayWallMacroLine: View {
    let label: String
    let target: Int
    let fillTarget: CGFloat
    let tint: Color
    let revealStartedAt: Date?
    let duration: TimeInterval
    let animateBar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.black.opacity(0.58))

                Spacer()

                countingValue
                    .font(.caption.weight(.black))
                    .foregroundColor(.black)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.08))

                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, proxy.size.width * (animateBar ? fillTarget : 0)))
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private var countingValue: some View {
        if let revealStartedAt {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(revealStartedAt))
                let progress = min(1, elapsed / duration)
                let eased = 1 - pow(1 - progress, 3)
                let value = Int((Double(target) * eased).rounded())
                Text("\(value)g")
            }
        } else {
            Text("0g")
        }
    }
}

struct PayWallView_Previews: PreviewProvider {
    static var previews: some View {
        PayWallView(viewModel: PayWallViewModel(appCoordinator: AppCoordinator(serviceManager: ServiceManager())), isDemoMode: true)
    }
}

struct MacraReviewPaywallScreenshotView: View {
    @ObservedObject private var offering = OfferingViewModel.sharedInstance

    private let featureChips = [
        "3-day trial",
        "Meal scan",
        "Menu choices",
        "Buddies"
    ]

    private var annualPrice: String? {
        offering.planOptions.first(where: { $0.periodKind == .year })?.priceLabel
    }

    private var monthlyPrice: String? {
        offering.planOptions.first(where: { $0.periodKind == .month })?.priceLabel
    }

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("MACRA PLUS")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundColor(.primaryGreen)

                        Text("Build the body you want without giving up the food you love.")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Scan meals, make smarter menu choices, ask Nora what fits, and share eating habits with friends.")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    MacraAuthChipRow(labels: featureChips)

                    VStack(spacing: 14) {
                        MacraReviewPlanCard(
                            accent: .primaryGreen,
                            tint: .primaryGreen,
                            badge: "Most Popular",
                            title: "Annual",
                            subtitle: "Try 3 days free",
                            price: annualPrice,
                            cadence: "per year",
                            supportingLine: "Best value for everyday progress"
                        )

                        MacraReviewPlanCard(
                            accent: .primaryBlue,
                            tint: .primaryBlue,
                            badge: "Flexible",
                            title: "Monthly",
                            subtitle: "Try 3 days free",
                            price: monthlyPrice,
                            cadence: "per month",
                            supportingLine: "Start anytime, cancel anytime"
                        )
                    }

                    MacraGlassCard(accent: .white, tint: .white, tintOpacity: 0.04) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primaryGreen)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Includes the full Macra nutrition experience")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)

                                Text("Photo scans, label checks, menu decisions, Nora coaching, Buddies, share cards, and Fit With Pulse Pro.")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.white.opacity(0.68))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    HStack(spacing: 14) {
                        MacraReviewFooterPill(label: "Restore Purchases")
                        MacraReviewFooterPill(label: "Terms")
                        MacraReviewFooterPill(label: "Privacy")
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard offering.planOptions.isEmpty, !offering.isLoadingPackages else { return }
            Task { await offering.start(source: "subscription_review") }
        }
    }
}

private struct MacraReviewPlanCard: View {
    let accent: Color
    let tint: Color
    let badge: String
    let title: String
    let subtitle: String
    let price: String?
    let cadence: String
    let supportingLine: String

    var body: some View {
        MacraGlassCard(accent: accent, tint: tint, tintOpacity: 0.08) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(badge.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.12))
                        .clipShape(Capsule())

                    Text(title)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.68))

                    Text(supportingLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.54))
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    if let price {
                        Text(price)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(height: 34)
                    }

                    Text(cadence)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.62))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

private struct MacraReviewFooterPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}
