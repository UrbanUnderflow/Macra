import SwiftUI

final class SplashLoaderViewModel: ObservableObject {
    var serviceManager: ServiceManager
    var appCoordinator: AppCoordinator

    init(serviceManager: ServiceManager, appCoordinator: AppCoordinator) {
        self.serviceManager = serviceManager
        self.appCoordinator = appCoordinator
    }
}

struct SplashLoader: View {
    @State var viewModel: SplashLoaderViewModel
    @State private var reveal = false

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 12) {
                Text("MACRA")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color.primaryGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Pulse nutrition intelligence")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.68))
            }
            .opacity(reveal ? 1 : 0.15)
            .scaleEffect(reveal ? 1 : 0.94)

            VStack {
                Spacer()
                Text("Powered by Pulse Intelligence Labs, Inc.")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.6)
                    .foregroundColor(Color.white.opacity(0.5))
                    .padding(.bottom, 32)
                    .opacity(reveal ? 1 : 0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    reveal = true
                }
            }
        }
    }
}

struct SplashLoader_Previews: PreviewProvider {
    static var previews: some View {
        SplashLoader(
            viewModel: SplashLoaderViewModel(
                serviceManager: ServiceManager(),
                appCoordinator: AppCoordinator(serviceManager: ServiceManager())
            )
        )
    }
}
