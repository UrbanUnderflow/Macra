import Foundation
import SwiftUI

class StageSelectionViewModel: ObservableObject {
    @Published var options: [String] = ["Puppy", "Teen", "Adult", "Senior"] // Using String for demonstration.
}

struct StageSelectionView: View {
    @ObservedObject var viewModel: StageSelectionViewModel
    let onSubmittedAnswer: (String) -> Void
    @State var selectedOption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack {
                ForEach(viewModel.options, id: \.self) { option in
                    Button(action: {
                        selectedOption = option
                        onSubmittedAnswer(option)
                    }) {
                        HStack {
                            Text(option)
                                .foregroundColor(selectedOption == option ? Color.secondaryPink : .secondaryWhite)
                                .font(.title3)
                                .bold()
                                .padding()
                            Spacer()
                            // Replace with additional content as needed
                        }
                    }
                    .padding(.vertical)
                    .background(Color.primaryPurple)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                selectedOption == option ? Color.secondaryPink : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .background(selectedOption == option ? Color.primaryPurple.opacity(0.1) : Color.clear)
                }
            }
            .padding(.horizontal, 26)
        }
        .ignoresSafeArea(.all)
        .onAppear {
            if let item = viewModel.options.first {
                selectedOption = item
            }
        }
    }
}

struct StageSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.white
            StageSelectionView(viewModel: StageSelectionViewModel(), onSubmittedAnswer: { selectedOption in
                print("Selected option: \(selectedOption)")
            })
        }
    }
}
