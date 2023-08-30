import Foundation
import SwiftUI

class AboutViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator
    
    init(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
    }
}

struct AboutView: View {
    @State private var continuePressed: Bool = false
    @ObservedObject var viewModel: AboutViewModel
    
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
                ZStack {
                    Color.black
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(alignment: .leading) {
                        Spacer()
                        HStack {
                            Text("Welcome to QuickLifts.")
                                .font(.system(size: 50, weight: .bold))
                                .foregroundColor(.secondaryWhite)
                                .padding()
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Spacer()
                        }
                        
                        (Text("Your friendly AI-powered ") + Text("fitness partner!").bold().foregroundColor(.black))
                            .foregroundColor(.secondaryWhite)
                            .padding()
                            .multilineTextAlignment(.leading)
                        
                        Text("QuickLifts is based on the idea that an effective, body-transforming workout doesn't require hours in the gym; in fact, it can be achieved in just 40 minutes. Our goal is to help you make the most out of your fitness journey in the shortest time possible, in a way that's fun, personalized, and highly effective.")
                            .foregroundColor(.secondaryWhite)
                            .padding()
                            .multilineTextAlignment(.leading)
                        
                        Text("QuickLifts integrates the power of advanced AI technology, ChatGPT, to bring you a unique fitness experience. It's not just a digital workout diary to record your strength training sessions, but a smart fitness guide that learns your training habits, recognizes patterns, and helps you improve your exercises. It's like having a personal trainer who knows you well, but is available any time you need!")
                            .foregroundColor(.secondaryWhite)
                            .padding()
                            .multilineTextAlignment(.leading)
                        
                        Text("With the AI-driven insights, QuickLifts offers personalized workout suggestions, specifically tailored to your needs and goals. It tracks your progress, calculating how much weight you've lifted over time and how many reps you've completed, then uses this data to make intelligent recommendations for your future workouts.")
                            .foregroundColor(.secondaryWhite)
                            .padding()
                            .multilineTextAlignment(.leading)
                        
                        Text("But that's not all - it can even predict your body goal achievements. Imagine having a crystal ball that can show you how close you are to reaching your fitness targets based on your current workout data. That's the power of QuickLifts!")
                            .foregroundColor(.secondaryWhite)
                            .padding()
                            .multilineTextAlignment(.leading)
                        
                        Text("QuickLifts doesn't just document your fitness journey - it optimizes it. Every set, rep, and weight you record is analyzed and used to help you grow stronger and reach your goals faster. Plus, you can jot down notes or feedback about each workout, helping both you and the AI understand your exercise experience better.")
                            .foregroundColor(.secondaryWhite)
                            .padding()
                            .multilineTextAlignment(.leading)
                        
                        Text("Whether you're a fitness newbie or a seasoned weightlifter, QuickLifts adapts to your needs and grows with you. It's all about making your workouts work for you. And remember, it's not about how long you spend in the gym, it's about how you spend that time. With QuickLifts and the power of AI, we're here to make sure every minute counts towards a healthier, stronger you!")
                            .foregroundColor(.secondaryWhite)
                            .padding()
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                    }
                }
            }
        }
        .ignoresSafeArea(.all)
        .background(Color.gray)
    }
}
