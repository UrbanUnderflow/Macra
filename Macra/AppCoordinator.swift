import Foundation
import SwiftUI
import RevenueCat

protocol Screen {
    func makeView(serviceManager: ServiceManager, appCoordinator: AppCoordinator) -> AnyView
}

final class AppCoordinator: ObservableObject {
    enum NutritionShellTab: String, CaseIterable, Identifiable {
        case journal
        case planner
        case scanner
        case supplements
        case more

        var id: String { rawValue }

        var title: String {
            switch self {
            case .journal:
                return "Journal"
            case .planner:
                return "Plan"
            case .scanner:
                return "Scan"
            case .supplements:
                return "Supps"
            case .more:
                return "More"
            }
        }

        var systemImage: String {
            switch self {
            case .journal:
                return "calendar.day.timeline.leading"
            case .planner:
                return "list.bullet.rectangle"
            case .scanner:
                return "camera.viewfinder"
            case .supplements:
                return "pills"
            case .more:
                return "ellipsis.circle"
            }
        }
    }

    enum NutritionShellDestination: Hashable {
        case journalComposer
        case mealPlanning
        case macroTargets
        case supplementTracker
        case mealHistory
        case insights
        case settings

        var title: String {
            switch self {
            case .journalComposer:
                return "Log a meal"
            case .mealPlanning:
                return "Meal planning"
            case .macroTargets:
                return "Macro targets"
            case .supplementTracker:
                return "Supplement tracker"
            case .mealHistory:
                return "Photo history"
            case .insights:
                return "Nutrition insights"
            case .settings:
                return "Settings"
            }
        }

        var subtitle: String {
            switch self {
            case .journalComposer:
                return "Start a new entry from photo, text, or voice."
            case .mealPlanning:
                return "Plan meals and move them back into today’s journal."
            case .macroTargets:
                return "Review targets and recommendation settings."
            case .supplementTracker:
                return "Track supplements and their nutrient contributions."
            case .mealHistory:
                return "Browse the saved meal and photo history."
            case .insights:
                return "See day analysis and AI-generated coaching."
            case .settings:
                return "Manage the shell, account, and subscription state."
            }
        }

        var systemImage: String {
            switch self {
            case .journalComposer:
                return "plus.circle.fill"
            case .mealPlanning:
                return "calendar.badge.plus"
            case .macroTargets:
                return "target"
            case .supplementTracker:
                return "pills.circle.fill"
            case .mealHistory:
                return "square.grid.2x2"
            case .insights:
                return "sparkles"
            case .settings:
                return "gearshape"
            }
        }
    }

    enum Screen {
        case splash
        case introView
        case registration
        case appIntro
        case macraSubscriptionRequired
        case home
        case log
        case changePassword
        case profile
        case aboutScreen
        case terms
        case privacyPolicy
        case settings
        case macraNotificationSettings
        case calendar(viewModel: CalendarViewModel)
        case payWall
        case manageSubscription
        case foodFeedback(feedback: FoodJournalFeedbackViewModel)
    }

    enum ToastNotification {
        case toast(viewModel: ToastViewModel)
    }

    enum NotificationScreen {
        case notification(viewModel: CustomModalViewModel)
    }

    @Published var currentScreen: Screen = .splash
    @Published var modalScreen: Screen?
    @Published var notificationScreen: NotificationScreen?
    @Published var toast: ToastNotification?
    @Published var nutritionShellTab: NutritionShellTab = .journal
    @Published var nutritionPath: [NutritionShellDestination] = []
    @Published var logMenuRequestID = 0
    @Published var activeUpdateRelease: MacraAppVersionPayload?
    private var didCheckForPublishedUpdateThisSession = false
    private var isCheckingForPublishedUpdate = false

    @ObservedObject var serviceManager: ServiceManager

    lazy var homeViewModel: HomeViewModel = {
        HomeViewModel(appCoordinator: self, serviceManager: serviceManager)
    }()

    init(serviceManager: ServiceManager) {
        self.serviceManager = serviceManager
    }

    func handleLogin() {
        if serviceManager.firebaseService.isAuthenticated {
            handleLoginSuccess()
        } else {
            showIntroScreen()
        }
    }

    func signUpUser(email: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
        serviceManager.firebaseService.signUpWithEmailAndPassword(email: email, password: password) { result in
            switch result {
            case .success:
                completion(.success("success"))
                self.serviceManager.showTabBar = true
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func signIn(email: String, password: String, completion: @escaping (Result<String, Error>) -> Void) {
        serviceManager.firebaseService.signInWithEmailAndPassword(email: email, password: password) { result in
            switch result {
            case .success:
                completion(.success("success"))
                self.serviceManager.showTabBar = true
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func handleLogout() {
        do {
            try serviceManager.firebaseService.signOut()
            serviceManager.userService.user = nil
            serviceManager.userService.isBetaUser = false
            serviceManager.userService.isSubscribed = false
            PurchaseService.sharedInstance.resetSubscriptionStatus()
            serviceManager.isConfigured = false
            serviceManager.showTabBar = false
            resetNutritionShell()
        } catch {
            print(error)
        }
        showIntroScreen()
    }

    func handleLoginSuccess() {
        serviceManager.showTabBar = true

        Task { [weak self] in
            await PurchaseService.sharedInstance.offering.start()
            self?.routeAuthenticatedUser()
        }
    }

    private func routeAuthenticatedUser() {
        serviceManager.userService.getUser { [weak self] user, error in
            guard let self else { return }

            if let error = error {
                print("Error fetching user for routing: \(error.localizedDescription)")
            }

            if user?.hasCompletedMacraOnboarding == true {
                self.routeMacraSubscriber(user: user)
                return
            }

            self.serviceManager.userService.hasSavedMacraProfile { [weak self] hasSavedProfile in
                guard let self else { return }

                guard hasSavedProfile else {
                    DispatchQueue.main.async {
                        self.showAppIntro()
                    }
                    return
                }

                self.serviceManager.userService.markMacraOnboardingComplete { _ in
                    self.routeMacraSubscriber(user: self.serviceManager.userService.user ?? user)
                }
            }
        }
    }

    private func routeMacraSubscriber(user: User?) {
        PurchaseService.sharedInstance.checkSubscriptionStatus(forceRefresh: true) { [weak self] result in
            let hasRevenueCatAccess: Bool
            switch result {
            case .success(let isSubscribed):
                hasRevenueCatAccess = isSubscribed
            case .failure(let error):
                print("Error checking subscription status: \(error)")
                hasRevenueCatAccess = false
            }

            let hasAccess = hasRevenueCatAccess ||
                user?.subscriptionType.grantsMacraAccess == true ||
                self?.serviceManager.userService.isBetaUser == true

            DispatchQueue.main.async {
                if hasAccess {
                    self?.showHomeScreen()
                    return
                }

                self?.showMacraSubscriptionRequired()
            }
        }
    }

    private func setCurrentScreen(_ newScreen: Screen) {
        withAnimation {
            currentScreen = newScreen
        }
    }

    private func resetNutritionShell() {
        nutritionShellTab = .journal
        nutritionPath.removeAll()
    }

    func showSplashScreen() {
        setCurrentScreen(.splash)
    }

    func showIntroScreen() {
        setCurrentScreen(.introView)
    }

    func showChangePassword() {
        currentScreen = .changePassword
    }

    func showProfile() {
        currentScreen = .profile
    }

    func showHomeScreen() {
        resetNutritionShell()
        setCurrentScreen(.home)
    }

    func showLogScreen() {
        nutritionShellTab = .journal
        nutritionPath.removeAll()
        setCurrentScreen(.home)
        logMenuRequestID += 1
    }

    func showAppIntro() {
        setCurrentScreen(.appIntro)
    }

    func showMacraSubscriptionRequired() {
        setCurrentScreen(.macraSubscriptionRequired)
    }

    func showFoodJournalFeedback(feedback: FoodJournalFeedbackViewModel) {
        currentScreen = .foodFeedback(feedback: feedback)
    }

    func showNutritionDestination(_ destination: NutritionShellDestination) {
        setCurrentScreen(.home)
        nutritionPath.append(destination)
    }

    func showNutritionTab(_ tab: NutritionShellTab) {
        nutritionShellTab = tab
        setCurrentScreen(.home)
    }

    func closeModals() {
        modalScreen = nil
    }

    func hideNotification() {
        notificationScreen = nil
    }

    func showToast(viewModel: ToastViewModel) {
        toast = .toast(viewModel: viewModel)

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.toast = nil
        }
    }

    func checkForPublishedUpdateIfNeeded(force: Bool = false) {
        guard force || !didCheckForPublishedUpdateThisSession else { return }
        guard !isCheckingForPublishedUpdate else { return }

        isCheckingForPublishedUpdate = true

        MacraVersionService.sharedInstance.fetchLatestVersionState { [weak self] modalState in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCheckingForPublishedUpdate = false
                self.didCheckForPublishedUpdateThisSession = true

                guard modalState.config.isEnabled,
                      let latestRelease = modalState.latestRelease else {
                    return
                }

                let shouldShow = MacraVersionService.shouldShowUpdate(
                    installedVersion: MacraVersionService.sharedInstance.currentInstalledVersion,
                    installedBuild: MacraVersionService.sharedInstance.currentInstalledBuild,
                    latestVersion: latestRelease.version,
                    latestBuild: latestRelease.buildNumber,
                    lastSeenReleaseKey: MacraVersionService.sharedInstance.lastSeenReleaseKey,
                    isCriticalUpdate: latestRelease.isCriticalUpdate
                )

                if shouldShow {
                    self.activeUpdateRelease = latestRelease
                }
            }
        }
    }

    func dismissPublishedUpdate(markSeen: Bool) {
        if markSeen, let activeUpdateRelease {
            MacraVersionService.sharedInstance.markReleaseSeen(
                version: activeUpdateRelease.version,
                buildNumber: activeUpdateRelease.buildNumber
            )
        }
        activeUpdateRelease = nil
    }

    func showPayWallModal() {
        modalScreen = .payWall
    }

    func showManageSubscriptionModal() {
        modalScreen = .manageSubscription
    }

    func showCalendarModal(viewModel: CalendarViewModel) {
        modalScreen = .calendar(viewModel: viewModel)
    }

    func hideToast() {
        toast = nil
    }

    func showPrivacyScreenModal() {
        modalScreen = .privacyPolicy
    }

    func showRegisterModal() {
        modalScreen = .registration
    }

    func showSettingsModal() {
        modalScreen = .settings
    }

    func showMacraNotificationSettingsModal() {
        modalScreen = .macraNotificationSettings
    }

    func showNotificationModal(viewModel: CustomModalViewModel) {
        notificationScreen = .notification(viewModel: viewModel)
    }

    func showLogAnEventModal() {
        notificationScreen = .notification(viewModel: CustomModalViewModel(type: .log, title: "Choose an event", message: "What time did this occur?", primaryButtonTitle: "Log", primaryAction: { _ in
            self.hideNotification()
            self.showToast(viewModel: ToastViewModel(message: "Your log has been added successfully", backgroundColor: .ash, textColor: .primaryPurple))
        }, secondaryAction: {
            self.hideNotification()
        }))
    }
}

extension AppCoordinator.Screen: Screen {
    func makeView(serviceManager: ServiceManager, appCoordinator: AppCoordinator) -> AnyView {
        switch self {
        case .splash:
            return AnyView(
                SplashLoader(viewModel: SplashLoaderViewModel(serviceManager: serviceManager, appCoordinator: appCoordinator))
                    .onAppear {
                        Task {
                            await serviceManager.configure()
                            try? await Task.sleep(nanoseconds: 900_000_000)

                            await MainActor.run {
                                appCoordinator.handleLogin()
                            }
                        }
                    }
            )
        case .introView:
            return AnyView(
                IntroView(viewModel: IntroViewViewModel(serviceManager: serviceManager, appCoordinator: appCoordinator))
            )
        case .appIntro:
            return AnyView(
                MacraOnboardingFlowView(appCoordinator: appCoordinator)
            )
        case .macraSubscriptionRequired:
            return AnyView(
                MacraOnboardingFlowView(appCoordinator: appCoordinator, startingStep: .commitTrial)
            )
        case .home:
            return AnyView(
                HomeView(viewModel: appCoordinator.homeViewModel)
            )
        case .changePassword:
            return AnyView(
                ChangePasswordView(viewModel: ChangePasswordViewModel(appCoordinator: appCoordinator, serviceManager: serviceManager))
            )
        case .profile:
            return AnyView(
                ProfileView(viewModel: ProfileViewModel(serviceManager: serviceManager, appCoordinator: appCoordinator))
            )
        case .registration:
            return AnyView(
                RegistrationView()
            )
        case .payWall:
            return AnyView(EmptyView())
        case .manageSubscription:
            return AnyView(EmptyView())
        case .aboutScreen:
            return AnyView(EmptyView())
        case .terms:
            return AnyView(EmptyView())
        case .privacyPolicy:
            return AnyView(EmptyView())
        case .calendar:
            return AnyView(EmptyView())
        case .settings:
            return AnyView(EmptyView())
        case .macraNotificationSettings:
            return AnyView(EmptyView())
        case .log:
            return AnyView(EmptyView())
        case .foodFeedback:
            return AnyView(EmptyView())
        }
    }
}
