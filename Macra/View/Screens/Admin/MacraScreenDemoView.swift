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

                    VStack(spacing: 12) {
                        ForEach(MacraDemoScreen.allCases) { demo in
                            Button {
                                activeDemo = demo
                            } label: {
                                MacraScreenDemoRow(demo: demo)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("macra-screen-demo-\(demo.id)-button")
                        }
                    }
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
            case .onboarding:
                MacraOnboardingFlowView(
                    appCoordinator: appCoordinator,
                    isDemoMode: true,
                    usesLivePurchasesInDemo: true,
                    onDemoDismiss: { activeDemo = nil },
                    existingSubscriptionAccessOverride: paywallDemoAudience.hasExistingSubscriptionAccess
                )
                .environment(\.isMacraDemoMode, true)
                .overlay(alignment: .topTrailing) {
                    screenDemoPaywallControls
                }
            case .paywall:
                PayWallView(
                    viewModel: PayWallViewModel(appCoordinator: appCoordinator),
                    isDemoMode: true,
                    usesLivePurchasesInDemo: true,
                    onDismiss: { activeDemo = nil },
                    existingSubscriptionAccessOverride: paywallDemoAudience.hasExistingSubscriptionAccess
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
    case paywall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login: return "Login"
        case .onboarding: return "Full Onboarding"
        case .paywall: return "Paywall"
        }
    }

    var subtitle: String {
        switch self {
        case .login:
            return "Preview the returning-user auth page with email, password, reset, and Apple sign-in states."
        case .onboarding:
            return "Walk the first-run Macra flow with mocked profile, plan, meals, and purchase."
        case .paywall:
            return "Live App Store/RevenueCat products with real sandbox purchase, restore, and existing-subscriber paths."
        }
    }

    var systemImage: String {
        switch self {
        case .login: return "key.fill"
        case .onboarding: return "list.bullet.clipboard.fill"
        case .paywall: return "creditcard.fill"
        }
    }
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
    let demo: MacraDemoScreen

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: demo.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primaryGreen)
                .frame(width: 42, height: 42)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(demo.title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.black)

                Text(demo.subtitle)
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

struct MacraScreenDemoView_Previews: PreviewProvider {
    static var previews: some View {
        MacraScreenDemoView(appCoordinator: AppCoordinator(serviceManager: ServiceManager()))
    }
}
#endif
