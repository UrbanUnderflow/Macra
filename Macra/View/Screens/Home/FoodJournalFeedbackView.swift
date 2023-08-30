//
//  FoodJournalFeedbackView.swift
//  FoodJournal
//
//  Created by Tremaine Grant on 8/29/23.
//

import SwiftUI

import Foundation
import SwiftUI

class FoodJournalFeedbackViewModel: ObservableObject {
    @Published var appCoordinator: AppCoordinator
    @Published var title: String
    @Published var calorieRange: String
    @Published var proteinRange: String
    @Published var fatRange: String
    @Published var carbRange: String
    @Published var foodEvaluationItems: String
    @Published var personalizedFeedback: String
    @Published var unhealthyIngredientsItems: String
    @Published var proteinPercentage: Double?
    @Published var fatPercentage: Double?
    @Published var carbPercentage: Double?
    
    init(appCoordinator: AppCoordinator, title: String, calorieRange: String, proteinRange: String, fatRange: String, carbRange: String, foodEvaluationItems: String, personalizedFeedback: String, unhealthyIngredientsItems: String) {
        self.appCoordinator = appCoordinator
        self.title = title
        self.calorieRange = calorieRange
        self.proteinRange = proteinRange
        self.fatRange = fatRange
        self.carbRange = carbRange
        self.foodEvaluationItems = foodEvaluationItems
        self.personalizedFeedback = personalizedFeedback
        self.unhealthyIngredientsItems = unhealthyIngredientsItems
        
        updateMacronutrientPercentages()
    }
    
    func updateMacronutrientPercentages() {
            let proteinCalories = medianFromRange(proteinRange) * 4
            let fatCalories = medianFromRange(fatRange) * 9
            let carbCalories = medianFromRange(carbRange) * 4
            
            let totalCalories = (proteinCalories + fatCalories + carbCalories)
            
            self.proteinPercentage = proteinCalories / totalCalories
            self.fatPercentage = fatCalories / totalCalories
            self.carbPercentage = carbCalories / totalCalories
    }
        
    func medianFromRange(_ range: String) -> Double {
        //Remove any non-digit and non-separator characters from the string
        let cleanedString = range.components(separatedBy: CharacterSet.decimalDigits.inverted)
                                  .filter { !$0.isEmpty }
                                  .joined(separator: "-")
            
        let values = cleanedString.components(separatedBy: "-").compactMap { Double($0) }
        guard values.count == 2 else { return 0 }
        let median = (values[0] + values[1]) / 2.0
        return median
    }
}

struct FoodJournalFeedbackView: View {
    @ObservedObject var viewModel: FoodJournalFeedbackViewModel
    
    private var proteinLabel: some View {
        HStack(spacing: 20) {
            Circle()
                .fill(Color.orange)
                .frame(width: 16, height: 16)
            Text("Protein")
                .foregroundColor(.white)
        }
    }

    private var carbsLabel: some View {
        HStack(spacing: 20) {
            Circle()
                .fill(Color.orange.opacity(0.7))
                .frame(width: 16, height: 16)
            Text("Carbohydrates")
                .foregroundColor(.white)
        }
    }

    private var fatLabel: some View {
        HStack(spacing: 20) {
            Circle()
                .fill(Color.orange.opacity(0.4))
                .frame(width: 16, height: 16)
            Text("Fat")
                .foregroundColor(.white)
        }
    }

    
    private var legend: some View {
        VStack(alignment: .leading) {
            proteinLabel
            carbsLabel
            fatLabel
        }
    }
    
    private var comparisonChart: some View {
        PieChartView(data: [
            PieChartModel(name: "Protein", value: viewModel.proteinPercentage ?? 0.0),
            PieChartModel(name: "Carbohydrates", value: viewModel.carbPercentage ?? 0.0),
            PieChartModel(name: "Fat", value: viewModel.fatPercentage ?? 0.0)
        ])
        .frame(width: 100, height: 100) // adjust the height to suit your needs
    }
    
    var body: some View {
        VStack {
            ScrollView(.vertical, showsIndicators: false) {
                headerView
                VStack(spacing: 24) {
                    HStack {
                        legend
                        Spacer()
                        comparisonChart
                        Spacer()
                    }
                    .padding(.vertical, 30)
                    macronutrientCard
                    foodEvaluationCard
                    personalizedFeedbackCard
                    unhealthyIngredientsCard
                    doneButton
                        .padding(.bottom, 36)
                }
                .padding(.horizontal, 24)
            }
            .background(Color.primaryBlue.ignoresSafeArea())
        }
    }

    private var headerView: some View {
        VStack {
            HStack {
                Text(viewModel.title)
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.secondaryWhite)
                    .padding(.top, 152)
                    .padding(.leading, 28)
                Spacer()
            }
        }
    }
    
    private var macronutrientCard: some View {
        VStack {
            ZStack {
                Color.lightBlue
                VStack(alignment: .leading, spacing: 8) {
                    Text("Macronutrient Analysis")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.secondaryWhite)
                        .bold()
                        .padding(.top, 26)
                        .padding(.bottom)
                    
                    Text("Total Calories: \(viewModel.calorieRange) calories")
                        .font(.body)
                        .foregroundColor(.secondaryWhite)
                    
                    Text("Protein: \(viewModel.proteinRange) grams")
                        .font(.body)
                        .foregroundColor(.secondaryWhite)
                    
                    Text("Fat: \(viewModel.fatRange) grams")
                        .font(.body)
                        .foregroundColor(.secondaryWhite)
                    
                    Text("Carbohydrates: \(viewModel.carbRange) grams")
                        .font(.body)
                        .foregroundColor(.secondaryWhite)
                }
                .padding(.bottom, 26)
            }
            .background(Color.white)
            .cornerRadius(16)
        }
    }
    
    private var foodEvaluationCard: some View {
        VStack {
            ZStack {
                Color.lightBlue
                VStack(alignment: .leading, spacing: 8) {
                    Text("Food Evaluation")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.secondaryWhite)
                        .bold()
                        .padding(.top, 26)
                        .padding(.bottom)
                    
                    Text(viewModel.foodEvaluationItems)
                        .font(.body)
                        .foregroundColor(.secondaryWhite)
                }
                .padding(.bottom, 26)
            }
            .background(Color.white)
            .cornerRadius(16)
        }
    }
    
    private var personalizedFeedbackCard: some View {
        VStack {
            ZStack {
                Color.lightBlue
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personalized Feedback")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.secondaryWhite)
                        .bold()
                        .padding(.top, 26)
                        .padding(.bottom)
                    
                    Text(viewModel.personalizedFeedback)
                        .font(.body)
                        .foregroundColor(.secondaryWhite)
                }
                .padding(.bottom, 26)
            }
            .background(Color.white)
            .cornerRadius(16)
        }
    }
    
    private var unhealthyIngredientsCard: some View {
        VStack {
            ZStack {
                Color.lightBlue
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unhealthy/Harmful Ingredients")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.secondaryWhite)
                        .bold()
                        .padding(.top, 26)
                        .padding(.bottom)
                    
                    Text(viewModel.unhealthyIngredientsItems)
                        .font(.body)
                        .foregroundColor(.secondaryWhite)
                }
                .padding(.bottom, 26)
            }
            .background(Color.white)
            .cornerRadius(16)
        }
    }
    
    private var doneButton: some View {
        ConfirmationButton(title: "Done", type: .primaryLargeConfirmation) {
            viewModel.appCoordinator.closeModals()
        }
    }
}

struct FoodJournalFeedbackView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = FoodJournalFeedbackViewModel(
            appCoordinator: AppCoordinator(serviceManager: ServiceManager()), title: "Food Journal Feedback",
            calorieRange: "2000 - 2500",
            proteinRange: "50 - 60",
            fatRange: "70 - 80",
            carbRange: "90 - 100",
            foodEvaluationItems: "This is a test food evaluation item.",
            personalizedFeedback: "This is a test personalized feedback.",
            unhealthyIngredientsItems: "These are test unhealthy ingredients items."
        )

        // You need to call `updateMacronutrientPercentages()` method to calculate the percentages.
        viewModel.updateMacronutrientPercentages()

        return FoodJournalFeedbackView(viewModel: viewModel)
    }
}
