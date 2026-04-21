import SwiftUI

@MainActor
final class AppShellCoordinator: ObservableObject {
    @Published var selectedTab: AppCoordinator.NutritionShellTab = .journal
    @Published var navigationPath: [AppCoordinator.NutritionShellDestination] = []

    func reset() {
        selectedTab = .journal
        navigationPath.removeAll()
    }

    func select(tab: AppCoordinator.NutritionShellTab) {
        selectedTab = tab
    }

    func push(_ destination: AppCoordinator.NutritionShellDestination) {
        navigationPath.append(destination)
    }
}
