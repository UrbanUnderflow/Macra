import Foundation
import FirebaseCore

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
    static let startTrial = "af_start_trial"
    static let subscribe = "af_subscribe"
    static let purchase = "af_purchase"
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

    func trackRegistrationCompleted(source: String) {
        guard !trackedRegistrationSources.contains(source) else { return }
        trackedRegistrationSources.insert(source)

        var properties = baseProperties(source: source)
        properties[AppsFlyerAnalyticsParam.registrationMethod] = "macra_onboarding"

        trackAppsFlyerEvent(
            name: AppsFlyerAnalyticsEvent.completeRegistration,
            eventId: makeEventId(prefix: "complete_registration", source: source, plan: nil),
            properties: properties,
            includeRevenue: false
        )
    }

    func trackPaywallViewed(
        source: String,
        selectedPlan: SubscriptionPlanOption?,
        availablePlans: [SubscriptionPlanOption]
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

        if source == "onboarding" {
            trackRegistrationCompleted(source: source)
        }

        var appsFlyerProperties = properties
        appsFlyerProperties[AppsFlyerAnalyticsParam.contentType] = "subscription_paywall"
        appsFlyerProperties[AppsFlyerAnalyticsParam.contentId] = selectedPlan?.analyticsProductId ?? "macra_subscription_paywall"
        appsFlyerProperties[AppsFlyerAnalyticsParam.description] = "Macra Pro paywall"
        trackAppsFlyerEvent(
            name: AppsFlyerAnalyticsEvent.contentView,
            eventId: eventId,
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

    func trackSubscriptionStart(plan: SubscriptionPlanOption, source: String) {
        if let trialDays = plan.trialDays, trialDays > 0 {
            trackTrialStarted(plan: plan, trialDays: trialDays, source: source)
        } else {
            trackPurchase(plan: plan, source: source)
        }
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

    private func trackTrialStarted(plan: SubscriptionPlanOption, trialDays: Int, source: String) {
        var properties = baseProperties(source: source)
        properties.merge(plan.analyticsProperties) { _, new in new }
        properties["trial_days"] = trialDays
        properties[AppsFlyerAnalyticsParam.contentId] = plan.analyticsProductId
        properties[AppsFlyerAnalyticsParam.contentType] = "subscription"

        trackBaseEvent(
            name: .startTrial,
            eventName: "StartTrial",
            eventId: makeEventId(prefix: "start_trial", source: source, plan: plan),
            properties: properties
        )
    }

    private func trackPurchase(plan: SubscriptionPlanOption, source: String) {
        let value = analyticsValue(for: plan)
        let purchaseEventId = makeEventId(prefix: "purchase", source: source, plan: plan)
        let appsFlyerProperties = baseProperties(source: source)
            .merging(plan.analyticsProperties, uniquingKeysWith: { _, new in new })
            .merging([
                AppsFlyerAnalyticsParam.contentId: plan.analyticsProductId,
                AppsFlyerAnalyticsParam.contentType: "subscription",
                AppsFlyerAnalyticsParam.description: "Macra Pro subscription"
            ], uniquingKeysWith: { _, new in new })

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

        for (key, value) in baseProperties(source: source).merging(plan.analyticsProperties, uniquingKeysWith: { _, new in new }) {
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
            "build_number": buildNumber
        ]

        if FirebaseApp.app() != nil,
           let user = UserService.sharedInstance.user {
            properties["external_id"] = user.id
            properties["user_entry_point"] = user.registrationEntryPoint?.rawValue ?? "unknown"
            properties["subscription_type"] = user.subscriptionType.rawValue
        }

        return properties
    }

    private func makeEventId(prefix: String, source: String, plan: SubscriptionPlanOption?) -> String {
        let userId = FirebaseApp.app() != nil ? UserService.sharedInstance.user?.id : nil
        let subject = userId ?? "anonymous"
        let product = plan?.analyticsProductId ?? "none"
        return "macra_\(prefix)_\(source)_\(subject)_\(product)_\(UUID().uuidString)"
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
