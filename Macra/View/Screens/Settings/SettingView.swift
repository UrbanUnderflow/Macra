import SwiftUI

class SettingsViewModel: ObservableObject {
    let appCoordinator: AppCoordinator
        
    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var userService = UserService.sharedInstance
    @ObservedObject private var purchaseService = PurchaseService.sharedInstance
    @State var showMailView = false

    private var subscriptionSubtitle: String {
        purchaseService.isSubscribed ? "Current Plan: Macra Plus" : "Not subscribed — tap to subscribe"
    }

    private var headerView: some View {
        HStack {
            Text("Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.secondaryWhite)
            Spacer()
        }
    }

    var body: some View {
        ZStack {
            Color.primaryPurple
                .ignoresSafeArea(.all)

            ScrollView {
                Spacer()
                    .frame(height: 50)
                VStack(alignment: .leading, spacing: 10) {
                    headerView
                        .padding(10)
                    SettingsProfileHeader(
                        user: userService.user,
                        isSubscribed: purchaseService.isSubscribed
                    )
                    .padding(.bottom, 8)
//                    SettingCard(title: "Account Settings")
//                    SettingCard(title: "Notification Settings")
//                    SettingCard(title: "Privacy Settings")
//                    SettingCard(title: "Language")
                    SettingCard(title: "Subscription Plan", subtitle: subscriptionSubtitle)
                        .onTapGesture {
                            viewModel.appCoordinator.closeModals()
                            if purchaseService.isSubscribed {
                                viewModel.appCoordinator.showManageSubscriptionModal()
                            } else {
                                viewModel.appCoordinator.showPayWallModal()
                            }
                        }
                    SettingCard(title: "Notifications", subtitle: "Meal reminders, check-ins, emails")
                        .onTapGesture {
                            viewModel.appCoordinator.showMacraNotificationSettingsModal()
                        }
                    SettingCard(title: "Privacy Policy", subtitle: "")
                        .onTapGesture {
                            viewModel.appCoordinator.showPrivacyScreenModal()
                        }
                    SettingCard(title: "Terms and Conditions", subtitle: "")
                        .onTapGesture {
                            viewModel.appCoordinator.showPrivacyScreenModal()
                        }
//                    SettingCard(title: "Help & Support")
//                        .onTapGesture {
//                            showMailView.toggle()
//                        }
//                        .sheet(isPresented: $showMailView) {
//                                        MailView(subject: "Support from \(UserService.sharedInstance.user?.username ?? "User")", body: "", recipients: ["quickliftsapp@gmail.com"], isPresented: self.$showMailView)
//                                    }
                    SettingCard(title: "About", subtitle: "")
                        .onTapGesture {
                            //viewModel.appCoordinator.showAboutScreenModal()
                        }
                    Button {
                        viewModel.appCoordinator.showNotificationModal(viewModel: CustomModalViewModel(type: .field, title: "Delete Account", message: "Are you sure you want to delete your account?", primaryButtonTitle: "Yes, delete my account", secondaryButtonTitle: "Cancel", fieldSubtitle: "Enter your password to confirm deletion.", primaryAction: { message in
                            viewModel.appCoordinator.serviceManager.userService.deleteAccount(email: UserService.sharedInstance.user?.email ?? "", password: message) { result in
                                switch result {
                                case .success(_):
                                    self.viewModel.appCoordinator.handleLogout()
                                case .failure(_):
                                    self.viewModel.appCoordinator.showToast(viewModel: ToastViewModel(message: "There was an issue deleting your account. Please contact admin", backgroundColor: .red, textColor: .white))
                                }
                            }
                        }, secondaryAction: {
                            viewModel.appCoordinator.hideNotification()
                        }))
                    } label: {
                        SettingCard(title: "Delete Account", subtitle: "")
                    }
                    
                    Button {
                        main {
                            viewModel.appCoordinator.closeModals()
                            viewModel.appCoordinator.handleLogout()
                        }
                    } label: {
                        SettingCard(title: "Log out", subtitle: "")
                    }
                }
                .padding(.horizontal)
            }
            
            VStack {
                HStack {
                    IconImage(.sfSymbol(.close, color: .gray))
                        .padding(.leading, 30)
                        .onTapGesture {
                            viewModel.appCoordinator.closeModals()
                        }
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

private struct SettingsProfileHeader: View {
    let user: User?
    let isSubscribed: Bool

    private var email: String {
        let value = user?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Macra profile" : value
    }

    var body: some View {
        HStack(spacing: 14) {
            ProfileImageBubble(imageURL: user?.profileImageURL ?? "", fallbackText: email)

            VStack(alignment: .leading, spacing: 5) {
                Text("Profile")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.secondaryWhite)

                Text(email)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondaryWhite.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(isSubscribed ? "Macra Plus active" : "Free plan")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primaryGreen)
            }

            Spacer()
        }
        .padding(18)
        .background(Color.secondaryWhite.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.secondaryWhite.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ProfileImageBubble: View {
    let imageURL: String
    let fallbackText: String

    private var initials: String {
        guard let first = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "" }
        return String(first).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.secondaryWhite.opacity(0.92))

            if !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                RemoteImage(url: imageURL)
                    .scaledToFill()
                    .frame(width: 62, height: 62)
                    .clipShape(Circle())
            } else if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primaryPurple)
            } else {
                Text(initials)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primaryPurple)
            }
        }
        .frame(width: 62, height: 62)
        .overlay(
            Circle()
                .strokeBorder(Color.primaryGreen.opacity(0.85), lineWidth: 2)
        )
    }
}

struct SettingCard: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment:.leading, spacing: 0) {
                    Text(title)
                        .foregroundColor(.secondaryWhite)
                        .font(.headline)
                        .bold()
                    if subtitle != "" {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondaryWhite.opacity(0.5))
                    }
                }
                Spacer()
                IconImage(.sfSymbol(.chevRight, color: Color.secondaryWhite), width: 14, height: 14)

            }
            .padding()
//            Divider(color: .white.opacity(0.2), height: 2)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(viewModel: SettingsViewModel(appCoordinator: AppCoordinator(serviceManager: ServiceManager())))
    }
}
