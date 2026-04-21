import SwiftUI

struct ContentView: View {
    @StateObject private var appCoordinator: AppCoordinator
    @ObservedObject private var serviceManager: ServiceManager
    private let reviewScreenshotMode = ProcessInfo.processInfo.environment["MACRA_CAPTURE_PAYWALL"] == "1"
    
    var isModalPresented: Binding<Bool> {
        Binding(
            get: { appCoordinator.modalScreen != nil },
            set: { newValue in
                if !newValue {
                    appCoordinator.modalScreen = nil
                }
            }
        )
    }
    
    init(serviceManager: ServiceManager) {
        _appCoordinator = StateObject(wrappedValue: AppCoordinator(serviceManager: serviceManager))
        self.serviceManager = serviceManager
    }
    
    private var mainView: some View {
        Group {
            if reviewScreenshotMode {
                MacraReviewPaywallScreenshotView()
            } else {
                appCoordinator.currentScreen.makeView(serviceManager: serviceManager, appCoordinator: appCoordinator)
            }
        }
    }
    
    private var activeUpdateReleaseBinding: Binding<MacraAppVersionPayload?> {
        Binding(
            get: { appCoordinator.activeUpdateRelease },
            set: { newValue in
                if newValue == nil {
                    appCoordinator.activeUpdateRelease = nil
                }
            }
        )
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            mainView

            if let notification = appCoordinator.notificationScreen {
                switch notification {
                case .notification(let viewModel):
                    CustomModalView(viewModel: viewModel)
                        .padding()
                }
            }

            if let toast = appCoordinator.toast {
                switch toast {
                    case .toast(let viewModel):
                        ToastView(viewModel: viewModel)
                            .padding()
                            .onTapGesture {
                                appCoordinator.hideToast()
                        }
                }
            }
        }
        .onAppear {
            appCoordinator.checkForPublishedUpdateIfNeeded()
        }
        .fullScreenCover(item: activeUpdateReleaseBinding) { release in
            MacraUpdateModalView(release: release) { markSeen in
                appCoordinator.dismissPublishedUpdate(markSeen: markSeen)
            }
        }
        .fullScreenCover(isPresented: isModalPresented) {
            if let modal = appCoordinator.modalScreen {
                ZStack {
                    switch modal {
                    case .aboutScreen:
                        AboutView(viewModel: AboutViewModel(appCoordinator: appCoordinator))
                    case .terms:
                        TermsConditionsView(viewModel: TermsConditionsViewModel(appCoordinator: appCoordinator))
                    case .privacyPolicy:
                        PrivacyPolicyView(viewModel: PrivacyPolicyViewModel(appCoordinator: appCoordinator))
//                    case .commandDetail(let command):
//                        if let userCommand = CommandService.sharedInstance.getUserCommand(command: command) {
//                            CommandDetailView(viewModel: CommandDetailViewModel(appCoordinator: appCoordinator, command: command, userCommand: userCommand))
//                        } else {
//                            CommandDetailView(viewModel: CommandDetailViewModel(appCoordinator: appCoordinator, command: command, userCommand: nil))
//                        }
                    case .registration:
                        RegistrationModal(viewModel: RegistrationModalViewModel(appCoordinator: appCoordinator))
                    case .calendar(let viewModel):
                        CalendarView(viewModel: viewModel)
                    case .payWall:
                        PayWallView(viewModel: PayWallViewModel(appCoordinator: appCoordinator))
                    case .manageSubscription:
                        ManageSubscriptionView(viewModel: ManageSubscriptionViewModel(appCoordinator: appCoordinator))
                    case .settings:
                        SettingsView(viewModel: SettingsViewModel(appCoordinator: appCoordinator))
                    case .macraNotificationSettings:
                        MacraNotificationSettingsView(appCoordinator: appCoordinator)
                    default:
                        EmptyView()
                    }
                    
                    if let notification = appCoordinator.notificationScreen {
                        switch notification {
                        case .notification(let viewModel):
                            CustomModalView(viewModel: viewModel)
                                .padding()

                        }
                    }
                    
                    if let toast = appCoordinator.toast {
                        switch toast {
                            case .toast(let viewModel):
                                ToastView(viewModel: viewModel)
                                    .padding()
                                    .onTapGesture {
                                        appCoordinator.hideToast()
                                }
                        }
                    }
                }
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(serviceManager: ServiceManager())
    }
}
