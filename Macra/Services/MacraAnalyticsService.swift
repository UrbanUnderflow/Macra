import Foundation
import FirebaseCore
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

#if canImport(TikTokBusinessSDK)
import TikTokBusinessSDK
#endif

enum MacraAnalyticsEventName: String {
    case paywallViewed = "paywall_viewed"
    case journalViewed = "journal_viewed"
    case startTrial = "start_trial"
    case purchase = "purchase"
}

private enum AppsFlyerAnalyticsEvent {
    static let appOpened = "af_app_opened"
    static let completeRegistration = "af_complete_registration"
    static let contentView = "af_content_view"
    static let initiatedCheckout = "af_initiated_checkout"
    static let startTrial = "af_start_trial"
    static let subscribe = "af_subscribe"
    static let purchase = "af_purchase"
    static let planSelected = "macra_subscription_plan_selected"
    static let purchaseCancelled = "macra_subscription_purchase_cancelled"
    static let purchaseFailed = "macra_subscription_purchase_failed"
    static let accessVerified = "macra_subscription_access_verified"
    static let accessVerificationFailed = "macra_subscription_access_verification_failed"
    static let restoreAttempted = "macra_subscription_restore_attempted"
    static let restoreSucceeded = "macra_subscription_restore_succeeded"
    static let restoreFailed = "macra_subscription_restore_failed"
    static let existingAccessViewed = "macra_subscription_existing_access_viewed"
    static let existingAccessContinued = "macra_subscription_existing_access_continued"
    static let paywallViewed = "macra_paywall_viewed_standalone"
    static let paywallPrimaryButtonPressed = "macra_paywall_primary_button_pressed"
    static let paywallValuePreviewViewed = "macra_paywall_value_preview_viewed"
    static let paywallPricingDisclosureViewed = "macra_paywall_pricing_disclosure_viewed"
    static let paywallTrialConfidenceViewed = "macra_paywall_trial_confidence_viewed"
    static let paywallCTABlocked = "macra_paywall_cta_blocked"
    static let paywallCancelFeedbackPresented = "macra_paywall_cancel_feedback_presented"
    static let paywallCancelFeedbackSubmitted = "macra_paywall_cancel_feedback_submitted"
    static let paywallCancelFeedbackDismissed = "macra_paywall_cancel_feedback_dismissed"
    static let paywallCancelReasonPriceTooHigh = "macra_paywall_cancel_reason_price_too_high"
    static let paywallCancelReasonNotReady = "macra_paywall_cancel_reason_not_ready"
    static let paywallCancelReasonNeedMoreProof = "macra_paywall_cancel_reason_need_more_proof"
    static let paywallCancelReasonAppleSheetConfusing = "macra_paywall_cancel_reason_apple_sheet_confusing"
    static let paywallCancelReasonWrongPlan = "macra_paywall_cancel_reason_wrong_plan"
    static let paywallCancelReasonSomethingDidNotWork = "macra_paywall_cancel_reason_something_did_not_work"
    static let paywallCancelReasonUnknown = "macra_paywall_cancel_reason_unknown"
    static let paywallDismissed = "macra_paywall_dismissed"
    static let plansLoadStarted = "macra_subscription_plans_load_started"
    static let plansLoaded = "macra_subscription_plans_loaded"
    static let plansLoadFailed = "macra_subscription_plans_load_failed"
    static let webCheckoutFallbackPresented = "macra_subscription_web_checkout_fallback_presented"
    static let webCheckoutFallbackPressed = "macra_subscription_web_checkout_fallback_pressed"
    static let webCheckoutStarted = "macra_subscription_web_checkout_started"
    static let webCheckoutReturned = "macra_subscription_web_checkout_returned"
    static let webCheckoutFailed = "macra_subscription_web_checkout_failed"
    static let onboardingStarted = "macra_onboarding_started"
    static let onboardingProfileCompleted = "macra_onboarding_profile_completed"
    static let onboardingPaywallReached = "macra_onboarding_paywall_reached"
    static let onboardingCompleted = "macra_onboarding_completed"
    static let onboardingStepViewed = "macra_onboarding_step_viewed"
    static let onboardingStepCompleted = "macra_onboarding_step_completed"
    static let onboardingStepBack = "macra_onboarding_step_back"
    static let onboardingExited = "macra_onboarding_exited"
}

private enum AppsFlyerAnalyticsParam {
    static let contentId = "af_content_id"
    static let contentType = "af_content_type"
    static let currency = "af_currency"
    static let description = "af_description"
    static let price = "af_price"
    static let registrationMethod = "af_registration_method"
    static let revenue = "af_revenue"
}

final class MacraAnalyticsService {
    static let shared = MacraAnalyticsService()

    private let appName = "macra"
    private let platform = "ios"
    private var didLogMissingTikTokConfig = false
    private var didTrackAppOpened = false
    private var trackedRegistrationSources: Set<String> = []

    private init() {}

    func configureTikTokSDK() {
        #if canImport(TikTokBusinessSDK)
        guard !TikTokBusiness.isInitialized() else { return }
        guard let appId = infoString("TikTokDeveloperAppID"),
              let tikTokAppId = infoString("TikTokAppID"),
              let accessToken = infoString("TikTokAccessToken") else {
            logMissingTikTokConfigIfNeeded()
            return
        }

        guard let config = TikTokConfig(
            accessToken: accessToken,
            appId: appId,
            tiktokAppId: tikTokAppId
        ) else {
            print("[Macra][Analytics] TikTokConfig could not be created.")
            return
        }

        config.disablePaymentTracking()
        config.setDelayForATTUserAuthorizationInSeconds(20)

        #if DEBUG
        if infoBool("TikTokManualDebugModeEnabled") {
            config.enableDebugMode()
        }
        config.setLogLevel(TikTokLogLevelVerbose)
        #endif

        TikTokBusiness.initializeSdk(config) { success, error in
            if success {
                #if DEBUG
                let mode = TikTokBusiness.isDebugMode() ? "manual-debug" : "live"
                print("[Macra][Analytics] TikTok SDK initialized. mode=\(mode)")
                #else
                print("[Macra][Analytics] TikTok SDK initialized.")
                #endif
            } else {
                print("[Macra][Analytics] TikTok SDK failed to initialize: \(error?.localizedDescription ?? "unknown error")")
            }
        }
        #else
        print("[Macra][Analytics] TikTokBusinessSDK is not linked.")
        #endif
    }

    func identifyCurrentUserIfAvailable() {
        identifyAppsFlyerUserIfAvailable()

        #if canImport(FirebaseAnalytics)
        if FirebaseApp.app() != nil,
           let user = UserService.sharedInstance.user {
            Analytics.setUserID(user.id)
        }
        #endif

        #if canImport(TikTokBusinessSDK)
        guard TikTokBusiness.isInitialized(),
              FirebaseApp.app() != nil,
              let user = UserService.sharedInstance.user else { return }

        TikTokBusiness.identify(
            withExternalID: user.id,
            externalUserName: user.username,
            phoneNumber: nil,
            email: user.email
        )
        #endif
    }

    func trackAppOpened(source: String = "app_launch") {
        guard !didTrackAppOpened else { return }
        didTrackAppOpened = true

        var properties = baseProperties(source: source)
        properties["content_type"] = "session"

        trackAppsFlyerEvent(
            name: AppsFlyerAnalyticsEvent.appOpened,
            eventId: makeEventId(prefix: "app_opened", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackAccountRegistrationCompleted(method: String, source: String = "account_registration") {
        let key = "\(source):\(method)"
        guard !trackedRegistrationSources.contains(key) else { return }
        trackedRegistrationSources.insert(key)

        var properties = baseProperties(source: source)
        properties["registration_method"] = method
        properties[AppsFlyerAnalyticsParam.registrationMethod] = method

        trackAppsFlyerEvent(
            name: AppsFlyerAnalyticsEvent.completeRegistration,
            eventId: makeEventId(prefix: "complete_registration", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackFirebasePaywallExperimentAssignment(
        defaultPlan: String,
        layoutVariant: String,
        source: String = "remote_config_fetch"
    ) {
        var properties = baseProperties(source: source)
        properties["funnel"] = "subscription"
        properties["funnel_step"] = "paywall_experiment_assignment"
        properties["macra_paywall_default_plan"] = defaultPlan
        properties["macra_paywall_layout_variant"] = layoutVariant

        trackFirebaseEvent(
            name: "macra_ab_assignment",
            eventId: makeEventId(prefix: "ab_assignment", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackPaywallViewed(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        availablePlans: [SubscriptionPlanOption],
        metadata: [String: Any] = [:]
    ) {
        let value = selectedPlan.map { analyticsValue(for: $0) } ?? 0
        let eventId = makeEventId(prefix: "paywall_viewed", source: source, plan: selectedPlan)
        var properties = baseProperties(source: source)
        properties["selected_plan_id"] = selectedPlan?.analyticsProductId ?? "none"
        properties["selected_plan_period"] = selectedPlan?.analyticsPeriod ?? "none"
        properties["selected_plan_price"] = value
        properties["currency"] = selectedPlan?.analyticsCurrencyCode ?? "USD"
        properties["available_plan_ids"] = availablePlans.map(\.analyticsProductId).joined(separator: ",")
        properties["available_plan_count"] = availablePlans.count
        properties["plans_loaded"] = !availablePlans.isEmpty
        mergeAnalyticsMetadata(metadata, into: &properties)

        var appsFlyerProperties = properties
        appsFlyerProperties[AppsFlyerAnalyticsParam.contentType] = "subscription_paywall"
        appsFlyerProperties[AppsFlyerAnalyticsParam.contentId] = selectedPlan?.analyticsProductId ?? "macra_subscription_paywall"
        appsFlyerProperties[AppsFlyerAnalyticsParam.description] = "Macra Pro paywall"

        if source == "onboarding" || source == "onboarding_paywall" {
            trackCustomLifecycleEvent(
                appsFlyerName: AppsFlyerAnalyticsEvent.onboardingPaywallReached,
                tikTokEventName: "MacraOnboardingPaywallReached",
                eventId: makeEventId(prefix: "onboarding_paywall_reached", source: source, plan: selectedPlan),
                properties: appsFlyerProperties,
                includeRevenue: false
            )
        }

        guard source == "standalone_paywall" else { return }

        trackAppsFlyerEvent(
            name: AppsFlyerAnalyticsEvent.contentView,
            eventId: eventId,
            properties: appsFlyerProperties,
            includeRevenue: false
        )

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.paywallViewed,
            tikTokEventName: "MacraPaywallViewed",
            eventId: makeEventId(prefix: "macra_paywall_viewed_standalone", source: source, plan: selectedPlan),
            properties: appsFlyerProperties,
            includeRevenue: false
        )

        #if canImport(TikTokBusinessSDK)
        guard tikTokReadyForTracking() else {
            print("[Macra][Analytics] TikTok \(MacraAnalyticsEventName.paywallViewed.rawValue) skipped because SDK is not ready. eventId=\(eventId)")
            return
        }

        identifyCurrentUserIfAvailable()

        let event = TikTokViewContentEvent()
        event.eventId = eventId
        event.setContentId(selectedPlan?.analyticsProductId ?? "macra_subscription_paywall")
        event.setCurrency(selectedPlan?.analyticsCurrency ?? TTCurrency(rawValue: "USD"))
        event.setDescription("Macra Pro paywall")
        event.setContentType("subscription")
        event.setValue(formatValue(value))

        if let selectedPlan {
            let content = TikTokContentParams()
            content.price = NSNumber(value: value)
            content.quantity = 1
            content.brand = "Macra"
            content.contentId = selectedPlan.analyticsProductId
            content.contentName = selectedPlan.displayTitle
            event.setContents([content])
        }

        for (key, value) in properties {
            event.addProperty(withKey: key, value: value)
        }

        TikTokBusiness.trackTTEvent(event)
        print("[Macra][Analytics] TikTok \(MacraAnalyticsEventName.paywallViewed.rawValue) tracked. eventId=\(eventId)")
        #else
        print("[Macra][Analytics] TikTok \(MacraAnalyticsEventName.paywallViewed.rawValue) skipped because SDK is not linked. eventId=\(eventId)")
        #endif
    }

    func trackSubscriptionStart(
        plan: SubscriptionPlanOption,
        source: String,
        metadata: [String: Any] = [:]
    ) {
        if let trialDays = plan.trialDays, trialDays > 0 {
            trackTrialStarted(plan: plan, trialDays: trialDays, source: source, metadata: metadata)
        } else {
            trackPurchase(plan: plan, source: source, metadata: metadata)
        }
    }

    func trackPaywallValuePreviewViewed(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        availablePlans: [SubscriptionPlanOption],
        previewType: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: selectedPlan,
            funnelStep: "paywall_value_preview_viewed"
        )
        properties["preview_type"] = previewType
        properties["available_plan_count"] = availablePlans.count
        properties["available_plan_ids"] = availablePlans.map(\.analyticsProductId).joined(separator: ",")
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.paywallValuePreviewViewed,
            tikTokEventName: "PaywallValuePreviewViewed",
            eventId: makeEventId(prefix: "paywall_value_preview_viewed", source: source, plan: selectedPlan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackPaywallPricingDisclosureViewed(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        availablePlans: [SubscriptionPlanOption],
        disclosureText: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: selectedPlan,
            funnelStep: "paywall_pricing_disclosure_viewed"
        )
        properties["available_plan_count"] = availablePlans.count
        properties["available_plan_ids"] = availablePlans.map(\.analyticsProductId).joined(separator: ",")
        properties["disclosure_text"] = truncated(disclosureText, maxLength: 500)
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.paywallPricingDisclosureViewed,
            tikTokEventName: "PaywallPricingDisclosureViewed",
            eventId: makeEventId(prefix: "paywall_pricing_disclosure_viewed", source: source, plan: selectedPlan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackPaywallTrialConfidenceViewed(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        availablePlans: [SubscriptionPlanOption],
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: selectedPlan,
            funnelStep: "paywall_trial_confidence_viewed"
        )
        properties["available_plan_count"] = availablePlans.count
        properties["available_plan_ids"] = availablePlans.map(\.analyticsProductId).joined(separator: ",")
        properties["confidence_element"] = "trial_timeline"
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.paywallTrialConfidenceViewed,
            tikTokEventName: "PaywallTrialConfidenceViewed",
            eventId: makeEventId(prefix: "paywall_trial_confidence_viewed", source: source, plan: selectedPlan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionPlanSelected(
        plan: SubscriptionPlanOption,
        source: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: plan,
            funnelStep: "plan_selected"
        )

        properties["selection_source"] = "paywall_plan_card"
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.planSelected,
            tikTokEventName: "SubscriptionPlanSelected",
            eventId: makeEventId(prefix: "subscription_plan_selected", source: source, plan: plan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionPurchaseAttempted(
        plan: SubscriptionPlanOption,
        source: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: plan,
            funnelStep: "purchase_attempted"
        )
        properties[AppsFlyerAnalyticsParam.contentId] = plan.analyticsProductId
        properties[AppsFlyerAnalyticsParam.contentType] = "subscription"
        properties[AppsFlyerAnalyticsParam.description] = "Macra Pro purchase attempted"
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.initiatedCheckout,
            tikTokEventName: "InitiateCheckout",
            eventId: makeEventId(prefix: "purchase_attempted", source: source, plan: plan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackPaywallPrimaryButtonPressed(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        ctaTitle: String,
        availablePlanCount: Int,
        isLoadingPackages: Bool,
        packageLoadError: String?,
        isPurchasing: Bool,
        hasExistingSubscriptionAccess: Bool,
        ctaDecision: String,
        usesWebCheckoutFallback: Bool,
        fallbackReason: String?,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: selectedPlan,
            funnelStep: "paywall_primary_button_pressed"
        )
        properties["button_name"] = "paywall_primary_cta"
        properties["cta_title"] = ctaTitle
        properties["available_plan_count"] = availablePlanCount
        properties["selected_plan_available"] = selectedPlan != nil
        properties["is_loading_packages"] = isLoadingPackages
        properties["is_purchasing"] = isPurchasing
        properties["has_existing_subscription_access"] = hasExistingSubscriptionAccess
        properties["cta_decision"] = ctaDecision
        properties["uses_web_checkout_fallback"] = usesWebCheckoutFallback
        if usesWebCheckoutFallback {
            properties["checkout_provider"] = "stripe"
            properties["checkout_plan_period"] = "annual"
            properties["content_id"] = "stripe_web_checkout"
            properties["fallback_reason"] = fallbackReason ?? "unknown"
        }
        if let packageLoadError {
            properties["package_load_error"] = truncated(packageLoadError)
        }
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.paywallPrimaryButtonPressed,
            tikTokEventName: "PaywallPrimaryButtonPressed",
            eventId: makeEventId(prefix: "paywall_primary_button_pressed", source: source, plan: selectedPlan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackPaywallCTABlocked(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        reason: String,
        ctaTitle: String,
        availablePlanCount: Int,
        isLoadingPackages: Bool,
        packageLoadError: String?,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: selectedPlan,
            funnelStep: "paywall_cta_blocked"
        )
        properties["cta_title"] = ctaTitle
        properties["blocked_reason"] = reason
        properties["failure_reason"] = reason
        properties["available_plan_count"] = availablePlanCount
        properties["selected_plan_available"] = selectedPlan != nil
        properties["is_loading_packages"] = isLoadingPackages
        if let packageLoadError {
            properties["package_load_error"] = truncated(packageLoadError)
        }
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.paywallCTABlocked,
            tikTokEventName: "PaywallCTABlocked",
            eventId: makeEventId(prefix: "paywall_cta_blocked", source: source, plan: selectedPlan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionPlansLoadStarted(source: String) {
        let properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "plans_load_started"
        )

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.plansLoadStarted,
            tikTokEventName: "SubscriptionPlansLoadStarted",
            eventId: makeEventId(prefix: "plans_load_started", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionPlansLoaded(
        source: String,
        currentOfferingIdentifier: String?,
        availablePackageCount: Int,
        supportedPackageCount: Int,
        packageIdentifiers: [String],
        productIdentifiers: [String]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "plans_loaded"
        )
        properties["revenuecat_current_offering_id"] = currentOfferingIdentifier ?? "none"
        properties["available_package_count"] = availablePackageCount
        properties["supported_package_count"] = supportedPackageCount
        properties["revenuecat_package_ids"] = truncated(packageIdentifiers.joined(separator: ", "), maxLength: 500)
        properties["revenuecat_product_ids"] = truncated(productIdentifiers.joined(separator: ", "), maxLength: 500)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.plansLoaded,
            tikTokEventName: "SubscriptionPlansLoaded",
            eventId: makeEventId(prefix: "plans_loaded", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionPlansLoadFailed(
        source: String,
        reason: String,
        currentOfferingIdentifier: String?,
        availablePackageCount: Int,
        supportedPackageCount: Int,
        packageIdentifiers: [String],
        productIdentifiers: [String],
        error: Error? = nil
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "plans_load_failed"
        )
        properties["failure_reason"] = reason
        properties["revenuecat_current_offering_id"] = currentOfferingIdentifier ?? "none"
        properties["available_package_count"] = availablePackageCount
        properties["supported_package_count"] = supportedPackageCount
        properties["revenuecat_package_ids"] = truncated(packageIdentifiers.joined(separator: ", "), maxLength: 500)
        properties["revenuecat_product_ids"] = truncated(productIdentifiers.joined(separator: ", "), maxLength: 500)

        if let error {
            properties.merge(errorAnalyticsProperties(error, reason: reason)) { _, new in new }
        }

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.plansLoadFailed,
            tikTokEventName: "SubscriptionPlansLoadFailed",
            eventId: makeEventId(prefix: "plans_load_failed", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionWebCheckoutFallbackPresented(
        source: String,
        reason: String,
        ctaTitle: String,
        availablePlanCount: Int,
        isLoadingPackages: Bool,
        packageLoadError: String?,
        metadata: [String: Any] = [:]
    ) {
        var properties = webCheckoutFallbackProperties(
            source: source,
            reason: reason,
            funnelStep: "web_checkout_fallback_presented",
            ctaTitle: ctaTitle,
            availablePlanCount: availablePlanCount,
            isLoadingPackages: isLoadingPackages,
            packageLoadError: packageLoadError,
            metadata: metadata
        )

        properties["fallback_visible"] = true

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.webCheckoutFallbackPresented,
            tikTokEventName: "SubscriptionWebCheckoutFallbackPresented",
            eventId: makeEventId(prefix: "web_checkout_fallback_presented", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionWebCheckoutFallbackPressed(
        source: String,
        reason: String,
        ctaTitle: String,
        availablePlanCount: Int,
        isLoadingPackages: Bool,
        packageLoadError: String?,
        metadata: [String: Any] = [:]
    ) {
        var properties = webCheckoutFallbackProperties(
            source: source,
            reason: reason,
            funnelStep: "web_checkout_fallback_pressed",
            ctaTitle: ctaTitle,
            availablePlanCount: availablePlanCount,
            isLoadingPackages: isLoadingPackages,
            packageLoadError: packageLoadError,
            metadata: metadata
        )

        properties["button_name"] = "paywall_primary_cta"

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.webCheckoutFallbackPressed,
            tikTokEventName: "SubscriptionWebCheckoutFallbackPressed",
            eventId: makeEventId(prefix: "web_checkout_fallback_pressed", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionWebCheckoutStarted(
        source: String,
        reason: String,
        checkoutURL: URL,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "web_checkout_started"
        )
        properties["fallback_reason"] = reason
        properties["checkout_provider"] = "stripe"
        properties["checkout_plan_period"] = "annual"
        properties["checkout_host"] = checkoutURL.host ?? "unknown"
        properties["checkout_path"] = checkoutURL.path
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.webCheckoutStarted,
            tikTokEventName: "SubscriptionWebCheckoutStarted",
            eventId: makeEventId(prefix: "web_checkout_started", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionWebCheckoutReturned(
        source: String,
        status: String,
        sessionId: String?,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "web_checkout_returned"
        )
        properties["return_status"] = status
        properties["stripe_session_id"] = sessionId ?? "none"
        properties["checkout_provider"] = "stripe"
        properties["checkout_plan_period"] = "annual"
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.webCheckoutReturned,
            tikTokEventName: "SubscriptionWebCheckoutReturned",
            eventId: makeEventId(prefix: "web_checkout_returned_\(status)", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionWebCheckoutFailed(
        source: String,
        reason: String,
        error: Error? = nil,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "web_checkout_failed"
        )
        properties["failure_reason"] = reason
        properties["checkout_provider"] = "stripe"
        properties["checkout_plan_period"] = "annual"
        if let error {
            properties.merge(errorAnalyticsProperties(error, reason: reason)) { _, new in new }
        }
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.webCheckoutFailed,
            tikTokEventName: "SubscriptionWebCheckoutFailed",
            eventId: makeEventId(prefix: "web_checkout_failed", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionPurchaseCancelled(
        plan: SubscriptionPlanOption,
        source: String,
        error: Error? = nil,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: plan,
            funnelStep: "purchase_cancelled"
        )
        properties["cancel_classification"] = error == nil ? "user_cancelled_no_error_payload" : "user_cancelled_error_payload"
        if let error {
            properties.merge(errorAnalyticsProperties(error, reason: "storekit_user_cancelled")) { _, new in new }
        }
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.purchaseCancelled,
            tikTokEventName: "PurchaseCancelled",
            eventId: makeEventId(prefix: "purchase_cancelled", source: source, plan: plan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackPaywallCancelFeedbackPresented(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        trigger: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: selectedPlan,
            funnelStep: "cancel_feedback_presented"
        )
        properties["cancel_feedback_trigger"] = trigger
        properties["feedback_surface"] = "confirmation_dialog"
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.paywallCancelFeedbackPresented,
            tikTokEventName: "PaywallCancelFeedbackPresented",
            eventId: makeEventId(prefix: "cancel_feedback_presented", source: source, plan: selectedPlan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackPaywallCancelFeedbackSubmitted(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        trigger: String,
        reason: String,
        reasonLabel: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: selectedPlan,
            funnelStep: "cancel_feedback_submitted"
        )
        properties["cancel_feedback_trigger"] = trigger
        properties["cancel_feedback_reason"] = reason
        properties["cancel_feedback_reason_label"] = reasonLabel
        properties["feedback_surface"] = "confirmation_dialog"
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.paywallCancelFeedbackSubmitted,
            tikTokEventName: "PaywallCancelFeedbackSubmitted",
            eventId: makeEventId(prefix: "cancel_feedback_submitted", source: source, plan: selectedPlan),
            properties: properties,
            includeRevenue: false
        )

        let reasonEvent = cancelFeedbackReasonEvent(for: reason)
        trackCustomLifecycleEvent(
            appsFlyerName: reasonEvent.appsFlyerName,
            tikTokEventName: reasonEvent.tikTokEventName,
            eventId: makeEventId(prefix: reasonEvent.eventIdPrefix, source: source, plan: selectedPlan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackPaywallCancelFeedbackDismissed(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        trigger: String,
        reason: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: selectedPlan,
            funnelStep: "cancel_feedback_dismissed"
        )
        properties["cancel_feedback_trigger"] = trigger
        properties["cancel_feedback_dismiss_reason"] = reason
        properties["feedback_surface"] = "confirmation_dialog"
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.paywallCancelFeedbackDismissed,
            tikTokEventName: "PaywallCancelFeedbackDismissed",
            eventId: makeEventId(prefix: "cancel_feedback_dismissed", source: source, plan: selectedPlan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionPurchaseFailed(
        plan: SubscriptionPlanOption,
        source: String,
        error: Error,
        reason: String? = nil,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: plan,
            funnelStep: "purchase_failed"
        )
        properties.merge(errorAnalyticsProperties(error, reason: reason)) { _, new in new }
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.purchaseFailed,
            tikTokEventName: "PurchaseFailed",
            eventId: makeEventId(prefix: "purchase_failed", source: source, plan: plan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionAccessVerified(
        plan: SubscriptionPlanOption?,
        source: String,
        context: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: plan,
            funnelStep: "access_verified"
        )
        properties["verification_context"] = context
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.accessVerified,
            tikTokEventName: "SubscriptionAccessVerified",
            eventId: makeEventId(prefix: "access_verified", source: source, plan: plan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionAccessVerificationFailed(
        plan: SubscriptionPlanOption?,
        source: String,
        context: String,
        reason: String,
        error: Error? = nil,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: plan,
            funnelStep: "access_verification_failed"
        )
        properties["verification_context"] = context
        properties["failure_reason"] = reason
        if let error {
            properties.merge(errorAnalyticsProperties(error, reason: reason)) { _, new in new }
        }
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.accessVerificationFailed,
            tikTokEventName: "SubscriptionAccessVerificationFailed",
            eventId: makeEventId(prefix: "access_verification_failed", source: source, plan: plan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionRestoreAttempted(source: String) {
        let properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "restore_attempted"
        )

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.restoreAttempted,
            tikTokEventName: "SubscriptionRestoreAttempted",
            eventId: makeEventId(prefix: "restore_attempted", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionRestoreSucceeded(source: String) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "restore_succeeded"
        )
        properties["restored"] = true

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.restoreSucceeded,
            tikTokEventName: "SubscriptionRestoreSucceeded",
            eventId: makeEventId(prefix: "restore_succeeded", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackSubscriptionRestoreFailed(source: String, reason: String, error: Error? = nil) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "restore_failed"
        )
        properties["restored"] = false
        properties["failure_reason"] = reason
        if let error {
            properties.merge(errorAnalyticsProperties(error, reason: reason)) { _, new in new }
        }

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.restoreFailed,
            tikTokEventName: "SubscriptionRestoreFailed",
            eventId: makeEventId(prefix: "restore_failed", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackPaywallDismissed(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        metadata: [String: Any] = [:]
    ) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: selectedPlan,
            funnelStep: "paywall_dismissed"
        )
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.paywallDismissed,
            tikTokEventName: "PaywallDismissed",
            eventId: makeEventId(prefix: "paywall_dismissed", source: source, plan: selectedPlan),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackExistingSubscriptionAccessViewed(source: String) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "existing_access_viewed"
        )
        properties["access_source"] = "existing_subscription"

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.existingAccessViewed,
            tikTokEventName: "ExistingSubscriptionAccessViewed",
            eventId: makeEventId(prefix: "existing_access_viewed", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackExistingSubscriptionAccessContinued(source: String) {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: "existing_access_continued"
        )
        properties["access_source"] = "existing_subscription"

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.existingAccessContinued,
            tikTokEventName: "ExistingSubscriptionAccessContinued",
            eventId: makeEventId(prefix: "existing_access_continued", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackOnboardingStarted(
        source: String,
        startingStepId: String,
        stepCount: Int,
        metadata: [String: Any] = [:]
    ) {
        var properties = baseProperties(source: source)
        properties["funnel"] = "onboarding"
        properties["funnel_step"] = "started"
        properties["starting_step_id"] = startingStepId
        properties["step_count"] = stepCount
        for (key, value) in metadata {
            properties[key] = value
        }

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.onboardingStarted,
            tikTokEventName: "MacraOnboardingStarted",
            eventId: makeEventId(prefix: "onboarding_started", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackOnboardingProfileCompleted(
        source: String,
        startingStepId: String,
        stepCount: Int,
        completionAction: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = baseProperties(source: source)
        properties["funnel"] = "onboarding"
        properties["funnel_step"] = "profile_completed"
        properties["starting_step_id"] = startingStepId
        properties["step_count"] = stepCount
        properties["completion_action"] = completionAction
        for (key, value) in metadata {
            properties[key] = value
        }

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.onboardingProfileCompleted,
            tikTokEventName: "MacraOnboardingProfileCompleted",
            eventId: makeEventId(prefix: "onboarding_profile_completed", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackOnboardingCompleted(
        source: String,
        startingStepId: String,
        stepCount: Int,
        completionAction: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = baseProperties(source: source)
        properties["funnel"] = "onboarding"
        properties["funnel_step"] = "completed"
        properties["starting_step_id"] = startingStepId
        properties["step_count"] = stepCount
        properties["completion_action"] = completionAction
        for (key, value) in metadata {
            properties[key] = value
        }

        trackCustomLifecycleEvent(
            appsFlyerName: AppsFlyerAnalyticsEvent.onboardingCompleted,
            tikTokEventName: "MacraOnboardingCompleted",
            eventId: makeEventId(prefix: "onboarding_completed", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackOnboardingStepViewed(
        stepId: String,
        stepName: String,
        stepIndex: Int,
        stepCount: Int,
        source: String,
        startingStepId: String,
        visitCount: Int,
        trigger: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = onboardingProperties(
            stepId: stepId,
            stepName: stepName,
            stepIndex: stepIndex,
            stepCount: stepCount,
            source: source,
            startingStepId: startingStepId,
            metadata: metadata
        )
        properties["visit_count"] = visitCount
        properties["trigger"] = trigger

        trackCustomLifecycleEvent(
            appsFlyerName: stepEventName(prefix: AppsFlyerAnalyticsEvent.onboardingStepViewed, stepId: stepId),
            tikTokEventName: "MacraOnboardingStepViewed",
            eventId: makeEventId(prefix: "onboarding_step_viewed_\(stepId)", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackOnboardingStepCompleted(
        stepId: String,
        stepName: String,
        stepIndex: Int,
        stepCount: Int,
        source: String,
        startingStepId: String,
        completionAction: String,
        destinationStepId: String?,
        metadata: [String: Any] = [:]
    ) {
        var properties = onboardingProperties(
            stepId: stepId,
            stepName: stepName,
            stepIndex: stepIndex,
            stepCount: stepCount,
            source: source,
            startingStepId: startingStepId,
            metadata: metadata
        )
        properties["completion_action"] = completionAction
        properties["destination_step_id"] = destinationStepId ?? "none"

        trackCustomLifecycleEvent(
            appsFlyerName: stepEventName(prefix: AppsFlyerAnalyticsEvent.onboardingStepCompleted, stepId: stepId),
            tikTokEventName: "MacraOnboardingStepCompleted",
            eventId: makeEventId(prefix: "onboarding_step_completed_\(stepId)", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackOnboardingStepBack(
        stepId: String,
        stepName: String,
        stepIndex: Int,
        stepCount: Int,
        source: String,
        startingStepId: String,
        destinationStepId: String?,
        metadata: [String: Any] = [:]
    ) {
        var properties = onboardingProperties(
            stepId: stepId,
            stepName: stepName,
            stepIndex: stepIndex,
            stepCount: stepCount,
            source: source,
            startingStepId: startingStepId,
            metadata: metadata
        )
        properties["destination_step_id"] = destinationStepId ?? "none"

        trackCustomLifecycleEvent(
            appsFlyerName: stepEventName(prefix: AppsFlyerAnalyticsEvent.onboardingStepBack, stepId: stepId),
            tikTokEventName: "MacraOnboardingStepBack",
            eventId: makeEventId(prefix: "onboarding_step_back_\(stepId)", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackOnboardingExited(
        stepId: String,
        stepName: String,
        stepIndex: Int,
        stepCount: Int,
        source: String,
        startingStepId: String,
        exitAction: String,
        metadata: [String: Any] = [:]
    ) {
        var properties = onboardingProperties(
            stepId: stepId,
            stepName: stepName,
            stepIndex: stepIndex,
            stepCount: stepCount,
            source: source,
            startingStepId: startingStepId,
            metadata: metadata
        )
        properties["exit_action"] = exitAction

        trackCustomLifecycleEvent(
            appsFlyerName: stepEventName(prefix: AppsFlyerAnalyticsEvent.onboardingExited, stepId: stepId),
            tikTokEventName: "MacraOnboardingExited",
            eventId: makeEventId(prefix: "onboarding_exited_\(stepId)", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackJournalViewed(source: String) {
        #if DEBUG
        let eventId = makeEventId(prefix: "journal_viewed", source: source, plan: nil)
        var properties = baseProperties(source: source)
        properties["content_id"] = "macra_journal"
        properties["content_type"] = "journal"

        #if canImport(TikTokBusinessSDK)
        guard tikTokReadyForTracking() else {
            print("[Macra][Analytics] TikTok \(MacraAnalyticsEventName.journalViewed.rawValue) skipped because SDK is not ready. eventId=\(eventId)")
            return
        }

        identifyCurrentUserIfAvailable()

        let event = TikTokViewContentEvent()
        event.eventId = eventId
        event.setContentId("macra_journal")
        event.setCurrency(TTCurrency(rawValue: "USD"))
        event.setDescription("Macra journal viewed")
        event.setContentType("journal")
        event.setValue("0.00")

        for (key, value) in properties {
            event.addProperty(withKey: key, value: value)
        }

        TikTokBusiness.trackTTEvent(event)
        print("[Macra][Analytics] TikTok \(MacraAnalyticsEventName.journalViewed.rawValue) tracked. eventId=\(eventId)")
        #else
        print("[Macra][Analytics] TikTok \(MacraAnalyticsEventName.journalViewed.rawValue) skipped because SDK is not linked. eventId=\(eventId)")
        #endif
        #endif
    }

    private func trackTrialStarted(
        plan: SubscriptionPlanOption,
        trialDays: Int,
        source: String,
        metadata: [String: Any]
    ) {
        var properties = baseProperties(source: source)
        properties.merge(plan.analyticsProperties) { _, new in new }
        properties["trial_days"] = trialDays
        properties[AppsFlyerAnalyticsParam.contentId] = plan.analyticsProductId
        properties[AppsFlyerAnalyticsParam.contentType] = "subscription"
        mergeAnalyticsMetadata(metadata, into: &properties)

        trackBaseEvent(
            name: .startTrial,
            eventName: "StartTrial",
            eventId: makeEventId(prefix: "start_trial", source: source, plan: plan),
            properties: properties
        )
    }

    private func trackPurchase(plan: SubscriptionPlanOption, source: String, metadata: [String: Any]) {
        let value = analyticsValue(for: plan)
        let purchaseEventId = makeEventId(prefix: "purchase", source: source, plan: plan)
        var appsFlyerProperties = baseProperties(source: source)
            .merging(plan.analyticsProperties, uniquingKeysWith: { _, new in new })
            .merging([
                AppsFlyerAnalyticsParam.contentId: plan.analyticsProductId,
                AppsFlyerAnalyticsParam.contentType: "subscription",
                AppsFlyerAnalyticsParam.description: "Macra Pro subscription"
            ], uniquingKeysWith: { _, new in new })
        mergeAnalyticsMetadata(metadata, into: &appsFlyerProperties)

        trackAppsFlyerEvent(
            name: AppsFlyerAnalyticsEvent.subscribe,
            eventId: makeEventId(prefix: "subscribe", source: source, plan: plan),
            properties: appsFlyerProperties,
            includeRevenue: true
        )

        trackAppsFlyerEvent(
            name: AppsFlyerAnalyticsEvent.purchase,
            eventId: purchaseEventId,
            properties: appsFlyerProperties,
            includeRevenue: true
        )

        #if canImport(TikTokBusinessSDK)
        guard tikTokReadyForTracking() else {
            print("[Macra][Analytics] TikTok purchase skipped because SDK is not ready. eventId=\(purchaseEventId)")
            return
        }

        identifyCurrentUserIfAvailable()

        let event = TikTokPurchaseEvent()
        event.eventId = purchaseEventId
        event.setContentId(plan.analyticsProductId)
        event.setCurrency(plan.analyticsCurrency)
        event.setDescription("Macra Pro subscription")
        event.setContentType("subscription")
        event.setValue(formatValue(value))

        let content = TikTokContentParams()
        content.price = NSNumber(value: value)
        content.quantity = 1
        content.brand = "Macra"
        content.contentId = plan.analyticsProductId
        content.contentName = plan.displayTitle
        event.setContents([content])

        for (key, value) in appsFlyerProperties {
            event.addProperty(withKey: key, value: value)
        }

        TikTokBusiness.trackTTEvent(event)
        print("[Macra][Analytics] TikTok purchase tracked. eventId=\(purchaseEventId)")
        #else
        print("[Macra][Analytics] TikTok purchase skipped because SDK is not linked. eventId=\(purchaseEventId)")
        #endif
    }

    private func trackBaseEvent(
        name: MacraAnalyticsEventName,
        eventName: String,
        eventId: String,
        properties: [String: Any]
    ) {
        trackAppsFlyerEvent(
            name: appsFlyerEventName(for: name),
            eventId: eventId,
            properties: properties,
            includeRevenue: false
        )

        #if canImport(TikTokBusinessSDK)
        guard tikTokReadyForTracking() else {
            print("[Macra][Analytics] TikTok \(name.rawValue) skipped because SDK is not ready. eventId=\(eventId)")
            return
        }

        identifyCurrentUserIfAvailable()

        let event = TikTokBaseEvent(eventName: eventName)
        event.eventId = eventId
        for (key, value) in properties {
            event.addProperty(withKey: key, value: value)
        }
        TikTokBusiness.trackTTEvent(event)
        print("[Macra][Analytics] TikTok \(name.rawValue) tracked. eventId=\(eventId)")
        #else
        print("[Macra][Analytics] TikTok \(name.rawValue) skipped because SDK is not linked. eventId=\(eventId)")
        #endif
    }

    private func trackCustomLifecycleEvent(
        appsFlyerName: String,
        tikTokEventName: String,
        eventId: String,
        properties: [String: Any],
        includeRevenue: Bool
    ) {
        trackAppsFlyerEvent(
            name: appsFlyerName,
            eventId: eventId,
            properties: properties,
            includeRevenue: includeRevenue
        )

        #if canImport(TikTokBusinessSDK)
        guard tikTokReadyForTracking() else {
            print("[Macra][Analytics] TikTok \(tikTokEventName) skipped because SDK is not ready. eventId=\(eventId)")
            return
        }

        identifyCurrentUserIfAvailable()

        let event = TikTokBaseEvent(eventName: tikTokEventName)
        event.eventId = eventId
        for (key, value) in properties {
            event.addProperty(withKey: key, value: value)
        }
        TikTokBusiness.trackTTEvent(event)
        print("[Macra][Analytics] TikTok \(tikTokEventName) tracked. eventId=\(eventId)")
        #else
        print("[Macra][Analytics] TikTok \(tikTokEventName) skipped because SDK is not linked. eventId=\(eventId)")
        #endif
    }

    private func appsFlyerEventName(for name: MacraAnalyticsEventName) -> String {
        switch name {
        case .paywallViewed, .journalViewed:
            return AppsFlyerAnalyticsEvent.contentView
        case .startTrial:
            return AppsFlyerAnalyticsEvent.startTrial
        case .purchase:
            return AppsFlyerAnalyticsEvent.purchase
        }
    }

    private func trackAppsFlyerEvent(
        name: String,
        eventId: String,
        properties: [String: Any],
        includeRevenue: Bool
    ) {
        trackFirebaseEvent(
            name: name,
            eventId: eventId,
            properties: properties,
            includeRevenue: includeRevenue
        )

        #if canImport(AppsFlyerLib)
        identifyAppsFlyerUserIfAvailable()

        var values = appsFlyerValues(from: properties, includeRevenue: includeRevenue)
        values["macra_event_id"] = eventId
        AppsFlyerLib.shared().logEvent(name, withValues: values)
        print("[Macra][Analytics] AppsFlyer \(name) tracked. eventId=\(eventId)")
        #else
        print("[Macra][Analytics] AppsFlyer \(name) skipped because SDK is not linked. eventId=\(eventId)")
        #endif
    }

    private func trackFirebaseEvent(
        name: String,
        eventId: String,
        properties: [String: Any],
        includeRevenue: Bool
    ) {
        #if canImport(FirebaseAnalytics)
        guard FirebaseApp.app() != nil else {
            print("[Macra][Analytics] Firebase \(name) skipped because Firebase is not configured. eventId=\(eventId)")
            return
        }

        var parameters = firebaseAnalyticsParameters(
            from: properties,
            maxCount: includeRevenue ? 22 : 24
        )
        parameters["macra_event_id"] = eventId

        if includeRevenue {
            if let value = properties["value"] ?? properties["selected_plan_price"] {
                parameters["value"] = firebaseAnalyticsValue(value)
            }
            parameters["currency"] = (properties["currency"] as? String) ?? "USD"
        }

        Analytics.logEvent(firebaseAnalyticsEventName(name), parameters: parameters)
        print("[Macra][Analytics] Firebase \(name) tracked. eventId=\(eventId)")
        #else
        print("[Macra][Analytics] Firebase \(name) skipped because SDK is not linked. eventId=\(eventId)")
        #endif
    }

    private func appsFlyerValues(from properties: [String: Any], includeRevenue: Bool) -> [String: Any] {
        var values = properties

        values[AppsFlyerAnalyticsParam.currency] = (properties["currency"] as? String) ?? "USD"

        if let contentId = properties["content_id"] {
            values[AppsFlyerAnalyticsParam.contentId] = contentId
        }
        if let contentType = properties["content_type"] {
            values[AppsFlyerAnalyticsParam.contentType] = contentType
        }
        if let value = properties["value"] ?? properties["selected_plan_price"] {
            values[AppsFlyerAnalyticsParam.price] = value
            if includeRevenue {
                values[AppsFlyerAnalyticsParam.revenue] = value
            }
        }

        if !includeRevenue {
            values.removeValue(forKey: AppsFlyerAnalyticsParam.revenue)
        }

        return values
    }

    private func firebaseAnalyticsParameters(from properties: [String: Any], maxCount: Int) -> [String: Any] {
        var parameters: [String: Any] = [:]
        let priorityKeys = [
            "funnel",
            "funnel_step",
            "source",
            "plan_id",
            "plan_period",
            "selected_plan_period",
            "selected_plan_id",
            "macra_paywall_default_plan",
            "macra_paywall_layout_variant",
            "paywall_variant",
            "paywall_layout_variant",
            "paywall_default_selection",
            "paywall_layout_selection",
            "paywall_default_reason",
            "paywall_ab_parameter",
            "paywall_layout_ab_parameter",
            "uses_web_checkout_fallback",
            "has_trial_confidence_card",
            "available_plan_count",
            "available_package_count",
            "supported_package_count",
            "error_code",
            "error_domain",
            "readable_error_code",
            "cancel_reason",
            "purchase_status",
            "app_version",
            "build_number",
            "build_configuration"
        ]

        for key in priorityKeys where parameters.count < maxCount {
            guard let value = properties[key] else { continue }
            parameters[firebaseAnalyticsParameterName(key)] = firebaseAnalyticsValue(value)
        }

        for key in properties.keys.sorted() where parameters.count < maxCount {
            guard !priorityKeys.contains(key), let value = properties[key] else { continue }
            parameters[firebaseAnalyticsParameterName(key)] = firebaseAnalyticsValue(value)
        }

        return parameters
    }

    private func firebaseAnalyticsEventName(_ name: String) -> String {
        let sanitized = sanitizedFirebaseIdentifier(name)
        let prefixed = sanitized.first?.isLetter == true ? sanitized : "macra_\(sanitized)"
        return String(prefixed.prefix(40))
    }

    private func firebaseAnalyticsParameterName(_ name: String) -> String {
        let sanitized = sanitizedFirebaseIdentifier(name)
        let prefixed = sanitized.first?.isLetter == true ? sanitized : "macra_\(sanitized)"
        return String(prefixed.prefix(40))
    }

    private func sanitizedFirebaseIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let joined = String(scalars)
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return joined.isEmpty ? "macra_event" : joined
    }

    private func firebaseAnalyticsValue(_ value: Any) -> Any {
        if let value = value as? NSString {
            return truncated(value as String, maxLength: 100)
        }
        if let value = value as? String {
            return truncated(value, maxLength: 100)
        }
        if let value = value as? Bool {
            return NSNumber(value: value)
        }
        if let value = value as? NSNumber {
            return value
        }
        if let value = value as? Int {
            return NSNumber(value: value)
        }
        if let value = value as? Double {
            return NSNumber(value: value)
        }
        if let value = value as? Float {
            return NSNumber(value: value)
        }
        if let value = value as? URL {
            return truncated(value.absoluteString, maxLength: 100)
        }

        return truncated(String(describing: value), maxLength: 100)
    }

    private func identifyAppsFlyerUserIfAvailable() {
        #if canImport(AppsFlyerLib)
        if FirebaseApp.app() != nil,
           let user = UserService.sharedInstance.user {
            AppsFlyerLib.shared().customerUserID = user.id
        }
        #endif
    }

    private func tikTokReadyForTracking() -> Bool {
        #if canImport(TikTokBusinessSDK)
        configureTikTokSDK()
        return TikTokBusiness.isInitialized()
        #else
        return false
        #endif
    }

    private func baseProperties(source: String) -> [String: Any] {
        var properties: [String: Any] = [
            "app": appName,
            "platform": platform,
            "source": source,
            "app_version": appVersion,
            "build_number": buildNumber,
            "build_configuration": buildConfiguration
        ]

        if FirebaseApp.app() != nil,
           let user = UserService.sharedInstance.user {
            properties["external_id"] = user.id
            properties["user_entry_point"] = user.registrationEntryPoint?.rawValue ?? "unknown"
            properties["subscription_type"] = user.subscriptionType.rawValue
        }

        return properties
    }

    private func mergeAnalyticsMetadata(_ metadata: [String: Any], into properties: inout [String: Any]) {
        for (key, value) in metadata {
            properties[key] = value
        }
    }

    private var buildConfiguration: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    private func subscriptionLifecycleProperties(
        source: String,
        plan: SubscriptionPlanOption?,
        funnelStep: String
    ) -> [String: Any] {
        var properties = baseProperties(source: source)
        properties["funnel"] = "subscription"
        properties["funnel_step"] = funnelStep
        properties["content_type"] = "subscription"

        if let plan {
            properties.merge(plan.analyticsProperties) { _, new in new }
            properties[AppsFlyerAnalyticsParam.contentId] = plan.analyticsProductId
            properties[AppsFlyerAnalyticsParam.contentType] = "subscription"
        } else {
            properties["plan_id"] = "none"
            properties["plan_period"] = "none"
            properties[AppsFlyerAnalyticsParam.contentType] = "subscription"
        }

        return properties
    }

    private func webCheckoutFallbackProperties(
        source: String,
        reason: String,
        funnelStep: String,
        ctaTitle: String,
        availablePlanCount: Int,
        isLoadingPackages: Bool,
        packageLoadError: String?,
        metadata: [String: Any]
    ) -> [String: Any] {
        var properties = subscriptionLifecycleProperties(
            source: source,
            plan: nil,
            funnelStep: funnelStep
        )
        properties["fallback_reason"] = reason
        properties["checkout_provider"] = "stripe"
        properties["checkout_plan_period"] = "annual"
        properties["checkout_surface"] = "safari_view_controller"
        properties["checkout_entry_point"] = "paywall_primary_cta"
        properties["content_id"] = "stripe_web_checkout"
        properties["cta_title"] = ctaTitle
        properties["available_plan_count"] = availablePlanCount
        properties["selected_plan_available"] = false
        properties["is_loading_packages"] = isLoadingPackages

        if let packageLoadError {
            properties["package_load_error"] = truncated(packageLoadError)
        }
        mergeAnalyticsMetadata(metadata, into: &properties)

        return properties
    }

    private func onboardingProperties(
        stepId: String,
        stepName: String,
        stepIndex: Int,
        stepCount: Int,
        source: String,
        startingStepId: String,
        metadata: [String: Any]
    ) -> [String: Any] {
        var properties = baseProperties(source: source)
        properties["funnel"] = "onboarding"
        properties["step_id"] = stepId
        properties["step_name"] = stepName
        properties["step_index"] = stepIndex
        properties["step_position"] = stepIndex + 1
        properties["step_count"] = stepCount
        properties["starting_step_id"] = startingStepId
        properties["is_starting_step"] = stepId == startingStepId

        for (key, value) in metadata {
            properties[key] = value
        }

        return properties
    }

    private func errorAnalyticsProperties(_ error: Error, reason: String?) -> [String: Any] {
        let nsError = error as NSError
        var properties: [String: Any] = [
            "error_domain": nsError.domain,
            "error_code": nsError.code,
            "error_description": truncated(nsError.localizedDescription)
        ]

        if let reason {
            properties["failure_reason"] = reason
        }

        if let readableCode = nsError.userInfo["readable_error_code"] as? String {
            properties["readable_error_code"] = readableCode
        }

        return properties
    }

    private func truncated(_ value: String, maxLength: Int = 180) -> String {
        guard value.count > maxLength else { return value }
        return String(value.prefix(maxLength))
    }

    private func makeEventId(prefix: String, source: String, plan: SubscriptionPlanOption?) -> String {
        let userId = FirebaseApp.app() != nil ? UserService.sharedInstance.user?.id : nil
        let subject = userId ?? "anonymous"
        let product = plan?.analyticsProductId ?? "none"
        return "macra_\(prefix)_\(source)_\(subject)_\(product)_\(UUID().uuidString)"
    }

    private func stepEventName(prefix: String, stepId: String) -> String {
        let safeStepId = stepId
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber || character == "_" ? character : "_"
            }
        return "\(prefix)_\(String(safeStepId))"
    }

    private func cancelFeedbackReasonEvent(for reason: String) -> (
        appsFlyerName: String,
        tikTokEventName: String,
        eventIdPrefix: String
    ) {
        switch reason {
        case "price_too_high":
            return (
                AppsFlyerAnalyticsEvent.paywallCancelReasonPriceTooHigh,
                "PaywallCancelReasonPriceTooHigh",
                "cancel_reason_price_too_high"
            )
        case "not_ready":
            return (
                AppsFlyerAnalyticsEvent.paywallCancelReasonNotReady,
                "PaywallCancelReasonNotReady",
                "cancel_reason_not_ready"
            )
        case "need_more_proof":
            return (
                AppsFlyerAnalyticsEvent.paywallCancelReasonNeedMoreProof,
                "PaywallCancelReasonNeedMoreProof",
                "cancel_reason_need_more_proof"
            )
        case "apple_sheet_confusing":
            return (
                AppsFlyerAnalyticsEvent.paywallCancelReasonAppleSheetConfusing,
                "PaywallCancelReasonAppleSheetConfusing",
                "cancel_reason_apple_sheet_confusing"
            )
        case "wrong_plan":
            return (
                AppsFlyerAnalyticsEvent.paywallCancelReasonWrongPlan,
                "PaywallCancelReasonWrongPlan",
                "cancel_reason_wrong_plan"
            )
        case "something_did_not_work":
            return (
                AppsFlyerAnalyticsEvent.paywallCancelReasonSomethingDidNotWork,
                "PaywallCancelReasonSomethingDidNotWork",
                "cancel_reason_something_did_not_work"
            )
        default:
            return (
                AppsFlyerAnalyticsEvent.paywallCancelReasonUnknown,
                "PaywallCancelReasonUnknown",
                "cancel_reason_unknown"
            )
        }
    }

    private func analyticsValue(for plan: SubscriptionPlanOption) -> Double {
        NSDecimalNumber(decimal: plan.price).doubleValue
    }

    private func formatValue(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }

    private func infoBool(_ key: String) -> Bool {
        switch Bundle.main.object(forInfoDictionaryKey: key) {
        case let value as Bool:
            return value
        case let value as String:
            return ["1", "true", "yes"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        default:
            return false
        }
    }

    private func logMissingTikTokConfigIfNeeded() {
        guard !didLogMissingTikTokConfig else { return }
        didLogMissingTikTokConfig = true
        print("[Macra][Analytics] Missing TikTokDeveloperAppID, TikTokAppID, or TikTokAccessToken in Info.plist.")
    }
}

private extension SubscriptionPlanOption {
    var analyticsProductId: String {
        switch self {
        case .revenueCat(let package):
            return package.package.storeProduct.productIdentifier
        case .local(let plan):
            return plan.id
        }
    }

    var analyticsPeriod: String {
        switch periodKind {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        case .unknown: return "unknown"
        }
    }

    var analyticsCurrencyCode: String {
        switch self {
        case .revenueCat(let package):
            return package.package.storeProduct.currencyCode ?? "USD"
        case .local:
            return "USD"
        }
    }

    #if canImport(TikTokBusinessSDK)
    var analyticsCurrency: TTCurrency {
        TTCurrency(rawValue: analyticsCurrencyCode.uppercased())
    }
    #endif

    var analyticsProperties: [String: Any] {
        [
            "plan_id": analyticsProductId,
            "plan_title": displayTitle,
            "plan_period": analyticsPeriod,
            "value": NSDecimalNumber(decimal: price).doubleValue,
            "currency": analyticsCurrencyCode,
            "has_trial": trialDays != nil,
            "trial_days": trialDays ?? 0
        ]
    }
}
