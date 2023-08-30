//
//  FoodJournalView.swift
//  FoodJournal
//
//  Created by Tremaine Grant on 8/29/23.
//

import SwiftUI

class FoodJournalViewModel: ObservableObject {
    let serviceManager: ServiceManager
    let appCoordinator: AppCoordinator
    
    @Published var showLoader = false
    @Published var introComplete = false

    init(serviceManager: ServiceManager, appCoordinator: AppCoordinator) {
        self.serviceManager = serviceManager
        self.appCoordinator = appCoordinator
    }
    
    func logEntry(_ entry: Entry, completion: @escaping () -> Void) {
        // Update your question here and provide feedback and insights
        self.serviceManager.gptService.analyzeFood(entry.text) { result in
            switch result {
            case .success(let feedback):
                let newFeedback = FoodJournalFeedback(id: UUID().uuidString, calories: feedback.calories, carbs: feedback.carbs, protein: feedback.protein, fat: feedback.fat, foodEvaluation: feedback.foodEvaluation, personalizedFeedback: feedback.personalizedFeedback, unhealthyItems: feedback.unhealthyItems, score: feedback.score, sentiment: feedback.sentiment, journalEntry: entry.text)
                
                self.serviceManager.entryService.logEntry(entry: newFeedback) { message, error  in
                    print(message)
                    self.appCoordinator.showFoodJournalFeedback(feedback: FoodJournalFeedbackViewModel(appCoordinator: self.appCoordinator, title: "Food Feedback", calorieRange: newFeedback.calories, proteinRange: newFeedback.protein, fatRange: newFeedback.fat, carbRange: newFeedback.carbs, foodEvaluationItems: newFeedback.foodEvaluation, personalizedFeedback: newFeedback.personalizedFeedback, unhealthyIngredientsItems: newFeedback.unhealthyItems))
                }
            case .failure(let error):
                print(error.localizedDescription)
                completion()
            }
        }
    }
}

struct FoodJournalView: View {
    @ObservedObject var viewModel: FoodJournalViewModel

    var body: some View {
        ZStack {
            Color.primaryBlue
            if viewModel.introComplete {
                VStack {
                    Spacer()
                    EntryPanelView(viewModel: EntryPanelViewModel(serviceManager: viewModel.serviceManager, isLoading: viewModel.showLoader), onSubmittedAnswer: { answer in
                            updateLoader(true)
                        viewModel.logEntry(Entry(id: UUID().uuidString, text: answer, sentiment: "", sentimentScore: 0, aiFeedback: "", createdAt: Date(), updatedAt: Date()), completion: {
                            updateLoader(false)
                        })
                    })
                    Spacer()
                }
                .padding(25)
            } else {
                FoodJournalIntroView(viewModel: viewModel)
            }
        }
        .ignoresSafeArea(.all)
        .overlay(
            viewModel.showLoader ? Loader() : nil,
            alignment: .center
        )
    }
    
    func updateLoader(_ show: Bool) {
        DispatchQueue.main.async {
            withAnimation(.default) {
                viewModel.showLoader = show
            }
        }
    }
}

struct FoodJournalIntroView: View {
    @ObservedObject var viewModel: FoodJournalViewModel
    
    var headerView: some View {
        VStack {
            HStack {
                Text("Food Journal")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.secondaryWhite)
                    .padding(.top, 152)
                    .padding(.leading, 28)
                Spacer()
            }
        }
    }
    
    var introText: some View {
        Text("To make the most of this feature, here are some tips: \n\n1. Be as descriptive as possible. Include details such as serving size, brand, and weight of your meals.\n2. If you know the weight of what you ate, that's perfect! If not, our AI will give its best effort to make the estimate. \n3. The more descriptive you are with your entries, the more accurate the food analysis and recommendation will be.")
            .font(.body)
            .foregroundColor(Color.secondaryWhite)
            .multilineTextAlignment(.leading)
            .padding()
    }
    
    var nextButton: some View {
        Button(action: {
            // Next action
            viewModel.introComplete
        }) {
            Text("Let's Go!")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(Color.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange)
                .cornerRadius(10)
        }
        .padding()
    }
    
    var body: some View {
        ZStack {
            Color.primaryBlue
            VStack {
                Spacer()
                introText
                nextButton
                Spacer()
            }
        }
        .ignoresSafeArea(.all)
    }
}


struct FoodJournalView_Previews: PreviewProvider {
    static var previews: some View {
        FoodJournalView(viewModel: FoodJournalViewModel(serviceManager: ServiceManager(), appCoordinator: AppCoordinator(serviceManager: ServiceManager())))
    }
}
