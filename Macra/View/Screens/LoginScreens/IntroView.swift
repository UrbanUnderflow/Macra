import SwiftUI
import AVKit

class IntroViewViewModel: ObservableObject {
    var serviceManager: ServiceManager
    var appCoordinator: AppCoordinator
    @Published var loginPressed: Bool = false
    @Published var newUser: Bool = false
    
    init(serviceManager: ServiceManager, appCoordinator: AppCoordinator) {
        self.serviceManager = serviceManager
        self.appCoordinator = appCoordinator
    }
    
    func newUserButtonPressed(){
        self.loginPressed = true
        self.newUser = true
    }
    
    func existingUserButtonPressed() {
        self.loginPressed = true
        self.newUser = false
    }
    
}

struct IntroView: View {
    @ObservedObject var viewModel: IntroViewViewModel
    @State private var selection = 0
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(viewModel.loginPressed ? Color.primaryPurple : .black)
                .opacity(viewModel.loginPressed ? 0.5 : 0.3)
            if !viewModel.loginPressed {
                Group {
                    VStack {
                        Text("Macra")
                            .font(.largeTitle)
                            .bold()
                            .foregroundColor(.white)
                            .padding()
                            .padding(.top, 60)
                        
                        TabView(selection: $selection) {
                            // Onboarding texts
                            OnboardingView(title: "Food Journal", description: "Just write what you ate, AI will do the rest.")
                            OnboardingView(title: "Macro Breakdown", description: "Know the full nutritional breakdown of everything you ate")
                            OnboardingView(title: "Insights", description: "Recieve AI insights about your eating habits.")
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                        .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                        
                        Spacer()
                        
                        HStack {
                            Spacer()
                            Button(action: {
                                viewModel.existingUserButtonPressed()
                            }) {
                                Text("Returning User")
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(Color.black)
                            .cornerRadius(30)
                            Spacer()
                                .frame(width:20)
                            Button(action: {
                                viewModel.newUserButtonPressed()
                            }) {
                                Text("New User")
                                    .foregroundColor(.black)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(30)
                            Spacer()
                        }
                        .padding(.bottom, 50)
                    }
                }
                .foregroundColor(.white)
            } else {
                LoginView(viewModel: LoginViewModel(appCoordinator: viewModel.appCoordinator, isSignUp: viewModel.newUser))
                    .frame(width:.infinity, height: .infinity)
                    .ignoresSafeArea(.all)
            }
        }
        .background(
            IconImage(.custom(.background))
                    .aspectRatio(contentMode: .fill)
        )
        .clipped()
        .edgesIgnoringSafeArea(.all)
    }
}


struct OnboardingView: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title2)
                .bold()
            Text(description)
                .multilineTextAlignment(.center)
                .padding()
        }
        .padding()
    }
}


struct IntroScreen_Previews: PreviewProvider {
    static var previews: some View {
        IntroView(viewModel: IntroViewViewModel(serviceManager: ServiceManager(), appCoordinator: AppCoordinator(serviceManager: ServiceManager())))
    }
}

