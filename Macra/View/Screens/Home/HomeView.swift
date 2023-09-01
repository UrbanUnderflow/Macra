import SwiftUI

class HomeViewModel: ObservableObject {
    let appCoordinator: AppCoordinator
    let serviceManager: ServiceManager
    
    @Published var showLoader = false
    
    init(appCoordinator: AppCoordinator, serviceManager: ServiceManager) {
        self.appCoordinator = appCoordinator
        self.serviceManager = serviceManager
    }
}

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        FoodJournalView(viewModel: FoodJournalViewModel(serviceManager: viewModel.serviceManager, appCoordinator: viewModel.appCoordinator))
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(viewModel: HomeViewModel(appCoordinator: AppCoordinator(serviceManager: ServiceManager()), serviceManager: ServiceManager()))
    }
}
