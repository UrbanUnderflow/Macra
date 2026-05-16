import SwiftUI

class PayWallViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator

    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }
}

struct PayWallView: View {
    @ObservedObject private var offeringViewModel = PurchaseService.sharedInstance.offering
    @ObservedObject var viewModel: PayWallViewModel
    @State private var didTrackPaywallView = false
    @State private var didTrackExistingAccessView = false
    @State private var standaloneSelectedPlanID: String?
    @State private var standalonePurchaseError: String?
    @State private var isStandalonePurchasing = false
    private let isDemoMode: Bool
    private let usesLivePurchasesInDemo: Bool
    private let onboardingCoordinator: MacraOnboardingCoordinator?
    private let onDismiss: (() -> Void)?
    private let existingSubscriptionAccessOverride: Bool?

    init(
        viewModel: PayWallViewModel,
        isDemoMode: Bool = false,
        usesLivePurchasesInDemo: Bool = false,
        onboardingCoordinator: MacraOnboardingCoordinator? = nil,
        onDismiss: (() -> Void)? = nil,
        existingSubscriptionAccessOverride: Bool? = nil
    ) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self.isDemoMode = isDemoMode
        self.usesLivePurchasesInDemo = usesLivePurchasesInDemo
        self.onboardingCoordinator = onboardingCoordinator
        self.onDismiss = onDismiss
        self.existingSubscriptionAccessOverride = existingSubscriptionAccessOverride
    }

    private var shouldUseDemoPlans: Bool {
        isDemoMode && !usesLivePurchasesInDemo
    }

    private var shouldTrackPaywallAnalytics: Bool {
        !isDemoMode
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
        Self.paywallPlans(from: availablePlans)
    }

    private var selectedPlan: SubscriptionPlanOption? {
        if let coordinator = onboardingCoordinator {
            if let current = coordinator.selectedPlan,
               displayedPlans.contains(where: { $0.id == current.id }) {
                return current
            }
            return displayedPlans.first ?? coordinator.selectedPlan
        }

        if let id = standaloneSelectedPlanID,
           let match = displayedPlans.first(where: { $0.id == id }) {
            return match
        }
        return displayedPlans.first
    }

    private var isPurchasing: Bool {
        onboardingCoordinator?.isPurchasing ?? isStandalonePurchasing
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

    var body: some View {
        ZStack {
            MacraChromaticBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        heroSection

                        revealOrPersonalizedSection

                        if hasExistingSubscriptionAccess {
                            existingAccessCard
                        } else {
                            outcomeProofCard

                            foodFreedomCard

                            eatingOutCard

                            noraDecisionCard

                            socialLearningCard

                            unlockHighlightsCard

                            tierPickerSection

                            priceDisclosureCard
                        }

                        if let purchaseError, !purchaseError.isEmpty {
                            Text(purchaseError)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "FF8A80"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }

                bottomCTASection
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await loadPlansAndTrackPaywallView()
        }
        .onAppear {
            if let coordinator = onboardingCoordinator {
                if !coordinator.isDemoMode {
                    coordinator.loadPlanMacros()
                }
                coordinator.ensureOfferingsLoaded()
            }
            ensureVisiblePlanSelected()
        }
        .onChange(of: availablePlans.map(\.id).joined(separator: ",")) { _ in
            ensureVisiblePlanSelected()
            guard shouldTrackPaywallAnalytics else { return }
            trackPaywallViewedIfReady()
        }
        .onChange(of: existingSubscriptionAccessOverride) { _ in
            Task { await loadPlansAndTrackPaywallView() }
        }
    }

    // MARK: - Top bar

    @ViewBuilder
    private var topBar: some View {
        if let coordinator = onboardingCoordinator {
            PaywallTopBar(
                canGoBack: coordinator.canGoBack,
                onBack: coordinator.back
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
        return "MACRA PLUS"
    }

    private var headerTitle: String {
        if hasExistingSubscriptionAccess { return "Your Macra plan is ready." }
        if isRenewalFlow { return "Renew Macra Pro." }
        return "Build the body you want without giving up the food you love."
    }

    private var headerSubtitle: String {
        if hasExistingSubscriptionAccess {
            return "Your subscription already unlocks Macra. Continue when you're ready to start using this plan."
        }
        return "Macra turns your calories, meals out, labels, and Nora's AI insights into a plan you can actually live with."
    }

    // MARK: - Personalized plan (when available) + Reveal teaser (always)

    @ViewBuilder
    private var revealOrPersonalizedSection: some View {
        if showsPersonalizedPlan, let macros = onboardingCoordinator?.planMacros {
            planSummaryCard(macros: macros)
        }
        if !hasExistingSubscriptionAccess {
            PayWallRevealMoment()
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

    // MARK: - Conversion proof

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
                planStatusCard(message: packageLoadError ?? "No subscription plans are available right now.")
            } else {
                ForEach(Array(displayedPlans.enumerated()), id: \.element.id) { index, plan in
                    TierCard(
                        title: plan.displayTitle,
                        perPeriodPrice: plan.perPeriodDisplay,
                        billingNote: plan.billingNote,
                        badge: tierSavingsBadge(for: plan),
                        emphasized: index == 0,
                        isSelected: selectedPlan?.id == plan.id,
                        onTap: { selectPlan(plan, userInitiated: true) }
                    )
                }
            }
        }
    }

    private func planStatusCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if let coordinator = onboardingCoordinator {
                    coordinator.ensureOfferingsLoaded(force: true)
                } else {
                    Task { await offeringViewModel.start() }
                }
            } label: {
                Text("Retry loading plans")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.primaryGreen)
            }
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
                source: paywallAnalyticsSource
            )
        }
    }

    private func ensureVisiblePlanSelected() {
        guard let firstVisiblePlan = displayedPlans.first else { return }

        if let coordinator = onboardingCoordinator {
            if let current = coordinator.selectedPlan,
               displayedPlans.contains(where: { $0.id == current.id }) {
                return
            }
            coordinator.selectPlan(firstVisiblePlan)
            return
        }

        if let id = standaloneSelectedPlanID,
           displayedPlans.contains(where: { $0.id == id }) {
            return
        }
        standaloneSelectedPlanID = firstVisiblePlan.id
    }

    // MARK: - Price disclosure

    private var priceDisclosureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(priceDisclosureText)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            if let trialDays = selectedTrialDays {
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
        if let trialDays = selectedTrialDays {
            return "Your \(trialLengthText(for: trialDays)) trial is free. After the trial, your selected plan auto-renews until canceled. Cancel anytime in Settings > [your name] > Subscriptions."
        }

        return "Auto-renews at the price shown until canceled. Cancel anytime in Settings > [your name] > Subscriptions."
    }

    // MARK: - Bottom CTA + footer

    private var bottomCTASection: some View {
        VStack(spacing: 14) {
            MacraPrimaryButton(
                title: isPurchasing ? "Processing..." : ctaTitle,
                accent: Color.primaryGreen,
                isLoading: isPurchasing,
                action: hasExistingSubscriptionAccess ? triggerExistingAccessContinue : triggerPurchase
            )
            .disabled(isPurchasing || (!hasExistingSubscriptionAccess && ((availablePlans.isEmpty && isLoadingPackages) || selectedPlan == nil)))

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

    private var ctaTitle: String {
        if hasExistingSubscriptionAccess { return "Continue to Macra" }
        if let trialDays = selectedTrialDays { return "Try \(trialLengthText(for: trialDays)) free" }
        if isRenewalFlow { return "Renew Macra Pro" }
        guard let plan = selectedPlan else { return "Continue" }
        switch plan.periodKind {
        case .year: return "Unlock my yearly plan"
        case .month: return "Unlock my monthly plan"
        default: return "Unlock my plan"
        }
    }

    private var ctaSupportingText: String? {
        guard !hasExistingSubscriptionAccess, let plan = selectedPlan else { return nil }
        if let trialDays = selectedTrialDays {
            return "Free for \(trialLengthText(for: trialDays)), then \(plan.priceLabel). Cancel anytime."
        }

        return "\(plan.priceLabel). Cancel anytime in Apple Subscriptions."
    }

    private func trialLengthText(for days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }

    // MARK: - Actions

    private func triggerPurchase() {
        if hasExistingSubscriptionAccess {
            triggerExistingAccessContinue()
            return
        }

        if let coordinator = onboardingCoordinator {
            coordinator.purchaseAndContinue()
            return
        }
        guard let plan = selectedPlan else { return }
        purchaseStandalone(plan)
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
        if shouldTrackPaywallAnalytics {
            MacraAnalyticsService.shared.trackSubscriptionPurchaseAttempted(
                plan: plan,
                source: paywallAnalyticsSource
            )
        }

        offeringViewModel.purchase(plan) { result in
            isStandalonePurchasing = false
            switch result {
            case .success:
                if shouldTrackPaywallAnalytics {
                    MacraAnalyticsService.shared.trackSubscriptionStart(plan: plan, source: paywallAnalyticsSource)
                }
                finishStandalonePaywall()
            case .failure(let error):
                if PurchaseService.sharedInstance.isPurchaseCanceledError(error) {
                    if shouldTrackPaywallAnalytics {
                        MacraAnalyticsService.shared.trackSubscriptionPurchaseCancelled(
                            plan: plan,
                            source: paywallAnalyticsSource
                        )
                    }
                    standalonePurchaseError = nil
                } else {
                    if shouldTrackPaywallAnalytics {
                        MacraAnalyticsService.shared.trackSubscriptionPurchaseFailed(
                            plan: plan,
                            source: paywallAnalyticsSource,
                            error: error
                        )
                    }
                    standalonePurchaseError = (error as NSError).localizedDescription
                    print("There was an error while purchasing \(error)")
                }
            }
        }
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
                        finishStandalonePaywall()
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
        if let onDismiss {
            onDismiss()
        } else {
            viewModel.appCoordinator.closeModals()
        }
    }

    // MARK: - Tracking / loading

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
            await offeringViewModel.start()
        }

        trackPaywallViewedIfReady()
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
            availablePlans: availablePlans
        )
    }

    @MainActor
    private func trackExistingAccessViewIfReady() {
        guard shouldTrackPaywallAnalytics, !didTrackExistingAccessView else { return }
        didTrackExistingAccessView = true
        MacraAnalyticsService.shared.trackExistingSubscriptionAccessViewed(source: paywallAnalyticsSource)
    }

    // MARK: - Plan list helpers

    private static func paywallPlans(from plans: [SubscriptionPlanOption]) -> [SubscriptionPlanOption] {
        let annual = plans.first(where: { $0.periodKind == .year })
        let monthly = plans.first(where: { $0.periodKind == .month })
        let primaryPlans = [annual, monthly].compactMap { $0 }

        if !primaryPlans.isEmpty {
            return primaryPlans
        }

        return plans
            .filter { [.year, .month].contains($0.periodKind) }
            .sorted { $0.periodKind.rawValue < $1.periodKind.rawValue }
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
                trialDays: 3,
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
            Task { await offering.start() }
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
