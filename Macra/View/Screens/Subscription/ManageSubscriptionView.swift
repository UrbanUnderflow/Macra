import SwiftUI
import RevenueCat
import StoreKit

@MainActor
final class ManageSubscriptionViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator
    @Published private(set) var isLoading: Bool = true
    @Published private(set) var productIdentifier: String?
    @Published private(set) var planDisplayName: String = "Macra Plus"
    @Published private(set) var cadenceLabel: String = ""
    @Published private(set) var priceLabel: String = ""
    @Published private(set) var renewalDate: Date?
    @Published private(set) var willRenew: Bool = true
    @Published private(set) var isInTrial: Bool = false
    @Published private(set) var isLifetime: Bool = false

    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }

    var headerBadge: String {
        if isInTrial { return "Free trial" }
        if isLifetime { return "Lifetime access" }
        if willRenew { return "Active — auto-renews" }
        return "Active — cancels at period end"
    }

    var renewalLineTitle: String {
        if isLifetime { return "No expiration" }
        if willRenew && !isInTrial { return "Next renewal" }
        if willRenew && isInTrial { return "Trial ends" }
        return "Access ends"
    }

    var formattedRenewalDate: String {
        guard let renewalDate else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: renewalDate)
    }

    var daysRemainingLabel: String? {
        guard let renewalDate else { return nil }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfRenewal = calendar.startOfDay(for: renewalDate)
        guard let days = calendar.dateComponents([.day], from: startOfToday, to: startOfRenewal).day else {
            return nil
        }
        if days <= 0 { return nil }
        return days == 1 ? "1 day left" : "\(days) days left"
    }

    func load() {
        isLoading = true
        Purchases.shared.getCustomerInfo { [weak self] customerInfo, _ in
            Task { @MainActor in
                self?.apply(customerInfo: customerInfo)
            }
        }
    }

    func openAppStoreManagement() {
        #if targetEnvironment(macCatalyst)
        if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
        #else
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            Task {
                try? await AppStore.showManageSubscriptions(in: scene)
            }
        } else if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    func openChangePlan() {
        appCoordinator.closeModals()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.appCoordinator.showPayWallModal()
        }
    }

    func restore() {
        PurchaseService.sharedInstance.restoreSubscriptionStatus { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.load()
                case .failure:
                    self?.appCoordinator.showToast(
                        viewModel: ToastViewModel(
                            message: "We couldn't restore any purchases on this account.",
                            backgroundColor: .secondaryCharcoal,
                            textColor: .secondaryWhite
                        )
                    )
                }
            }
        }
    }

    private func apply(customerInfo: CustomerInfo?) {
        defer { isLoading = false }

        let userPlan = UserService.sharedInstance.user?.subscriptionType
        if userPlan == .lifetime {
            isLifetime = true
            planDisplayName = "Macra Plus"
            cadenceLabel = "Lifetime"
            priceLabel = ""
            willRenew = false
            isInTrial = false
            renewalDate = nil
            return
        }

        guard let customerInfo else {
            applyFallback(userPlan: userPlan)
            return
        }

        let entitlement = customerInfo.entitlements.active["plus"] ?? customerInfo.entitlements.active.values.first
        let activeProductID = entitlement?.productIdentifier
            ?? customerInfo.activeSubscriptions.first
            ?? (userPlan.flatMap { productIdentifier(for: $0) })

        productIdentifier = activeProductID

        if let activeProductID {
            renewalDate = entitlement?.expirationDate ?? customerInfo.expirationDate(forProductIdentifier: activeProductID)
        } else {
            renewalDate = entitlement?.expirationDate ?? customerInfo.latestExpirationDate
        }

        if let entitlement {
            willRenew = entitlement.willRenew
            isInTrial = entitlement.periodType == .trial
        } else {
            willRenew = true
            isInTrial = false
        }

        cadenceLabel = cadenceLabel(for: activeProductID, fallback: userPlan)
        planDisplayName = "Macra Plus"

        if let activeProductID,
           let pkg = package(forIdentifier: activeProductID) {
            priceLabel = pkg.price
        } else {
            priceLabel = ""
        }
    }

    private func applyFallback(userPlan: SubscriptionType?) {
        isInTrial = false
        willRenew = true
        renewalDate = nil
        priceLabel = ""
        cadenceLabel = cadenceLabel(for: nil, fallback: userPlan)
    }

    private func productIdentifier(for plan: SubscriptionType) -> String? {
        switch plan {
        case .monthly: return "rc_monthly"
        case .annual: return "rc_annual"
        default: return nil
        }
    }

    private func cadenceLabel(for productID: String?, fallback: SubscriptionType?) -> String {
        if let productID {
            if productID.contains("annual") || productID.contains("yearly") { return "Annual" }
            if productID.contains("monthly") { return "Monthly" }
        }
        switch fallback {
        case .annual: return "Annual"
        case .monthly: return "Monthly"
        case .lifetime: return "Lifetime"
        case .beta: return "Beta access"
        default: return "Active"
        }
    }

    private func package(forIdentifier identifier: String) -> PackageViewModel? {
        let offering = OfferingViewModel.sharedInstance
        if let yearly = offering.yearlyPackage, yearly.package.storeProduct.productIdentifier == identifier {
            return yearly
        }
        if let monthly = offering.monthlyPackage, monthly.package.storeProduct.productIdentifier == identifier {
            return monthly
        }
        return nil
    }
}

struct ManageSubscriptionView: View {
    @ObservedObject var viewModel: ManageSubscriptionViewModel

    var body: some View {
        ZStack {
            ManageSubscriptionBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    planCard
                    detailsCard
                    actionsSection
                    supportLinks
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }

            VStack {
                HStack {
                    Button {
                        viewModel.appCoordinator.closeModals()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondaryCharcoal)
                            .frame(width: 32, height: 32)
                            .background(Color.secondaryWhite)
                            .clipShape(Circle())
                    }
                    .padding(.leading, 20)
                    .padding(.top, 12)
                    Spacer()
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { viewModel.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer().frame(height: 50)

            Text("SUBSCRIPTION")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundColor(.primaryGreen)

            Text("Your plan")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.secondaryWhite)

            Text("Manage your Macra Plus membership and renewal.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondaryWhite.opacity(0.6))
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primaryGreen)

                Text(viewModel.headerBadge)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundColor(.primaryGreen)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.primaryGreen.opacity(0.14)))

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(viewModel.planDisplayName)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.secondaryWhite)
                if !viewModel.cadenceLabel.isEmpty {
                    Text(viewModel.cadenceLabel.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundColor(.secondaryWhite.opacity(0.6))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().strokeBorder(Color.secondaryWhite.opacity(0.25), lineWidth: 1)
                        )
                }
            }

            if !viewModel.priceLabel.isEmpty {
                Text(viewModel.priceLabel)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondaryWhite.opacity(0.85))
            }

            Divider().background(Color.secondaryWhite.opacity(0.12))

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.renewalLineTitle.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundColor(.secondaryWhite.opacity(0.55))
                    Text(viewModel.formattedRenewalDate)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondaryWhite)
                }
                Spacer()
                if let days = viewModel.daysRemainingLabel {
                    Text(days)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primaryBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primaryBlue.opacity(0.18)))
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.secondaryWhite.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.secondaryWhite.opacity(0.14), lineWidth: 1)
        )
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRow(
                iconName: "arrow.clockwise",
                title: "Auto-renew",
                value: viewModel.willRenew ? "On" : "Off"
            )
            DetailRow(
                iconName: "creditcard",
                title: "Billing",
                value: "Managed through Apple"
            )
            if viewModel.isInTrial {
                DetailRow(
                    iconName: "gift",
                    title: "Trial status",
                    value: "In free trial"
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.secondaryWhite.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.secondaryWhite.opacity(0.1), lineWidth: 1)
        )
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            Button(action: viewModel.openAppStoreManagement) {
                ActionRow(
                    iconName: "gearshape.fill",
                    title: "Manage in App Store",
                    subtitle: "Change billing, cancel, or update payment"
                )
            }

            Button(action: viewModel.openChangePlan) {
                ActionRow(
                    iconName: "arrow.up.right.circle.fill",
                    title: "Change plan",
                    subtitle: "Switch between monthly and annual"
                )
            }
        }
    }

    private var supportLinks: some View {
        HStack(spacing: 10) {
            FooterPill(icon: "arrow.triangle.2.circlepath", label: "Restore") {
                viewModel.restore()
            }
            FooterPill(icon: "doc.text", label: "Terms") { }
            FooterPill(icon: "hand.raised", label: "Privacy") {
                viewModel.appCoordinator.showPrivacyScreenModal()
            }
        }
        .padding(.top, 4)
    }
}

private struct DetailRow: View {
    let iconName: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primaryBlue)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primaryBlue.opacity(0.16)))

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondaryWhite.opacity(0.72))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondaryWhite)
        }
    }
}

private struct ActionRow: View {
    let iconName: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primaryGreen)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.primaryGreen.opacity(0.16)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondaryWhite)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondaryWhite.opacity(0.55))
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondaryWhite.opacity(0.45))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondaryWhite.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.secondaryWhite.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct FooterPill: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.secondaryWhite.opacity(0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.secondaryWhite.opacity(0.05))
            .overlay(
                Capsule().strokeBorder(Color.secondaryWhite.opacity(0.1), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }
}

private struct ManageSubscriptionBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.secondaryCharcoal,
                    Color.primaryBlue.opacity(0.85),
                    Color.primaryBlue.opacity(0.55),
                    Color.secondaryPink.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Color.secondaryCharcoal.opacity(0.35)
                .ignoresSafeArea()
        }
    }
}

struct ManageSubscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        ManageSubscriptionView(
            viewModel: ManageSubscriptionViewModel(
                appCoordinator: AppCoordinator(serviceManager: ServiceManager())
            )
        )
    }
}
