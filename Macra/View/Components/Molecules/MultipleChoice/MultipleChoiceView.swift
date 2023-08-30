import Foundation
import SwiftUI

class MultipleChoiceViewModel: ObservableObject {
    @Published var question: String
    @Published var options: [String]
    @Published var selectedOptions: [String]
    @Published var isMultiselect: Bool

    init(question: String, options: [String], isMultiselect: Bool, selectedOptions: [String] = []) {
        self.question = question
        self.options = options
        self.selectedOptions = selectedOptions
        self.isMultiselect = isMultiselect
    }

    func selectOption(_ option: String) {
        if isMultiselect {
            if selectedOptions.contains(option) {
                selectedOptions.removeAll(where: { $0 == option })
            } else {
                selectedOptions.append(option)
            }
        } else {
            selectedOptions = [option]
        }
    }
}

struct MultipleChoiceView: View {
    @ObservedObject var viewModel: MultipleChoiceViewModel
    let onSubmittedAnswer: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack {
                ForEach(viewModel.options, id: \.self) { option in
                    Button(action: {
                        viewModel.selectOption(option)
                        onSubmittedAnswer(viewModel.selectedOptions)
                    }) {
                        HStack {
                            VStack(alignment: .center, spacing:0) {
                                Text(option.capitalized)
                                    .foregroundColor(.white)
                                    .font(.title3)
                                    .bold()
                                    .padding(.bottom, 5)
                                Text("3 - 14 weeks")
                                    .font(.subheadline)
                            }
                            .padding()
                            Text("Puppy is highly receptive to new experiences, making it an ideal time for socialization and foundational training.")
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                    .padding(.vertical)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                viewModel.selectedOptions.contains(option) ? Color.black : Color.white,
                                lineWidth: 2
                            )
                    )
                    .background(viewModel.selectedOptions.contains(option) ? Color.black.opacity(0.1) : Color.clear)
                }
            }
            .padding(.horizontal, 26)
        }
        .ignoresSafeArea(.all)
    }
}


struct MultipleChoiceView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.white
            MultipleChoiceView(viewModel: MultipleChoiceViewModel(question: "What is your favorite color?", options: ["Red", "Blue", "Green", "Yellow"], isMultiselect: false), onSubmittedAnswer: { selectedOptions in
                print("Selected options: \(selectedOptions)")
            })
        }
    }
}
