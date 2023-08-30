import Foundation
import SwiftUI

class PrivacyPolicyViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator
    
    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }
}

struct PrivacyPolicyView: View {
    @ObservedObject var viewModel: PrivacyPolicyViewModel

    var body: some View {
        VStack {
            HStack {
                CloseButtonView {
                    viewModel.appCoordinator.closeModals()
                }
                .padding(.leading, 20)
                .padding(.top, 50)
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading) {
                    Text("Privacy Policy")
                        .font(.system(size: 50, weight: .bold))
                        .foregroundColor(.secondaryWhite)
                        .padding()
                        .multilineTextAlignment(.leading)
                    
                    Text("At QuickLifts, we respect your privacy and take the protection of personal information very seriously. This Privacy Policy outlines how we collect, use, and protect your information.")
                        .foregroundColor(.secondaryWhite)
                        .padding()
                        .multilineTextAlignment(.leading)
                    
                    Text("Information We Collect:")
                        .font(.title2)
                        .foregroundColor(.secondaryWhite)
                        .padding()
                        .multilineTextAlignment(.leading)
                    
                    // List what data you collect...
                    
                    Text("How We Use Information:")
                        .font(.title2)
                        .foregroundColor(.secondaryWhite)
                        .padding()
                        .multilineTextAlignment(.leading)
                    
                    // Describe how you use the data...
                    
                    Text("QuickLifts Rights:")
                        .font(.title2)
                        .foregroundColor(.secondaryWhite)
                        .padding()
                        .multilineTextAlignment(.leading)
                    
                    Text("QuickLifts retains rights to all content uploaded to the app and can use it for improving the service, research, and promotional purposes.")
                        .foregroundColor(.secondaryWhite)
                        .padding()
                        .multilineTextAlignment(.leading)
                    
                    
                    Spacer()
                }
            }
        }
        .foregroundColor(.white)
        .edgesIgnoringSafeArea(.all)
    }
}
