#if DEBUG
import SwiftUI

struct MacraScreenDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appCoordinator: AppCoordinator
    @State private var activeDemo: MacraDemoScreen?
    @State private var paywallDemoAudience: MacraPaywallDemoAudience = .nonSubscriber

    init(appCoordinator: AppCoordinator) {
        self._appCoordinator = ObservedObject(wrappedValue: appCoordinator)
    }

    var body: some View {
        ZStack {
            LinearGradient.macraGreen
                .ignoresSafeArea()

            Color.black.opacity(0.1)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    screenSection(
                        title: "Core Screens",
                        subtitle: "Use the Experiments assignment to see the treatment your device is actually receiving.",
                        entries: coreDemoEntries
                    )

                    abTestPreviewSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 54)
                .padding(.bottom, 40)
            }
        }
        .fullScreenCover(item: $activeDemo) { demo in
            switch demo {
            case .login:
                LoginView(
                    viewModel: LoginViewModel(
                        appCoordinator: appCoordinator,
                        isSignUp: false
                    )
                )
                .overlay(alignment: .topTrailing) {
                    MacraScreenDemoDismissButton {
                        activeDemo = nil
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                }
            case .onboarding, .onboardingControl, .onboardingTrialPrepCompact, .onboardingNoraGuided, .onboardingHardPaywallValue:
                MacraOnboardingFlowView(
                    appCoordinator: appCoordinator,
                    isDemoMode: true,
                    usesLivePurchasesInDemo: true,
                    onDemoDismiss: { activeDemo = nil },
                    existingSubscriptionAccessOverride: paywallDemoAudience.hasExistingSubscriptionAccess,
                    paywallDefaultPlanSelectionOverride: demo.paywallDefaultPlanSelectionOverride,
                    paywallLayoutVariantOverride: demo.paywallLayoutVariantOverride,
                    onboardingExperienceVariantOverride: demo.onboardingExperienceVariantOverride
                )
                .environment(\.isMacraDemoMode, true)
                .overlay(alignment: .topTrailing) {
                    screenDemoDismissControl
                }
            case .paywall, .paywallAnnualDefault, .paywallMonthlyVariant, .paywallTrialPrepCompact, .paywallHardPaywallValue, .paywallCancelFeedback:
                PayWallView(
                    viewModel: PayWallViewModel(appCoordinator: appCoordinator),
                    isDemoMode: true,
                    usesLivePurchasesInDemo: true,
                    onDismiss: { activeDemo = nil },
                    existingSubscriptionAccessOverride: paywallDemoAudience.hasExistingSubscriptionAccess,
                    defaultPlanSelectionOverride: demo.paywallDefaultPlanSelectionOverride,
                    layoutVariantOverride: demo.paywallLayoutVariantOverride,
                    presentsCancelFeedbackOnAppear: demo.presentsCancelFeedbackOnAppear,
                    persistsCancelFeedbackInDemo: demo.persistsCancelFeedbackInDemo
                )
                .overlay(alignment: .topTrailing) {
                    screenDemoPaywallControls
                }
            }
        }
    }

    private var screenDemoPaywallControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            MacraScreenDemoDismissButton {
                activeDemo = nil
            }

            MacraPaywallDemoAudienceToggle(selection: $paywallDemoAudience)
        }
        .padding(.top, 52)
        .padding(.trailing, 14)
    }

    private var screenDemoDismissControl: some View {
        MacraScreenDemoDismissButton {
            activeDemo = nil
        }
        .padding(.top, 52)
        .padding(.trailing, 14)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Screen Demo")
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.black)

                Text("Preview production UI. Login shows the live auth surface, onboarding uses safe mock profile data, and paywall surfaces use live RevenueCat/StoreKit products for sandbox purchase testing.")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.black.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black.opacity(0.72))
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.82))
                    .clipShape(Circle())
            }
            .accessibilityIdentifier("macra-screen-demo-close-button")
        }
    }

    private var coreDemoEntries: [MacraScreenDemoEntry] {
        [
            MacraScreenDemoEntry(demo: .login),
            MacraScreenDemoEntry(demo: .onboarding),
            MacraScreenDemoEntry(demo: .onboardingControl),
            MacraScreenDemoEntry(demo: .onboardingTrialPrepCompact),
            MacraScreenDemoEntry(demo: .onboardingNoraGuided),
            MacraScreenDemoEntry(demo: .onboardingHardPaywallValue),
            MacraScreenDemoEntry(demo: .paywall),
            MacraScreenDemoEntry(demo: .paywallHardPaywallValue),
            MacraScreenDemoEntry(demo: .paywallCancelFeedback)
        ]
    }

    private var abTestPreviewGroups: [MacraABTestPreviewGroup] {
        [
            MacraABTestPreviewGroup(
                id: "default-plan",
                title: "Default Plan Selection",
                parameter: MacraPaywallExperimentService.defaultPlanParameterKey,
                summary: "Checks whether annual-first or monthly-first reduces sticker shock and improves purchase intent.",
                entries: [
                    MacraScreenDemoEntry(
                        demo: .paywallAnnualDefault,
                        title: "Baseline - Annual First",
                        subtitle: "Value: annual. The yearly plan is selected when the paywall opens.",
                        systemImage: "calendar.badge.clock",
                        badge: "Base",
                        idSuffix: "default-plan-baseline"
                    ),
                    MacraScreenDemoEntry(
                        demo: .paywallMonthlyVariant,
                        title: "Variant A - Monthly First",
                        subtitle: "Value: monthly. The monthly plan is selected when the paywall opens.",
                        systemImage: "calendar",
                        badge: "A",
                        idSuffix: "default-plan-variant-a"
                    )
                ]
            ),
            MacraABTestPreviewGroup(
                id: "trial-confidence",
                title: "Paywall Layout",
                parameter: MacraPaywallExperimentService.layoutVariantParameterKey,
                summary: "Checks whether Apple-sheet prep, trial education, and a compact plan-first paywall improve purchase confirmation.",
                entries: [
                    MacraScreenDemoEntry(
                        demo: .onboardingControl,
                        title: "Baseline - Full Onboarding",
                        subtitle: "Value: trial_confidence_control. Walks the full onboarding flow into the current long paywall.",
                        systemImage: "rectangle.stack.fill",
                        badge: "Base",
                        idSuffix: "trial-confidence-baseline"
                    ),
                    MacraScreenDemoEntry(
                        demo: .onboardingTrialPrepCompact,
                        title: "Variant A - Full Onboarding Compact",
                        subtitle: "Value: trial_confidence. Walks the full onboarding flow into two prep screens and the condensed plan page.",
                        systemImage: "rectangle.stack.fill",
                        badge: "A",
                        idSuffix: "trial-confidence-variant-a"
                    ),
                    MacraScreenDemoEntry(
                        demo: .onboardingNoraGuided,
                        title: "Variant B - Nora Guided Onboarding",
                        subtitle: "Value: nora_guided. Adds the intent question, Nora prompt bubbles, and the compact trial prep paywall.",
                        systemImage: "sparkles",
                        badge: "B",
                        idSuffix: "trial-confidence-variant-b"
                    ),
                    MacraScreenDemoEntry(
                        demo: .onboardingHardPaywallValue,
                        title: "Variant C - Hard Paywall Value",
                        subtitle: "Value: hard_paywall_value. Monthly-first value flow that pushes the built plan, scanner, and Nora before Apple confirmation.",
                        systemImage: "creditcard.fill",
                        badge: "C",
                        idSuffix: "hard-paywall-value-variant-c"
                    )
                ]
            )
        ]
    }

    private func screenSection(
        title: String,
        subtitle: String,
        entries: [MacraScreenDemoEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.heavy))
                    .foregroundColor(.black)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.black.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                ForEach(entries) { entry in
                    screenDemoButton(for: entry)
                }
            }
        }
    }

    private var abTestPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Experiments")
                    .font(.headline.weight(.heavy))
                    .foregroundColor(.black)

                Text("Preview variants without waiting for the Experiments assignment.")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.black.opacity(0.58))
            }

            ForEach(abTestPreviewGroups) { group in
                MacraABTestPreviewCard(group: group) { entry in
                    screenDemoButton(for: entry)
                }
            }
        }
    }

    private func screenDemoButton(for entry: MacraScreenDemoEntry) -> some View {
        Button {
            activeDemo = entry.demo
        } label: {
            MacraScreenDemoRow(entry: entry)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("macra-screen-demo-\(entry.id)-button")
    }
}

private enum MacraPaywallDemoAudience: String, CaseIterable, Identifiable {
    case nonSubscriber
    case existingSubscriber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nonSubscriber: return "New"
        case .existingSubscriber: return "Subscriber"
        }
    }

    var hasExistingSubscriptionAccess: Bool {
        self == .existingSubscriber
    }
}

private enum MacraDemoScreen: String, CaseIterable, Identifiable {
    case login
    case onboarding
    case onboardingControl
    case onboardingTrialPrepCompact
    case onboardingNoraGuided
    case onboardingHardPaywallValue
    case paywall
    case paywallAnnualDefault
    case paywallMonthlyVariant
    case paywallTrialPrepCompact
    case paywallHardPaywallValue
    case paywallCancelFeedback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login: return "Login"
        case .onboarding: return "Full Onboarding - Experiments"
        case .onboardingControl: return "Full Onboarding - Baseline"
        case .onboardingTrialPrepCompact: return "Full Onboarding - Compact"
        case .onboardingNoraGuided: return "Full Onboarding - Nora Guided"
        case .onboardingHardPaywallValue: return "Full Onboarding - Hard Paywall"
        case .paywall: return "Paywall - Experiments"
        case .paywallAnnualDefault: return "Paywall - Annual Baseline"
        case .paywallMonthlyVariant: return "Paywall - Monthly Variant"
        case .paywallTrialPrepCompact: return "Paywall - Trial Prep Compact"
        case .paywallHardPaywallValue: return "Paywall - Hard Value"
        case .paywallCancelFeedback: return "Cancel Feedback"
        }
    }

    var subtitle: String {
        switch self {
        case .login:
            return "Preview the returning-user auth page with email, password, reset, and Apple sign-in states."
        case .onboarding:
            return "Walk the first-run Macra flow using the active Experiments assignment."
        case .onboardingControl:
            return "Walk the first-run Macra flow into the current long paywall baseline."
        case .onboardingTrialPrepCompact:
            return "Walk the first-run Macra flow into the two prep screens and compact plan-first paywall."
        case .onboardingNoraGuided:
            return "Walk the third variant with the early intent question, Nora prompt bubbles, reminder simplification, and compact paywall."
        case .onboardingHardPaywallValue:
            return "Walk the paid-conversion variant with Nora guided onboarding and a monthly-first value paywall."
        case .paywall:
            return "Uses the active Experiments assignment for plan order, pricing copy, and analytics metadata."
        case .paywallAnnualDefault:
            return "Forces the baseline annual-first treatment so you can review the control arm."
        case .paywallMonthlyVariant:
            return "Forces the monthly-first treatment so you can review the lower-sticker-shock variant."
        case .paywallTrialPrepCompact:
            return "Forces the two-step trial prep and condensed plan-first paywall treatment."
        case .paywallHardPaywallValue:
            return "Forces the monthly-first value paywall built for immediate paid conversion."
        case .paywallCancelFeedback:
            return "Opens the new one-tap cancellation reason prompt on top of the paywall."
        }
    }

    var systemImage: String {
        switch self {
        case .login: return "key.fill"
        case .onboarding: return "list.bullet.clipboard.fill"
        case .onboardingControl: return "rectangle.stack.fill"
        case .onboardingTrialPrepCompact: return "rectangle.stack.fill"
        case .onboardingNoraGuided: return "sparkles"
        case .onboardingHardPaywallValue: return "creditcard.fill"
        case .paywall: return "creditcard.fill"
        case .paywallAnnualDefault: return "calendar.badge.clock"
        case .paywallMonthlyVariant: return "calendar"
        case .paywallTrialPrepCompact: return "rectangle.stack.fill"
        case .paywallHardPaywallValue: return "creditcard.fill"
        case .paywallCancelFeedback: return "questionmark.bubble.fill"
        }
    }

    var paywallDefaultPlanSelectionOverride: MacraPaywallDefaultPlanSelection? {
        switch self {
        case .onboardingControl, .onboardingTrialPrepCompact, .onboardingNoraGuided, .paywallAnnualDefault, .paywallTrialPrepCompact, .paywallCancelFeedback:
            return .annual
        case .onboardingHardPaywallValue, .paywallMonthlyVariant, .paywallHardPaywallValue:
            return .monthly
        case .login, .onboarding, .paywall:
            return nil
        }
    }

    var paywallLayoutVariantOverride: MacraPaywallLayoutVariant? {
        switch self {
        case .onboardingTrialPrepCompact, .onboardingNoraGuided, .paywallTrialPrepCompact:
            return .trialPrepCompact
        case .onboardingHardPaywallValue, .paywallHardPaywallValue:
            return .hardPaywallValue
        case .onboardingControl, .paywallAnnualDefault, .paywallMonthlyVariant, .paywallCancelFeedback:
            return .control
        case .login, .onboarding, .paywall:
            return nil
        }
    }

    var onboardingExperienceVariantOverride: MacraOnboardingExperienceVariant? {
        switch self {
        case .onboardingNoraGuided, .onboardingHardPaywallValue:
            return .noraGuided
        case .login, .onboarding, .onboardingControl, .onboardingTrialPrepCompact, .paywall, .paywallAnnualDefault, .paywallMonthlyVariant, .paywallTrialPrepCompact, .paywallHardPaywallValue, .paywallCancelFeedback:
            return nil
        }
    }

    var presentsCancelFeedbackOnAppear: Bool {
        self == .paywallCancelFeedback
    }

    var persistsCancelFeedbackInDemo: Bool {
        self == .paywallCancelFeedback
    }
}

private struct MacraScreenDemoEntry: Identifiable {
    let demo: MacraDemoScreen
    let title: String
    let subtitle: String
    let systemImage: String
    let badge: String?
    let idSuffix: String?

    var id: String {
        [demo.id, idSuffix].compactMap { $0 }.joined(separator: "-")
    }

    init(
        demo: MacraDemoScreen,
        title: String? = nil,
        subtitle: String? = nil,
        systemImage: String? = nil,
        badge: String? = nil,
        idSuffix: String? = nil
    ) {
        self.demo = demo
        self.title = title ?? demo.title
        self.subtitle = subtitle ?? demo.subtitle
        self.systemImage = systemImage ?? demo.systemImage
        self.badge = badge
        self.idSuffix = idSuffix
    }
}

private struct MacraABTestPreviewGroup: Identifiable {
    let id: String
    let title: String
    let parameter: String
    let summary: String
    let entries: [MacraScreenDemoEntry]
}

private struct MacraScreenDemoDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white.opacity(0.86))
                .frame(width: 38, height: 38)
                .background(Color.black.opacity(0.62))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close screen demo")
        .accessibilityIdentifier("macra-screen-demo-active-close-button")
    }
}

private struct MacraPaywallDemoAudienceToggle: View {
    @Binding var selection: MacraPaywallDemoAudience

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MacraPaywallDemoAudience.allCases) { audience in
                Button {
                    selection = audience
                } label: {
                    Text(audience.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(selection == audience ? .black : .white.opacity(0.78))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selection == audience ? Color.primaryGreen : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("macra-paywall-demo-\(audience.id)-toggle")
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.64))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct MacraScreenDemoRow: View {
    let entry: MacraScreenDemoEntry

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primaryGreen)
                .frame(width: 42, height: 42)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.title)
                        .font(.headline.weight(.bold))
                        .foregroundColor(.black)

                    if let badge = entry.badge {
                        Text(badge)
                            .font(.caption2.weight(.heavy))
                            .foregroundColor(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primaryGreen.opacity(0.86))
                            .clipShape(Capsule())
                    }
                }

                Text(entry.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.black.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black.opacity(0.45))
        }
        .padding(16)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct MacraABTestPreviewCard<Content: View>: View {
    let group: MacraABTestPreviewGroup
    let content: (MacraScreenDemoEntry) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(group.title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.black)

                Text(group.parameter)
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundColor(.black.opacity(0.6))

                Text(group.summary)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.black.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(group.entries) { entry in
                    content(entry)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

struct MacraScreenDemoView_Previews: PreviewProvider {
    static var previews: some View {
        MacraScreenDemoView(appCoordinator: AppCoordinator(serviceManager: ServiceManager()))
    }
}
#endif
