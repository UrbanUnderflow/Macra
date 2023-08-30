import SwiftUI

class SettingsViewModel: ObservableObject {
    let appCoordinator: AppCoordinator
        
    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State var showMailView = false

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
//                    SettingCard(title: "Account Settings")
//                    SettingCard(title: "Notification Settings")
//                    SettingCard(title: "Privacy Settings")
//                    SettingCard(title: "Language")
                    SettingCard(title: "Subscription Plan", subtitle: "Current Plan: \(UserService.sharedInstance.user?.subscriptionType.rawValue.capitalized ?? "Monthly")")
                        .onTapGesture {
                            viewModel.appCoordinator.closeModals()
                            viewModel.appCoordinator.showPayWallModal()
                            
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
